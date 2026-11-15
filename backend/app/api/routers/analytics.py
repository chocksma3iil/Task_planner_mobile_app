"""Analytics endpoints: project dashboard metrics."""
from fastapi import APIRouter, Query

from ...core.rules import is_admin
from ...core.errors import ForbiddenError, NotFoundError
from ...models import Project
from ...schemas.analytics import DashboardOut
from ..deps import CurrentUser, DbSession
from ...services import analytics_service

router = APIRouter(prefix="/analytics", tags=["analytics"])


@router.get("/dashboard", response_model=DashboardOut)
def project_dashboard(
    db: DbSession,
    user: CurrentUser,
    project_id: int = Query(..., ge=1),
) -> DashboardOut:
    """Dashboard metrics for one project.

    Access: admins across all projects; owners/users within their own project.
    """
    project = db.get(Project, project_id)
    if project is None:
        raise NotFoundError("Project not found.")

    # Access scoping: admin across all projects; owner/user within own project.
    if not is_admin(user.role) and user.project_id != project_id:
        raise ForbiddenError("You can only view your own project dashboard.")

    return analytics_service.get_dashboard(db, project_id=project_id)
