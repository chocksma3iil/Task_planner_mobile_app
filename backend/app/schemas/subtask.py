"""Subtask request/response shapes."""
from typing import Literal

from pydantic import BaseModel, ConfigDict

from .common import OptionalText, RequiredText, UtcDateTime


class SubtaskOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    task_id: int
    title: str
    completed: bool
    sort_order: int
    created_at: UtcDateTime


class SubtaskIn(BaseModel):
    task_id: int
    title: RequiredText
    completed: bool = False
    sort_order: int = 0


class SubtaskUpdate(BaseModel):
    """Partial update; omitted fields stay unchanged."""

    title: str | None = None
    completed: bool | None = None
    sort_order: int | None = None


class SubtaskListOut(BaseModel):
    items: list[SubtaskOut]
    total: int
