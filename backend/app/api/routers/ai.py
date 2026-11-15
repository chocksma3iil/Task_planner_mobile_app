"""AI proposal endpoints (read-only; gated by the project's opt-in flag)."""
from fastapi import APIRouter, Query

from ...schemas import (
    AiBriefingOut,
    AiCaptureIn,
    AiDecomposeOut,
    AiWeeklyPlanOut,
)
from ...services import ai as ai_service
from ..deps import CurrentUser, DbSession

router = APIRouter(prefix="/ai", tags=["ai"])


@router.post("/weekly-plan", response_model=AiWeeklyPlanOut)
def weekly_plan(
    db: DbSession, user: CurrentUser, project_id: int = Query()
) -> dict:
    return ai_service.weekly_plan(db, actor=user, project_id=project_id)


@router.post("/decompose", response_model=AiDecomposeOut)
def decompose(
    db: DbSession, user: CurrentUser, task_id: int = Query()
) -> dict:
    return ai_service.decompose(db, actor=user, task_id=task_id)


@router.post("/briefing", response_model=AiBriefingOut)
def briefing(
    db: DbSession, user: CurrentUser, project_id: int = Query()
) -> dict:
    return ai_service.briefing(db, actor=user, project_id=project_id)


@router.post("/capture")
def capture(body: AiCaptureIn, db: DbSession, user: CurrentUser) -> dict:
    return ai_service.capture(
        db, actor=user, project_id=body.project_id, text=body.text
    )
