"""Subtask operations (checklist items attached to a task)."""
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..core.errors import ForbiddenError, NotFoundError
from ..core.rules import require_can_mutate
from ..models import Assignee, Subtask, Task
from . import analytics_service


def list_subtasks(db: Session, *, actor: Assignee, task_id: int) -> list[Subtask]:
    """All subtasks of a task, newest first."""
    task = db.get(Task, task_id)
    if task is None:
        raise NotFoundError("Task not found.")
    if not _can_access(actor.role, actor.project_id, task.project_id):
        raise ForbiddenError("You can only view subtasks of your own project tasks.")
    query = (
        select(Subtask)
        .where(Subtask.task_id == task_id)
        .order_by(Subtask.sort_order.asc(), Subtask.id.asc())
    )
    return list(db.scalars(query).all())


def create_subtask(
    db: Session,
    *,
    actor: Assignee,
    task_id: int,
    title: str,
    completed: bool,
    sort_order: int,
) -> Subtask:
    """Add a subtask to a task."""
    require_can_mutate(actor.role)
    task = _load_task(db, actor=actor, task_id=task_id)
    subtask = Subtask(
        task_id=task_id,
        title=title,
        completed=completed,
        sort_order=sort_order,
    )
    db.add(subtask)
    db.commit()
    db.refresh(subtask)
    # Record analytics event.
    analytics_service.record_event(
        db,
        project_id=task.project_id,
        actor_id=actor.id,
        event_type="subtask_created",
        task_id=task.id,
    )
    db.commit()
    return subtask


def update_subtask(
    db: Session,
    *,
    actor: Assignee,
    subtask_id: int,
    changes: dict,
) -> Subtask:
    """Apply a partial update; omitted fields stay unchanged."""
    require_can_mutate(actor.role)
    subtask = db.get(Subtask, subtask_id)
    if subtask is None:
        raise NotFoundError("Subtask not found.")
    task = _load_task(db, actor=actor, task_id=subtask.task_id)
    if "title" in changes and changes["title"] is not None:
        subtask.title = changes["title"]
    if "completed" in changes and changes["completed"] is not None:
        subtask.completed = changes["completed"]
    if "sort_order" in changes and changes["sort_order"] is not None:
        subtask.sort_order = changes["sort_order"]
    db.commit()
    db.refresh(subtask)
    return subtask


def delete_subtask(db: Session, *, actor: Assignee, subtask_id: int) -> None:
    """Remove a subtask."""
    require_can_mutate(actor.role)
    subtask = db.get(Subtask, subtask_id)
    if subtask is None:
        raise NotFoundError("Subtask not found.")
    task = _load_task(db, actor=actor, task_id=subtask.task_id)
    db.delete(subtask)
    db.commit()


def _load_task(db: Session, *, actor: Assignee, task_id: int) -> Task:
    task = db.get(Task, task_id)
    if task is None:
        raise NotFoundError("Task not found.")
    if not _can_access(actor.role, actor.project_id, task.project_id):
        raise ForbiddenError("You can only manage subtasks of your own project tasks.")
    return task


def _can_access(role: str, actor_project_id: int | None, task_project_id: int) -> bool:
    from ..core.rules import is_admin

    if is_admin(role):
        return True
    return actor_project_id is not None and actor_project_id == task_project_id
