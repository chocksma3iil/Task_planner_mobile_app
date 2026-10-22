"""Task endpoints: scoped reads, assignment-enforced create, status changes."""
from fastapi import APIRouter, Query, Response

from ...models import Task
from ...schemas import TaskIn, TaskOut, TaskUpdate
from ...services import tasks as task_service
from ..deps import CurrentUser, DbSession

router = APIRouter(prefix="/tasks", tags=["tasks"])


@router.get("", response_model=list[TaskOut])
def list_tasks(
    db: DbSession,
    user: CurrentUser,
    project_id: int | None = Query(default=None),
    assignee_id: int | None = Query(default=None),
) -> list[Task]:
    return task_service.list_tasks(
        db, actor=user, project_id=project_id, assignee_id=assignee_id
    )


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
