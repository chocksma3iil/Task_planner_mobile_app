"""AI endpoints (v2.0): read-only proposals, human approval required to write."""
from fastapi import APIRouter, Query

from ...core.errors import ForbiddenError, NotFoundError
from ..deps import CurrentUser, DbSession
from ...models import Project, Task
from ...schemas.ai import (
    BriefingOut,
    CaptureIn,
    CaptureOut,
    DecomposeOut,
    WeeklyPlanOut,
)
from ...services import ai_service as ai_service_module

router = APIRouter(prefix="/ai", tags=["ai"])


def _require_consent(db: DbSession, user: CurrentUser, project_id: int) -> Project:
    from ...core.rules import is_admin

    project = db.get(Project, project_id)
    if project is None:
        raise NotFoundError("Project not found.")
    ai_service_module.require_ai_consent(project)
    # Non-admin users can only use AI on their own project.
    if not is_admin(user.role) and user.project_id != project_id:
        raise ForbiddenError("You can only use AI on your own project.")
    return project


@router.post("/weekly-plan", response_model=WeeklyPlanOut)
async def weekly_plan(
    project_id: int = Query(..., description="Project id"),
    db: DbSession = None,
    user: CurrentUser = None,
) -> WeeklyPlanOut:
    """Propose a weekly plan for a project (read-only)."""
    _require_consent(db, user, project_id)
    service = ai_service_module.AIService(db, user)
    plan = await service.propose_weekly_plan(project_id)
    return WeeklyPlanOut(**plan)


@router.post("/decompose", response_model=DecomposeOut)
async def decompose(
    task_id: int = Query(..., description="Task id to decompose"),
    db: DbSession = None,
    user: CurrentUser = None,
) -> DecomposeOut:
    """Propose subtasks for a task (read-only)."""
    task = db.get(Task, task_id)
    if task is None:
        raise NotFoundError("Task not found.")
    _require_consent(db, user, task.project_id)
    service = ai_service_module.AIService(db, user)
    result = await service.decompose(task_id)
    return DecomposeOut(**result)


@router.post("/briefing", response_model=BriefingOut)
async def briefing(
    project_id: int = Query(..., description="Project id"),
    db: DbSession = None,
    user: CurrentUser = None,
) -> BriefingOut:
    """Propose a natural-language briefing for a project (read-only)."""
    _require_consent(db, user, project_id)
    service = ai_service_module.AIService(db, user)
    result = await service.briefing(project_id)
    return BriefingOut(**result)


@router.post("/capture", response_model=CaptureOut)
async def capture(
    body: CaptureIn,
    db: DbSession = None,
    user: CurrentUser = None,
) -> CaptureOut:
    """Propose a task from natural language (read-only)."""
    _require_consent(db, user, body.project_id)
    service = ai_service_module.AIService(db, user)
    result = await service.capture(body.project_id, body.text)
    return CaptureOut(**result)
