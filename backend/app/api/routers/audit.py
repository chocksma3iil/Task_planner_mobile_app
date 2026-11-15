"""Audit-log endpoints (D06): admin-only read access."""
from fastapi import APIRouter, Query

from ...schemas import AuditLogListOut
from ...services import audit as audit_service
from ..deps import CurrentUser, DbSession

router = APIRouter(prefix="/audit-logs", tags=["audit"])


@router.get("", response_model=AuditLogListOut)
def list_logs(
    user: CurrentUser,
    db: DbSession,
    project_id: int | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
) -> AuditLogListOut:
    """Newest first; optionally scoped to one project. Admins only."""
    items, total = audit_service.list_logs(
        db,
        actor=user,
        project_id=project_id,
        limit=limit,
        offset=offset,
    )
    return AuditLogListOut(items=items, total=total, limit=limit, offset=offset)
