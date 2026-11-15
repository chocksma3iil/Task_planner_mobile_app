"""Project endpoints. GET is public for the sign-up project picker."""
from typing import Literal

from fastapi import APIRouter, Query, Response

from ...models import Project
from ...schemas import (
    AssignOwnerIn,
    ProjectIn,
    ProjectListOut,
    ProjectOut,
    ProjectRestoreIn,
)
from ...schemas.ai import AiOptInIn
from ...services import exports as export_service
from ...services import projects as project_service
from ..deps import CurrentUser, DbSession

router = APIRouter(tags=["projects"])


@router.get("/projects", response_model=ProjectListOut)
def list_projects(
    db: DbSession,
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    include_archived: bool = Query(default=False),
) -> ProjectListOut:
    items, total = project_service.list_projects(
        db, limit=limit, offset=offset, include_archived=include_archived
    )
    return ProjectListOut(items=items, total=total, limit=limit, offset=offset)


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
    project_id: int,
    db: DbSession,
    user: CurrentUser,
) -> Project:
    return project_service.archive_project(db, actor=user, project_id=project_id)


@router.patch("/projects/{project_id}/restore", response_model=ProjectOut)
def restore_project(
    project_id: int,
    db: DbSession,
    user: CurrentUser,
) -> Project:
    return project_service.restore_project(db, actor=user, project_id=project_id)


@router.patch("/projects/{project_id}/ai-opt-in", response_model=ProjectOut)
def set_ai_opt_in(
    project_id: int,
    body: AiOptInIn,
    db: DbSession,
    user: CurrentUser,
) -> Project:
    """Enable/disable AI for a project (admin or project owner only)."""
    project = db.get(Project, project_id)
    if project is None:
        raise NotFoundError("Project not found.")
    from ...core.rules import is_admin, is_owner_or_admin

    if not is_admin(user.role) and not (
        is_owner_or_admin(user.role) and project.owner_id == user.id
    ):
        raise ForbiddenError("Only an admin or project owner can toggle AI.")
    project.ai_opt_in = body.ai_opt_in
    db.commit()
    db.refresh(project)
    return project


@router.get("/projects/{project_id}/export")
def export_project(
    project_id: int,
    user: CurrentUser,
    db: DbSession,
    format: Literal["csv", "pdf"] = Query(default="csv"),
) -> Response:
    """Download one project's task report as CSV or PDF (E03).

    Read access is enough, so viewers can export too.
    """
    if format == "pdf":
        content = export_service.pdf_for(db, actor=user, project_id=project_id)
        media_type = export_service.PDF_MEDIA_TYPE
    else:
        content = export_service.csv_for(db, actor=user, project_id=project_id)
        media_type = export_service.CSV_MEDIA_TYPE
    filename = f"project-{project_id}-report.{format}"
    return Response(
        content=content,
        media_type=media_type,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
