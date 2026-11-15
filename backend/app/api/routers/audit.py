"""Admin audit-trail reads."""
from fastapi import APIRouter, Query

from ...schemas import AuditLogOut, Page
from ...services import audit as audit_service
from ..deps import CurrentUser, DbSession

router = APIRouter(tags=["audit"])


@router.get("/audit-logs", response_model=Page[AuditLogOut])
def list_audit_logs(
    db: DbSession,
    user: CurrentUser,
    project_id: int | None = Query(default=None),
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
) -> Page[AuditLogOut]:
    items, total = audit_service.list_audit_events(
        db,
        actor=user,
        project_id=project_id,
        limit=limit,
        offset=offset,
    )
    return Page(items=items, total=total, limit=limit, offset=offset)
