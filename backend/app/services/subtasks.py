"""Task checklist items (subtasks)."""
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..core.errors import NotFoundError
from ..core.rules import require_can_mutate
from ..models import Assignee, Subtask
from .access import load_task


def list_subtasks(
    db: Session, *, actor: Assignee, task_id: int
) -> tuple[list[Subtask], int]:
    load_task(db, actor=actor, task_id=task_id)
    query = select(Subtask).where(Subtask.task_id == task_id)
    total = db.scalar(select(func.count()).select_from(query.subquery()))
    items = list(
        db.scalars(
            query.order_by(Subtask.sort_order, Subtask.id)
        ).all()
    )
    return items, total


def create_subtask(
    db: Session,
    *,
    actor: Assignee,
    task_id: int,
    title: str,
    completed: bool = False,
    sort_order: int = 0,
) -> Subtask:
    load_task(db, actor=actor, task_id=task_id, write=True)
    subtask = Subtask(
        task_id=task_id,
        title=title,
        completed=completed,
        sort_order=sort_order,
    )
    db.add(subtask)
    db.commit()
    db.refresh(subtask)
    return subtask


def update_subtask(
    db: Session, *, actor: Assignee, subtask_id: int, changes: dict
) -> Subtask:
    subtask = _load_subtask(db, actor=actor, subtask_id=subtask_id)
    if not changes:
        from ..core.errors import RuleError

        raise RuleError("Nothing to update.")
    if "title" in changes and changes["title"] is not None:
        subtask.title = changes["title"]
    if "completed" in changes and changes["completed"] is not None:
        subtask.completed = changes["completed"]
    if "sort_order" in changes and changes["sort_order"] is not None:
        subtask.sort_order = changes["sort_order"]
    db.commit()
    db.refresh(subtask)
    return subtask


def delete_subtask(
    db: Session, *, actor: Assignee, subtask_id: int
) -> None:
    subtask = _load_subtask(db, actor=actor, subtask_id=subtask_id)
    db.delete(subtask)
    db.commit()


def _load_subtask(
    db: Session, *, actor: Assignee, subtask_id: int
) -> Subtask:
    subtask = db.get(Subtask, subtask_id)
    if subtask is None:
        raise NotFoundError("Subtask not found.")
    require_can_mutate(actor.role)
    load_task(db, actor=actor, task_id=subtask.task_id, write=True)
    return subtask
