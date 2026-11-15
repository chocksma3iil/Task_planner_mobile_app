"""Audit trail (D06): record sensitive actions, list them for admins.

`record` only adds a row to the caller's transaction; the service that owns
the mutation commits it together with the change, so the trail can never
diverge from the data.
"""
import json
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..core.rules import require_admin
from ..models import Assignee, AuditLog


def record(
    db: Session,
    *,
    actor: Assignee | None,
    action: str,
    entity_type: str,
    entity_id: int | None = None,
    project_id: int | None = None,
    details: dict[str, Any] | None = None,
) -> AuditLog:
    """Append one audit row to the current transaction (no commit here)."""
    entry = AuditLog(
        actor_id=actor.id if actor else None,
        actor_name=actor.name if actor else "system",
        action=action,
        entity_type=entity_type,
        entity_id=entity_id,
        project_id=project_id,
        details=json.dumps(details) if details else None,
    )
    db.add(entry)
    return entry


def list_logs(
    db: Session,
    *,
    actor: Assignee,
    project_id: int | None = None,
    limit: int = 20,
    offset: int = 0,
) -> tuple[list[AuditLog], int]:
    """Newest first, optionally scoped to one project. Admin-only."""
    require_admin(actor.role)
    query = select(AuditLog).order_by(AuditLog.id.desc())
    if project_id is not None:
        query = query.where(AuditLog.project_id == project_id)
    total = db.scalar(select(func.count()).select_from(query.subquery()))
    items = list(db.scalars(query.limit(limit).offset(offset)).all())
    return items, total
