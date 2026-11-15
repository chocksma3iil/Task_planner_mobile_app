"""Analytics request/response shapes."""
from typing import Literal

from pydantic import BaseModel, ConfigDict

from .common import UtcDateTime

EventType = Literal[
    "task_created",
    "task_completed",
    "task_reopened",
    "task_deleted",
    "task_assigned",
    "subtask_created",
    "comment_created",
]


class DashboardOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    project_id: int
    project_name: str
    total_tasks: int
    completed_tasks: int
    pending_tasks: int
    overdue_tasks: int
    completion_rate: float  # 0..100
    overdue_rate: float  # 0..100
    priority_mix: dict[str, int]  # {"low": n, "medium": n, "high": n}
    velocity_per_week: float  # completed tasks per week (last 4 weeks)
    recent_events: list["DashboardEventOut"]


class DashboardEventOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    event_type: EventType
    task_id: int | None = None
    actor_id: int
    actor_name: str
    created_at: UtcDateTime


# Forward references resolve at import time.
DashboardOut.model_rebuild()
DashboardEventOut.model_rebuild()
