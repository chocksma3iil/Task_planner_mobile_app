"""AI request/response shapes (v2.0)."""
from typing import Any

from pydantic import BaseModel, ConfigDict, Field


class WeeklyPlanTask(BaseModel):
    title: str
    description: str | None = None
    priority: str = Field(default="medium")
    due_date: str | None = None
    status: str = Field(default="todo")


class WeeklyPlanOut(BaseModel):
    title: str
    tasks: list[WeeklyPlanTask] = Field(default_factory=list)


class SubtaskProposal(BaseModel):
    title: str
    description: str | None = None
    priority: str = Field(default="medium")


class DecomposeOut(BaseModel):
    subtasks: list[SubtaskProposal] = Field(default_factory=list)


class BriefingOut(BaseModel):
    briefing: str


class CaptureIn(BaseModel):
    project_id: int
    text: str


class CaptureOut(BaseModel):
    title: str
    description: str | None = None
    priority: str = Field(default="medium")
    due_date: str | None = None
    status: str = Field(default="todo")


class AiOptInIn(BaseModel):
    ai_opt_in: bool


# Alias for consumers that import from the package.
AIProposal = dict[str, Any]
