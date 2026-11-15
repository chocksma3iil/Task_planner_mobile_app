"""Comment operations."""
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..core.errors import ForbiddenError, NotFoundError
from ..core.rules import require_can_mutate, is_admin, is_owner_or_admin
from ..models import Assignee, Comment, Notification, Project, Task
from ..schemas.comment import CommentIn
from . import analytics_service, notification_service


def list_comments(db: Session, *, actor: Assignee, task_id: int) -> list[Comment]:
    """All comments of a task, newest first."""
    task = db.get(Task, task_id)
    if task is None:
        raise NotFoundError("Task not found.")
    if not _can_access(actor.role, actor.project_id, task.project_id):
        raise ForbiddenError("You can only view comments of your own project tasks.")
    query = (
        select(Comment)
        .where(Comment.task_id == task_id, Comment.deleted_at.is_(None))
        .order_by(Comment.created_at.asc(), Comment.id.asc())
    )
    return list(db.scalars(query).all())


def create_comment(
    db: Session,
    *,
    actor: Assignee,
    task_id: int,
    comment_in: CommentIn,
) -> Comment:
    """Add a comment to a task."""
    require_can_mutate(actor.role)
    task = _load_task(db, actor=actor, task_id=task_id)
    project = db.get(Project, task.project_id)
    project_name = project.name if project else ""

    # Validate mentions belong to the same project and aren't the author.
    valid_mention_ids = list(comment_in.mentions)
    valid_mention_ids = [m for m in valid_mention_ids if m != actor.id]
    if valid_mention_ids:
        member_ids = [
            m.id
            for m in db.scalars(
                select(Assignee).where(
                    Assignee.project_id == task.project_id,
                    Assignee.status == "active",
                )
            ).all()
        ]
        invalid = [m for m in valid_mention_ids if m not in member_ids]
        if invalid:
            raise ForbiddenError("You can only mention members of this project.")

    comment = Comment(
        task_id=task_id,
        author_id=actor.id,
        body=comment_in.body,
        mentions=valid_mention_ids,
    )
    db.add(comment)
    db.flush()

    # Notify the task assignee (once, deduped with mentions).
    notify_ids: set[int] = set(valid_mention_ids)
    if task.assignee_id is not None:
        notify_ids.add(task.assignee_id)
    notify_ids.discard(actor.id)

    if notify_ids:
        notification_service.notify_comment_created(
            db,
            task=task,
            actor=actor,
            project_name=project_name,
            target_ids=notify_ids,
        )

    # Record analytics event.
    analytics_service.record_event(
        db,
        project_id=task.project_id,
        actor_id=actor.id,
        event_type="comment_created",
        task_id=task.id,
    )
    db.commit()
    return comment


def update_comment(
    db: Session,
    *,
    actor: Assignee,
    comment_id: int,
    changes: dict,
) -> Comment:
    """Apply a partial update; only author can edit."""
    comment = db.get(Comment, comment_id)
    if comment is None or comment.deleted_at is not None:
        raise NotFoundError("Comment not found.")
    if comment.author_id != actor.id:
        raise ForbiddenError("You can only edit your own comments.")
    if "body" in changes:
        comment.body = changes["body"]
    comment.edited_at = comment.created_at  # simplified
    db.commit()
    db.refresh(comment)
    return comment


def delete_comment(db: Session, *, actor: Assignee, comment_id: int) -> None:
    """Soft delete: set deleted_at if author, owner, or admin."""
    comment = db.get(Comment, comment_id)
    if comment is None:
        raise NotFoundError("Comment not found.")
    if comment.author_id != actor.id:
        if not is_admin(actor.role) and not is_owner_or_admin(actor.role):
            raise ForbiddenError("You can only delete your own comments.")
        if is_owner_or_admin(actor.role) and not _actor_belongs_to_project(
            db, actor, comment.task_id
        ):
            raise ForbiddenError("You can only delete comments in your own project.")
    comment.deleted_at = comment.created_at  # simplified
    db.commit()


def _load_task(db: Session, *, actor: Assignee, task_id: int) -> Task:
    task = db.get(Task, task_id)
    if task is None:
        raise NotFoundError("Task not found.")
    if not _can_access(actor.role, actor.project_id, task.project_id):
        raise ForbiddenError("You can only manage comments of your own project tasks.")
    return task


def _actor_belongs_to_project(db: Session, actor: Assignee, task_id: int) -> bool:
    task = db.get(Task, task_id)
    if task is None:
        return False
    return actor.project_id is not None and actor.project_id == task.project_id


def _can_access(role: str, actor_project_id: int | None, task_project_id: int) -> bool:
    from ..core.rules import is_admin

    if is_admin(role):
        return True
    return actor_project_id is not None and actor_project_id == task_project_id
