"""Task endpoints: tasks, bulk actions, comments, and subtasks."""
from fastapi import APIRouter, Query, Response

from ...models import Task
from ...schemas import (
    BulkReassignIn,
    BulkTaskIn,
    BulkTaskOut,
    CommentIn,
    CommentList,
    CommentOut,
    Page,
    SubtaskIn,
    SubtaskList,
    SubtaskOut,
    SubtaskUpdate,
    TaskIn,
    TaskOut,
    TaskUpdate,
)
from ...services import comments as comment_service
from ...services import subtasks as subtask_service
from ...services import tasks as task_service
from ..deps import CurrentUser, DbSession

router = APIRouter(prefix="/tasks", tags=["tasks"])


@router.get("", response_model=Page[TaskOut])
def list_tasks(
    db: DbSession,
    user: CurrentUser,
    project_id: int | None = Query(default=None),
    assignee_id: int | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
) -> Page[TaskOut]:
    """One page of scoped tasks, newest first, with the total count."""
    items, total = task_service.list_tasks(
        db,
        actor=user,
        project_id=project_id,
        assignee_id=assignee_id,
        limit=limit,
        offset=offset,
    )
    return Page(items=items, total=total, limit=limit, offset=offset)


@router.post("", response_model=TaskOut, status_code=201)
def create_task(body: TaskIn, db: DbSession, user: CurrentUser) -> Task:
    return task_service.create_task(
        db,
        actor=user,
        project_id=body.project_id,
        title=body.title,
        description=body.description,
        priority=body.priority,
        due_date=body.due_date,
        assignee_id=body.assignee_id,
    )


@router.post("/bulk/complete", response_model=BulkTaskOut)
def bulk_complete(
    body: BulkTaskIn, db: DbSession, user: CurrentUser
) -> dict:
    return task_service.bulk_complete(
        db, actor=user, task_ids=body.task_ids
    )


@router.post("/bulk/reassign", response_model=BulkTaskOut)
def bulk_reassign(
    body: BulkReassignIn, db: DbSession, user: CurrentUser
) -> dict:
    return task_service.bulk_reassign(
        db,
        actor=user,
        task_ids=body.task_ids,
        assignee_id=body.assignee_id,
    )


@router.post("/bulk/delete", response_model=BulkTaskOut)
def bulk_delete(
    body: BulkTaskIn, db: DbSession, user: CurrentUser
) -> dict:
    return task_service.bulk_delete(db, actor=user, task_ids=body.task_ids)


@router.patch("/subtasks/{subtask_id}", response_model=SubtaskOut)
def update_subtask(
    subtask_id: int,
    body: SubtaskUpdate,
    db: DbSession,
    user: CurrentUser,
):
    return subtask_service.update_subtask(
        db,
        actor=user,
        subtask_id=subtask_id,
        changes=body.model_dump(exclude_unset=True),
    )


@router.delete("/subtasks/{subtask_id}", status_code=204)
def delete_subtask(
    subtask_id: int, db: DbSession, user: CurrentUser
) -> Response:
    subtask_service.delete_subtask(db, actor=user, subtask_id=subtask_id)
    return Response(status_code=204)


@router.get("/{task_id}/comments", response_model=CommentList)
def list_comments(
    task_id: int, db: DbSession, user: CurrentUser
) -> CommentList:
    items, total = comment_service.list_comments(
        db, actor=user, task_id=task_id
    )
    return CommentList(items=items, total=total)


@router.post(
    "/{task_id}/comments", response_model=CommentOut, status_code=201
)
def create_comment(
    task_id: int, body: CommentIn, db: DbSession, user: CurrentUser
):
    return comment_service.create_comment(
        db,
        actor=user,
        task_id=task_id,
        body=body.body,
        parent_id=body.parent_id,
    )


@router.get("/{task_id}/subtasks", response_model=SubtaskList)
def list_subtasks(
    task_id: int, db: DbSession, user: CurrentUser
) -> SubtaskList:
    items, total = subtask_service.list_subtasks(
        db, actor=user, task_id=task_id
    )
    return SubtaskList(items=items, total=total)


@router.post(
    "/{task_id}/subtasks", response_model=SubtaskOut, status_code=201
)
def create_subtask(
    task_id: int, body: SubtaskIn, db: DbSession, user: CurrentUser
):
    return subtask_service.create_subtask(
        db,
        actor=user,
        task_id=task_id,
        title=body.title,
        completed=body.completed,
        sort_order=body.sort_order,
    )


@router.patch("/{task_id}", response_model=TaskOut)
def update_task(
    task_id: int, body: TaskUpdate, db: DbSession, user: CurrentUser
) -> Task:
    return task_service.update_task(
        db,
        actor=user,
        task_id=task_id,
        changes=body.model_dump(exclude_unset=True),
    )


@router.patch("/{task_id}/complete", response_model=TaskOut)
def complete_task(task_id: int, db: DbSession, user: CurrentUser) -> Task:
    return task_service.complete_task(db, actor=user, task_id=task_id)


@router.patch("/{task_id}/reopen", response_model=TaskOut)
def reopen_task(task_id: int, db: DbSession, user: CurrentUser) -> Task:
    return task_service.reopen_task(db, actor=user, task_id=task_id)


@router.delete("/{task_id}", status_code=204)
def delete_task(task_id: int, db: DbSession, user: CurrentUser) -> Response:
    task_service.delete_task(db, actor=user, task_id=task_id)
    return Response(status_code=204)
