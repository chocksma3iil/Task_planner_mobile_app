"""Notification inbox endpoints."""
from fastapi import APIRouter, Query

from ...schemas import NotificationPage, NotificationReadIn
from ...services import notifications as notification_service
from ..deps import CurrentUser, DbSession

router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.get("", response_model=NotificationPage)
def list_notifications(
    db: DbSession,
    user: CurrentUser,
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    unread_only: bool = Query(default=False),
) -> NotificationPage:
    items, total, unread = notification_service.list_notifications(
        db, actor=user, limit=limit, offset=offset, unread_only=unread_only
    )
    return NotificationPage(
        items=items,
        total=total,
        unread=unread,
        limit=limit,
        offset=offset,
    )


@router.patch("/read")
def mark_read(
    body: NotificationReadIn, db: DbSession, user: CurrentUser
) -> dict:
    updated = notification_service.mark_read(
        db, actor=user, notification_ids=body.notification_ids
    )
    return {"updated": updated}
