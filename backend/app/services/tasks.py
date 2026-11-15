"""Task operations with server-enforced assignment and access rules."""
from datetime import date
from typing import Any

from sqlalchemy import delete as sa_delete, func, select
from sqlalchemy.orm import Session

from ..core.errors import (
    ApiError,
    ForbiddenError,
    NotFoundError,
    RuleError,
)
from ..core.rules import (
    TASK_COMPLETED,
    TASK_TODO,
    can_log_in,
    is_admin,
    require_can_mutate,
    require_project_access,
    validate_task_assignment,
)
from ..core.time import utc_now
from ..models import Assignee, Comment, Project, Subtask, Task
from .access import load_task
from .events import (
    TASK_ASSIGNED,
    TASK_COMPLETED as EVENT_TASK_COMPLETED,
    notify,
    record_event,
)


def list_tasks(
    db: Session,
    *,
    actor: Assignee,
    project_id: int | None,
    assignee_id: int | None,
    limit: int = 20,
    offset: int = 0,
) -> tuple[list[Task], int]:
    """One page of a project's or person's tasks, newest first, with total."""
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
    total = db.scalar(select(func.count()).select_from(query.subquery()))
    items = list(
        db.scalars(
            query.order_by(Task.created_at.desc(), Task.id.desc()).limit(limit).offset(offset)
        ).all()
    )
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
    require_project_access(actor.role, actor.project_id, project_id)
    require_can_mutate(actor.role)
    if db.get(Project, project_id) is None:
        raise NotFoundError("Project not found.")
    if assignee_id is not None:
        assignee = _validated_assignee(db, project_id=project_id, assignee_id=assignee_id)
    task = Task(
        title=title,
        description=description,
        priority=priority,
        due_date=due_date,
        project_id=project_id,
        assignee_id=assignee_id,
    )
    db.add(task)
    db.flush()
    record_event(
        db,
        project_id=project_id,
        event_type="task_created",
        actor=actor,
        task_id=task.id,
    )
    if assignee_id is not None:
        _notify_assignment(db, actor=actor, task=task)
    db.commit()
    db.refresh(task)
    return task


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
    if not changes:
        raise RuleError("Nothing to update.")
    task = load_task(db, actor=actor, task_id=task_id, write=True)
    reassigned = False
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
            _validated_assignee(
                db, project_id=task.project_id, assignee_id=assignee_id
            )
        reassigned = task.assignee_id != assignee_id
        task.assignee_id = assignee_id
    task.updated_at = utc_now()
    record_event(
        db,
        project_id=task.project_id,
        event_type="task_assigned" if reassigned else "task_updated",
        actor=actor,
        task_id=task.id,
    )
    if reassigned:
        _notify_assignment(db, actor=actor, task=task)
    db.commit()
    db.refresh(task)
    return task


def complete_task(db: Session, *, actor: Assignee, task_id: int) -> Task:
    task = load_task(db, actor=actor, task_id=task_id, write=True)
    was_completed = task.status == TASK_COMPLETED
    now = utc_now()
    task.status = TASK_COMPLETED
    task.completed_at = now
    task.updated_at = now
    if not was_completed:
        record_event(
            db,
            project_id=task.project_id,
            event_type="task_completed",
            actor=actor,
            task_id=task.id,
        )
        if task.assignee_id is not None and task.assignee_id != actor.id:
            notify(
                db,
                account_id=task.assignee_id,
                type=EVENT_TASK_COMPLETED,
                title="Task completed",
                body=f'"{task.title}" was completed.',
                payload=str(task.id),
            )
    db.commit()
    db.refresh(task)
    return task


def reopen_task(db: Session, *, actor: Assignee, task_id: int) -> Task:
    task = load_task(db, actor=actor, task_id=task_id, write=True)
    task.status = TASK_TODO
    task.completed_at = None
    task.updated_at = utc_now()
    record_event(
        db,
        project_id=task.project_id,
        event_type="task_reopened",
        actor=actor,
        task_id=task.id,
    )
    db.commit()
    db.refresh(task)
    return task


def delete_task(db: Session, *, actor: Assignee, task_id: int) -> None:
    task = load_task(db, actor=actor, task_id=task_id, write=True)
    record_event(
        db,
        project_id=task.project_id,
        event_type="task_deleted",
        actor=actor,
        task_id=task.id,
    )
    _delete_task_children(db, task_id=task.id)
    db.delete(task)
    db.commit()


def bulk_complete(
    db: Session, *, actor: Assignee, task_ids: list[int]
) -> dict:
    require_can_mutate(actor.role)
    return _run_bulk(
        db,
        actor=actor,
        task_ids=task_ids,
        action=lambda task_id: complete_task(db, actor=actor, task_id=task_id),
    )


def bulk_reassign(
    db: Session,
    *,
    actor: Assignee,
    task_ids: list[int],
    assignee_id: int,
) -> dict:
    require_can_mutate(actor.role)
    target = db.get(Assignee, assignee_id)
    if target is None:
        raise NotFoundError("Account not found.")
    if not can_log_in(target.status):
        raise RuleError("Tasks can only be assigned to active members.")

    def reassign(task_id: int) -> Task:
        task = load_task(db, actor=actor, task_id=task_id, write=True)
        validate_task_assignment(
            task_project_id=task.project_id,
            assignee_id=assignee_id,
            assignee_project_id=target.project_id,
        )
        return update_task(
            db,
            actor=actor,
            task_id=task_id,
            changes={"assignee_id": assignee_id},
        )

    return _run_bulk(db, actor=actor, task_ids=task_ids, action=reassign)


def bulk_delete(
    db: Session, *, actor: Assignee, task_ids: list[int]
) -> dict:
    require_can_mutate(actor.role)

    def remove(task_id: int) -> None:
        delete_task(db, actor=actor, task_id=task_id)

    return _run_bulk(db, actor=actor, task_ids=task_ids, action=remove)


def _run_bulk(
    db: Session, *, actor: Assignee, task_ids: list[int], action
) -> dict:
    """Run [action] per id, keeping successes when one row fails rule checks."""
    results: list[dict] = []
    for task_id in task_ids:
        try:
            action(task_id)
            results.append({"task_id": task_id, "success": True, "error": None})
        except ApiError as error:
            db.rollback()
            results.append(
                {"task_id": task_id, "success": False, "error": error.message}
            )
    succeeded = sum(1 for row in results if row["success"])
    return {
        "results": results,
        "total": len(results),
        "succeeded": succeeded,
        "failed": len(results) - succeeded,
    }


def _validated_assignee(
    db: Session, *, project_id: int, assignee_id: int
) -> Assignee:
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
    return assignee


def _notify_assignment(
    db: Session, *, actor: Assignee, task: Task
) -> None:
    if task.assignee_id is None or task.assignee_id == actor.id:
        return
    notify(
        db,
        account_id=task.assignee_id,
        type=TASK_ASSIGNED,
        title="New task assigned",
        body=f'You were assigned "{task.title}".',
        payload=str(task.id),
    )


def _delete_task_children(db: Session, *, task_id: int) -> None:
    db.execute(sa_delete(Comment).where(Comment.task_id == task_id))
    db.execute(sa_delete(Subtask).where(Subtask.task_id == task_id))
