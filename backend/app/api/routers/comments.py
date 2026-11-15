"""Comment endpoints."""
from fastapi import APIRouter

from ...core.errors import ForbiddenError, NotFoundError
from ..deps import CurrentUser, DbSession
from ...models import Comment, Task
from ...schemas.comment import CommentIn, CommentListOut, CommentOut, CommentUpdate
from ...services import comment as comment_service

router = APIRouter(prefix="/tasks", tags=["comments"])


@router.get("/{task_id}/comments", response_model=CommentListOut)
def list_comments(
    task_id: int,
    db: DbSession,
    user: CurrentUser,
) -> CommentListOut:
    """List all comments of a task."""
    task = db.get(Task, task_id)
    if task is None:
        raise NotFoundError("Task not found.")
    if not _can_access(user.role, user.project_id, task.project_id):
        raise ForbiddenError("You can only view comments of your own project tasks.")
    items = comment_service.list_comments(db, actor=user, task_id=task_id)
    return CommentListOut(items=items, total=len(items))


@router.post("/{task_id}/comments", response_model=CommentOut, status_code=201)
def create_comment(
    body: CommentIn,
    task_id: int,
    db: DbSession,
    user: CurrentUser,
) -> CommentOut:
    """Add a comment to a task."""
    if body.task_id != task_id:
        body.task_id = task_id
    comment = comment_service.create_comment(
        db, actor=user, task_id=task_id, comment_in=body
    )
    return comment


@router.patch("/comments/{comment_id}", response_model=CommentOut)
def update_comment(
    body: CommentUpdate,
    comment_id: int,
    db: DbSession,
    user: CurrentUser,
) -> CommentOut:
    """Update a comment (author only)."""
    comment = comment_service.update_comment(
        db, actor=user, comment_id=comment_id, changes=body.model_dump(exclude_unset=True)
    )
    return comment


@router.delete("/comments/{comment_id}", status_code=204)
def delete_comment(
    comment_id: int,
    db: DbSession,
    user: CurrentUser,
) -> None:
    """Delete a comment (author, owner, admin)."""
    comment_service.delete_comment(db, actor=user, comment_id=comment_id)


def _can_access(role: str, actor_project_id: int | None, task_project_id: int) -> bool:
    from ...core.rules import is_admin

    if is_admin(role):
        return True
    return actor_project_id is not None and actor_project_id == task_project_id
