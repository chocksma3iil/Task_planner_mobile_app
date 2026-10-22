"""Project endpoints. GET is public for the sign-up project picker."""
from fastapi import APIRouter

from ...models import Project
from ...schemas import AssignOwnerIn, ProjectIn, ProjectOut
from ...services import projects as project_service
from ..deps import CurrentUser, DbSession

router = APIRouter(tags=["projects"])


@router.get("/projects", response_model=list[ProjectOut])
def list_projects(db: DbSession) -> list[Project]:
    return project_service.list_projects(db)


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
