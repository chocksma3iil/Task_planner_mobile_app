"""Task operations with server-enforced assignment and access rules."""
from datetime import date
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..core.errors import ForbiddenError, NotFoundError, RuleError
from ..core.time import utc_now
from ..core.rules import (
    TASK_COMPLETED,
    TASK_TODO,
    can_log_in,
    is_admin,
    require_project_access,
    validate_task_assignment,
)
from ..models import Assignee, Project, Task


def list_tasks(
    db: Session,
    *,
    actor: Assignee,
    project_id: int | None,
    assignee_id: int | None,
) -> list[Task]:
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
    return list(db.scalars(query.order_by(Task.created_at.desc())).all())


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
    task = _load_task(db, actor=actor, task_id=task_id)
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
    return task


def _load_task(db: Session, *, actor: Assignee, task_id: int) -> Task:
    task = db.get(Task, task_id)
    if task is None:
        raise NotFoundError("Task not found.")
    require_project_access(actor.role, actor.project_id, task.project_id)
    return task


def complete_task(db: Session, *, actor: Assignee, task_id: int) -> Task:
    task = _load_task(db, actor=actor, task_id=task_id)
    now = utc_now()
    task.status = TASK_COMPLETED
    task.completed_at = now
    task.updated_at = now
    db.commit()
    db.refresh(task)
    return task


def reopen_task(db: Session, *, actor: Assignee, task_id: int) -> Task:
    task = _load_task(db, actor=actor, task_id=task_id)
    task.status = TASK_TODO
    task.completed_at = None
    task.updated_at = utc_now()
    db.commit()
    db.refresh(task)
    return task


def delete_task(db: Session, *, actor: Assignee, task_id: int) -> None:
    task = _load_task(db, actor=actor, task_id=task_id)
    db.delete(task)
    db.commit()
