"""Analytics dashboard and audit-trail shapes."""
from pydantic import BaseModel, ConfigDict

from .common import UtcDateTime


class AnalyticsEventOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    event_type: str
    task_id: int | None = None
    actor_id: int
    actor_name: str
    created_at: UtcDateTime


class DashboardOut(BaseModel):
    project_id: int
    project_name: str
    total_tasks: int
    completed_tasks: int
    pending_tasks: int
    overdue_tasks: int
    completion_rate: float
    overdue_rate: float
    priority_mix: dict[str, int]
    velocity_per_week: float
    recent_events: list[AnalyticsEventOut]


class AuditLogOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    actor_id: int | None = None
    actor_name: str
    action: str
    entity_type: str
    entity_id: int | None = None
    project_id: int | None = None
    details: str | None = None
    created_at: UtcDateTime
