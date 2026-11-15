"""Task operations with server-enforced assignment and access rules."""
from datetime import date
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..core.errors import ForbiddenError, NotFoundError, RuleError
from ..core.time import utc_now
from ..core.rules import (
    TASK_COMPLETED,
    TASK_TODO,
    VIEWER,
    can_log_in,
    is_admin,
    is_viewer,
    require_can_mutate,
    require_project_access,
    validate_task_assignment,
)
from ..models import Assignee, Project, Task
from . import analytics_service, notification_service
from ..schemas.task import BulkTaskResult, BulkTaskResultOut


def list_tasks(
    db: Session,
    *,
    actor: Assignee,
    project_id: int | None,
    assignee_id: int | None,
    limit: int = 20,
    offset: int = 0,
) -> tuple[list[Task], int]:
    """Tasks of one project or of one assignee, newest first."""
    if (project_id is None) == (assignee_id is None):
        raise RuleError("Provide project_id or assignee_id.")
    if project_id is not None:
        if not is_admin(actor.role) and actor.project_id != project_id:
            raise ForbiddenError("You can only view your own project tasks.")
        query = select(Task).where(Task.project_id == project_id)
    else:
        target = db.get(Assignee, assignee_id)
        if target is None:
            raise NotFoundError("Account not found.")
        if not is_admin(actor.role) and (
            actor.project_id is None or target.project_id != actor.project_id
        ):
            raise ForbiddenError(
                "You can only view your own project members' tasks."
            )
        query = select(Task).where(Task.assignee_id == assignee_id)
    # MySQL DATETIME has second precision, so tasks created in the same second
    # tie on created_at. The id is monotonic and makes "newest first" stable.
    query = query.order_by(Task.created_at.desc(), Task.id.desc())
    total = db.scalar(select(func.count()).select_from(query.subquery()))
    items = list(db.scalars(query.limit(limit).offset(offset)).all())
    return items, total


def create_task(
    db: Session,
    *,
    actor: Assignee,
    project_id: int,
    title: str,
    description: str | None,
    priority: str,
    due_date: date | None,
    assignee_id: int | None,
) -> Task:
    require_can_mutate(actor.role)
    require_project_access(actor.role, actor.project_id, project_id)
    if db.get(Project, project_id) is None:
        raise NotFoundError("Project not found.")
    if assignee_id is not None:
        assignee = db.get(Assignee, assignee_id)
        if assignee is None:
            raise NotFoundError("Account not found.")
        if not can_log_in(assignee.status):
            raise RuleError("Tasks can only be assigned to active members.")
        validate_task_assignment(
            task_project_id=project_id,
            assignee_id=assignee_id,
            assignee_project_id=assignee.project_id,
        )
    task = Task(
        title=title,
        description=description,
        priority=priority,
        due_date=due_date,
        project_id=project_id,
        assignee_id=assignee_id,
    )
    db.add(task)
    db.commit()
    db.refresh(task)
    # Record analytics event.
    analytics_service.record_event(
        db,
        project_id=project_id,
        actor_id=actor.id,
        event_type="task_created",
        task_id=task.id,
    )
    db.commit()
    # Notify the assignee (if any) after the task is persisted.
    if assignee_id is not None:
        target = db.get(Assignee, assignee_id)
        project = db.get(Project, project_id)
        notification_service.notify_task_created(
            db,
            task=task,
            actor=actor,
            project_name=project.name if project else "",
            assignee=target,
        )
        db.commit()
    return task


def bulk_complete_tasks(
    db: Session,
    *,
    actor: Assignee,
    task_ids: list[int],
) -> BulkTaskResultOut:
    """Bulk complete multiple tasks (actor must have mutate access to each)."""
    require_can_mutate(actor.role)
    results: list[BulkTaskResult] = []
    for tid in task_ids:
        try:
            complete_task(db, actor=actor, task_id=tid)
            results.append(BulkTaskResult(task_id=tid, success=True))
        except Exception as e:
            results.append(BulkTaskResult(task_id=tid, success=False, error=str(e)))
    return BulkTaskResultOut(
        results=results,
        total=len(results),
        succeeded=sum(1 for r in results if r.success),
        failed=sum(1 for r in results if not r.success),
    )


def bulk_reassign_tasks(
    db: Session,
    *,
    actor: Assignee,
    task_ids: list[int],
    new_assignee_id: int,
) -> BulkTaskResultOut:
    """Bulk reassign multiple tasks to a new assignee."""
    require_can_mutate(actor.role)
    results: list[BulkTaskResult] = []
    for tid in task_ids:
        try:
            # Reuse the single-task update so assignment validation, the
            # notification, and the analytics event stay consistent.
            update_task(db, actor=actor, task_id=tid, changes={"assignee_id": new_assignee_id})
            results.append(BulkTaskResult(task_id=tid, success=True))
        except Exception as e:
            results.append(BulkTaskResult(task_id=tid, success=False, error=str(e)))
    return BulkTaskResultOut(
        results=results,
        total=len(results),
        succeeded=sum(1 for r in results if r.success),
        failed=sum(1 for r in results if not r.success),
    )


