"""Audit-log response shapes (D06)."""
from pydantic import BaseModel, ConfigDict

from .common import UtcDateTime


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


class AuditLogListOut(BaseModel):
    items: list[AuditLogOut]
    total: int
    limit: int
    offset: int
