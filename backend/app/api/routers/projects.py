"""Project endpoints. GET is public for the sign-up project picker."""
from fastapi import APIRouter, Query, Response

from ...models import Project
from ...schemas import (
    AiOptInIn,
    AssignOwnerIn,
    Page,
    ProjectIn,
    ProjectOut,
)
from ...services import exports as export_service
from ...services import projects as project_service
from ..deps import CurrentUser, DbSession

router = APIRouter(tags=["projects"])


@router.get("/projects", response_model=Page[ProjectOut])
def list_projects(
    db: DbSession,
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    include_archived: bool = Query(default=False),
) -> Page[ProjectOut]:
    """One page of projects, sorted by name, with the total count."""
    items, total = project_service.list_projects(
        db, limit=limit, offset=offset, include_archived=include_archived
    )
    return Page(items=items, total=total, limit=limit, offset=offset)


@router.post("/projects", response_model=ProjectOut, status_code=201)
def create_project(
    body: ProjectIn, db: DbSession, user: CurrentUser
) -> Project:
    return project_service.create_project(
        db, actor=user, name=body.name, description=body.description
    )


@router.post("/projects/{project_id}/assign-owner", response_model=ProjectOut)
def assign_owner(
    project_id: int,
    body: AssignOwnerIn,
    db: DbSession,
    user: CurrentUser,
) -> Project:
    return project_service.assign_owner(
        db, actor=user, project_id=project_id, owner_id=body.owner_id
    )


@router.patch("/projects/{project_id}/archive", response_model=ProjectOut)
def archive_project(
    project_id: int, db: DbSession, user: CurrentUser
) -> Project:
    return project_service.archive_project(
        db, actor=user, project_id=project_id
    )


@router.patch("/projects/{project_id}/restore", response_model=ProjectOut)
def restore_project(
    project_id: int, db: DbSession, user: CurrentUser
) -> Project:
    return project_service.restore_project(
        db, actor=user, project_id=project_id
    )


@router.patch("/projects/{project_id}/ai-opt-in", response_model=ProjectOut)
def set_ai_opt_in(
    project_id: int, body: AiOptInIn, db: DbSession, user: CurrentUser
) -> Project:
    return project_service.set_ai_opt_in(
        db, actor=user, project_id=project_id, enabled=body.ai_opt_in
    )


@router.get("/projects/{project_id}/export")
def export_project(
    project_id: int,
    db: DbSession,
    user: CurrentUser,
    format: str = Query(default="csv"),
) -> Response:
    """Download all project tasks as CSV or PDF."""
    data, media_type, filename = export_service.build_export(
        db, actor=user, project_id=project_id, format=format
    )
    return Response(
        content=data,
        media_type=media_type,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )