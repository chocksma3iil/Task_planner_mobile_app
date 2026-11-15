"""Project analytics dashboard."""
from fastapi import APIRouter, Query

from ...schemas import DashboardOut
from ...services import analytics as analytics_service
from ..deps import CurrentUser, DbSession

router = APIRouter(prefix="/analytics", tags=["analytics"])


@router.get("/dashboard", response_model=DashboardOut)
def dashboard(
    db: DbSession,
    user: CurrentUser,
    project_id: int = Query(),
) -> dict:
    return analytics_service.dashboard(
        db, actor=user, project_id=project_id
    )