def bulk_delete_tasks(
    db: Session,
    *,
    actor: Assignee,
    task_ids: list[int],
) -> BulkTaskResultOut:
    """Bulk delete multiple tasks."""
    require_can_mutate(actor.role)
    results: list[BulkTaskResult] = []
    for tid in task_ids:
        try:
            delete_task(db, actor=actor, task_id=tid)
            results.append(BulkTaskResult(task_id=tid, success=True))
        except Exception as e:
            results.append(BulkTaskResult(task_id=tid, success=False, error=str(e)))
    return BulkTaskResultOut(
        results=results,
        total=len(results),
        succeeded=sum(1 for r in results if r.success),
        failed=sum(1 for r in results if not r.success),
    )


def update_task(
    db: Session,
    *,
    actor: Assignee,
    task_id: int,
    changes: dict[str, Any],
) -> Task:
    """Apply a partial update; null clears optional fields.

    The project never changes here, so the same access rule as every other
    task mutation applies. Reassignment validates the new person just like
    creation does.
    """
    require_can_mutate(actor.role)
    if not changes:
        raise RuleError("Nothing to update.")
    task = _load_task(db, actor=actor, task_id=task_id)
    previous_assignee_id = task.assignee_id
    if "title" in changes:
        if changes["title"] is None:
            raise RuleError("Title is required.")
        task.title = changes["title"]
    if "description" in changes:
        task.description = changes["description"]
    if "priority" in changes:
        if changes["priority"] is not None:
            task.priority = changes["priority"]
    if "due_date" in changes:
        task.due_date = changes["due_date"]
    if "assignee_id" in changes:
        assignee_id = changes["assignee_id"]
        if assignee_id is not None:
            assignee = db.get(Assignee, assignee_id)
            if assignee is None:
                raise NotFoundError("Account not found.")
            if not can_log_in(assignee.status):
                raise RuleError("Tasks can only be assigned to active members.")
            validate_task_assignment(
                task_project_id=task.project_id,
                assignee_id=assignee_id,
                assignee_project_id=assignee.project_id,
            )
        task.assignee_id = assignee_id
    task.updated_at = utc_now()
    db.commit()
    db.refresh(task)
    # Notify when the assignee changed.
    if (
        task.assignee_id is not None
        and task.assignee_id != previous_assignee_id
    ):
        target = db.get(Assignee, task.assignee_id)
        project = db.get(Project, task.project_id)
        notification_service.notify_task_assigned(
            db,
            task=task,
            actor=actor,
            project_name=project.name if project else "",
            assignee=target,
            previous_assignee_id=previous_assignee_id,
        )
        analytics_service.record_event(
            db,
            project_id=task.project_id,
            actor_id=actor.id,
            event_type="task_assigned",
            task_id=task.id,
        )
        db.commit()
    return task


def _load_task(db: Session, *, actor: Assignee, task_id: int) -> Task:
    task = db.get(Task, task_id)
    if task is None:
        raise NotFoundError("Task not found.")
    require_project_access(actor.role, actor.project_id, task.project_id)
    return task


def complete_task(db: Session, *, actor: Assignee, task_id: int) -> Task:
    require_can_mutate(actor.role)
    task = _load_task(db, actor=actor, task_id=task_id)
    now = utc_now()
    task.status = TASK_COMPLETED
    task.completed_at = now
    task.updated_at = now
    db.commit()
    db.refresh(task)
    # Notify the assignee (if different from the actor).
    if task.assignee_id is not None and task.assignee_id != actor.id:
        target = db.get(Assignee, task.assignee_id)
        project = db.get(Project, task.project_id)
        notification_service.notify_task_completed(
            db,
            task=task,
            actor=actor,
            project_name=project.name if project else "",
            assignee=target,
        )
    analytics_service.record_event(
        db,
        project_id=task.project_id,
        actor_id=actor.id,
        event_type="task_completed",
        task_id=task.id,
    )
    db.commit()
    return task


def reopen_task(db: Session, *, actor: Assignee, task_id: int) -> Task:
    require_can_mutate(actor.role)
    task = _load_task(db, actor=actor, task_id=task_id)
    task.status = TASK_TODO
    task.completed_at = None
    task.updated_at = utc_now()
    db.commit()
    db.refresh(task)
    # Notify the assignee (if different from the actor).
    if task.assignee_id is not None and task.assignee_id != actor.id:
        target = db.get(Assignee, task.assignee_id)
        project = db.get(Project, task.project_id)
        notification_service.notify_task_reopened(
            db,
            task=task,
            actor=actor,
            project_name=project.name if project else "",
            assignee=target,
        )
    analytics_service.record_event(
        db,
        project_id=task.project_id,
        actor_id=actor.id,
        event_type="task_reopened",
        task_id=task.id,
    )
    db.commit()
    return task


def delete_task(db: Session, *, actor: Assignee, task_id: int) -> None:
    require_can_mutate(actor.role)
    task = _load_task(db, actor=actor, task_id=task_id)
    task_id = task.id
    project_id = task.project_id
    task_title = task.title
    assignee_id = task.assignee_id
    db.delete(task)
    db.commit()
    # Notify the former assignee (if any and different from the actor).
    if assignee_id is not None and assignee_id != actor.id:
        project = db.get(Project, project_id)
        notification_service.notify_task_deleted(
            db,
            task_title=task_title,
            actor=actor,
            project_name=project.name if project else "",
            assignee_id=assignee_id,
        )
    analytics_service.record_event(
        db,
        project_id=project_id,
        actor_id=actor.id,
        event_type="task_deleted",
        task_id=task_id,
    )
    db.commit()
