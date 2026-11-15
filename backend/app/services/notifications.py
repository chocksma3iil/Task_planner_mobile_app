"""Per-account notification inbox."""
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..core.time import utc_now
from ..models import Assignee, Notification


def list_notifications(
    db: Session,
    *,
    actor: Assignee,
    limit: int = 20,
    offset: int = 0,
    unread_only: bool = False,
) -> tuple[list[Notification], int, int]:
    """One page plus the total and the caller's overall unread count."""
    base = select(Notification).where(Notification.account_id == actor.id)
    unread = db.scalar(
        select(func.count())
        .select_from(Notification)
        .where(Notification.account_id == actor.id, Notification.read_at.is_(None))
    )
    query = base
    if unread_only:
        query = query.where(Notification.read_at.is_(None))
    total = db.scalar(select(func.count()).select_from(query.subquery()))
    items = list(
        db.scalars(
            query.order_by(Notification.created_at.desc(), Notification.id.desc())
            .limit(limit)
            .offset(offset)
        ).all()
    )
    return items, int(total or 0), int(unread or 0)


def mark_read(
    db: Session, *, actor: Assignee, notification_ids: list[int]
) -> int:
    """Mark the caller's unread rows; unknown/foreign ids are skipped."""
    rows = list(
        db.scalars(
            select(Notification).where(
                Notification.account_id == actor.id,
                Notification.id.in_(notification_ids),
                Notification.read_at.is_(None),
            )
        ).all()
    )
    now = utc_now()
    for row in rows:
        row.read_at = now
    if rows:
        db.commit()
    return len(rows)
