"""AI proposal shapes (read-only; nothing is persisted)."""
from pydantic import BaseModel

from .common import RequiredText


class AiTaskProposalOut(BaseModel):
    title: str
    description: str | None = None
    priority: str = "medium"
    due_date: str | None = None
    status: str = "todo"


class AiWeeklyPlanOut(BaseModel):
    title: str = "Weekly Plan"
    tasks: list[AiTaskProposalOut]


class AiSubtaskProposalOut(BaseModel):
    title: str
    description: str | None = None
    priority: str = "medium"


class AiDecomposeOut(BaseModel):
    subtasks: list[AiSubtaskProposalOut]


class AiBriefingOut(BaseModel):
    briefing: str


class AiCaptureIn(BaseModel):
    project_id: int
    text: RequiredText
