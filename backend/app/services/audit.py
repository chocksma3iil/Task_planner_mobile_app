"""Admin-only audit trail reads."""
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..core.rules import require_admin
from ..models import Assignee, AuditEvent


def list_audit_events(
    db: Session,
    *,
    actor: Assignee,
    project_id: int | None = None,
    limit: int = 50,
    offset: int = 0,
) -> tuple[list[AuditEvent], int]:
    require_admin(actor.role)
    query = select(AuditEvent)
    if project_id is not None:
        query = query.where(AuditEvent.project_id == project_id)
    total = db.scalar(select(func.count()).select_from(query.subquery()))
    items = list(
        db.scalars(
            query.order_by(
                AuditEvent.created_at.desc(), AuditEvent.id.desc()
            )
            .limit(limit)
            .offset(offset)
        ).all()
    )
    return items, int(total or 0)
