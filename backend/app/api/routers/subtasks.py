"""Subtask endpoints: checklist items attached to a task."""
from fastapi import APIRouter

from ...core.errors import ForbiddenError, NotFoundError
from ..deps import CurrentUser, DbSession
from ...models import Task
from ...schemas.subtask import SubtaskIn, SubtaskListOut, SubtaskOut, SubtaskUpdate
from ...services import subtask as subtask_service

router = APIRouter(prefix="/tasks", tags=["subtasks"])


@router.get("/{task_id}/subtasks", response_model=SubtaskListOut)
def list_subtasks(
    task_id: int,
    db: DbSession,
    user: CurrentUser,
) -> SubtaskListOut:
    """List all subtasks of a task."""
    task = db.get(Task, task_id)
    if task is None:
        raise NotFoundError("Task not found.")
    if not _can_access(user.role, user.project_id, task.project_id):
        raise ForbiddenError("You can only view subtasks of your own project tasks.")
    items = subtask_service.list_subtasks(db, actor=user, task_id=task_id)
    return SubtaskListOut(items=items, total=len(items))


@router.post("/{task_id}/subtasks", response_model=SubtaskOut)
def create_subtask(
    body: SubtaskIn,
    task_id: int,
    db: DbSession,
    user: CurrentUser,
) -> SubtaskOut:
    """Add a subtask to a task."""
    task = db.get(Task, task_id)
    if task is None:
        raise NotFoundError("Task not found.")
    if not _can_access(user.role, user.project_id, task.project_id):
        raise ForbiddenError("You can only add subtasks to your own project tasks.")
    subtask = subtask_service.create_subtask(
        db,
        actor=user,
        task_id=task_id,
        title=body.title,
        completed=body.completed,
        sort_order=body.sort_order,
    )
    return subtask


@router.patch("/subtasks/{subtask_id}", response_model=SubtaskOut)
def update_subtask(
    body: SubtaskUpdate,
    subtask_id: int,
    db: DbSession,
    user: CurrentUser,
) -> SubtaskOut:
    """Update a subtask (title / completed / sort_order)."""
    subtask = subtask_service.update_subtask(
        db,
        actor=user,
        subtask_id=subtask_id,
        changes=body.model_dump(exclude_unset=True),
    )
    return subtask


@router.delete("/subtasks/{subtask_id}")
def delete_subtask(
    subtask_id: int,
    db: DbSession,
    user: CurrentUser,
) -> dict:
    """Delete a subtask."""
    subtask_service.delete_subtask(db, actor=user, subtask_id=subtask_id)
    return {"ok": True}


def _can_access(role: str, actor_project_id: int | None, task_project_id: int) -> bool:
    from ...core.rules import is_admin

    if is_admin(role):
        return True
    return actor_project_id is not None and actor_project_id == task_project_id
