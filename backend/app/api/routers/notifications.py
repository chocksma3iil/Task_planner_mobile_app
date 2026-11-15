"""Notification endpoints: list, mark as read."""
from fastapi import APIRouter, Query

from ...models import Notification
from ...schemas import NotificationListOut, NotificationOut, MarkReadIn
from ..deps import CurrentUser, DbSession

router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.get("", response_model=NotificationListOut)
def list_notifications(
    db: DbSession,
    user: CurrentUser,
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    unread_only: bool = Query(default=False),
) -> NotificationListOut:
    query = db.query(Notification).where(Notification.user_id == user.id)
    if unread_only:
        query = query.where(Notification.read_at.is_(None))
    query = query.order_by(Notification.created_at.desc(), Notification.id.desc())
    total = query.count()
    items = query.limit(limit).offset(offset).all()
    unread = (
        db.query(Notification)
        .where(Notification.user_id == user.id, Notification.read_at.is_(None))
        .count()
    )
    return NotificationListOut(
        items=items, total=total, unread=unread, limit=limit, offset=offset
    )


@router.patch("/read", response_model=dict)
def mark_as_read(
    body: MarkReadIn,
    db: DbSession,
    user: CurrentUser,
) -> dict:
    from datetime import datetime, timezone

    now = datetime.now(timezone.utc)
    marked = 0
    for nid in body.notification_ids:
        n = db.get(Notification, nid)
        if n is not None and n.user_id == user.id and n.read_at is None:
            n.read_at = now
            marked += 1
    db.commit()
    return {"marked": marked}
