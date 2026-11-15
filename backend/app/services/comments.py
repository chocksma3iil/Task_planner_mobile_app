"""Task comments: project-scoped reads, author-only edits and soft deletes."""
import json

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..core.errors import ForbiddenError, NotFoundError, RuleError
from ..core.rules import require_can_mutate
from ..core.time import utc_now
from ..models import Assignee, Comment, Task
from .access import load_task


def list_comments(
    db: Session, *, actor: Assignee, task_id: int
) -> tuple[list[Comment], int]:
    """All comments of one visible task, newest first (deleted rows kept)."""
    load_task(db, actor=actor, task_id=task_id)
    query = select(Comment).where(Comment.task_id == task_id)
    total = db.scalar(select(func.count()).select_from(query.subquery()))
    items = list(
        db.scalars(
            query.order_by(Comment.created_at.desc(), Comment.id.desc())
        ).all()
    )
    return items, total


def create_comment(
    db: Session,
    *,
    actor: Assignee,
    task_id: int,
    body: str,
    parent_id: int | None = None,
) -> Comment:
    task = load_task(db, actor=actor, task_id=task_id, write=True)
    if parent_id is not None:
        parent = db.get(Comment, parent_id)
        if parent is None or parent.task_id != task_id:
            raise NotFoundError("Parent comment not found.")
    comment = Comment(
        task_id=task_id,
        author_id=actor.id,
        parent_id=parent_id,
        body=body,
        mentions=json.dumps([]),
    )
    db.add(comment)
    db.flush()
    _notify_assignee(db, actor=actor, task=task)
    db.commit()
    db.refresh(comment)
    return comment


def update_comment(
    db: Session, *, actor: Assignee, comment_id: int, body: str
) -> Comment:
    comment = _load_own_comment(db, actor=actor, comment_id=comment_id)
    if comment.deleted_at is not None:
        raise RuleError("Deleted comments cannot be edited.")
    comment.body = body
    comment.edited_at = utc_now()
    db.commit()
    db.refresh(comment)
    return comment


def delete_comment(
    db: Session, *, actor: Assignee, comment_id: int
) -> None:
    comment = _load_own_comment(db, actor=actor, comment_id=comment_id)
    if comment.deleted_at is None:
        comment.deleted_at = utc_now()
        db.commit()


def _load_own_comment(
    db: Session, *, actor: Assignee, comment_id: int
) -> Comment:
    require_can_mutate(actor.role)
    comment = db.get(Comment, comment_id)
    if comment is None:
        raise NotFoundError("Comment not found.")
    if comment.author_id != actor.id:
        raise ForbiddenError("You can only change your own comments.")
    return comment


def _notify_assignee(
    db: Session, *, actor: Assignee, task: Task
) -> None:
    """Tell the task assignee about a new comment, when someone else wrote it."""
    if task.assignee_id is None or task.assignee_id == actor.id:
        return
    from .events import COMMENT_CREATED, notify

    notify(
        db,
        account_id=task.assignee_id,
        type=COMMENT_CREATED,
        title="New comment",
        body=f'A comment was added to "{task.title}".',
        payload=str(task.id),
    )
