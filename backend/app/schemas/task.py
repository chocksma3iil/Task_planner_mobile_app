"""Task request/response shapes."""
from datetime import date
from typing import Literal

from pydantic import BaseModel, ConfigDict

from .common import OptionalText, RequiredText, UtcDateTime

Priority = Literal["low", "medium", "high"]


class TaskOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    title: str
    description: str | None = None
    status: str
    priority: str
    due_date: date | None = None
    project_id: int
    assignee_id: int | None = None
    created_at: UtcDateTime
    updated_at: UtcDateTime
    completed_at: UtcDateTime | None = None


class TaskIn(BaseModel):
    project_id: int
    title: RequiredText
    description: OptionalText = None
    priority: Priority = "medium"
    due_date: date | None = None
    assignee_id: int | None = None


class TaskUpdate(BaseModel):
    """Partial update; omitted fields stay unchanged, null clears optional ones."""

    title: RequiredText | None = None
    description: OptionalText = None
    priority: Priority | None = None
    due_date: date | None = None
    assignee_id: int | None = None
