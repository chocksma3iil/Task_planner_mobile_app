"""Cross-cutting helpers: analytics events, audit rows, notifications."""
import json
from typing import Any

from sqlalchemy.orm import Session

from ..models import AnalyticsEvent, Assignee, AuditEvent, Notification

TASK_ASSIGNED = "task_assigned"
TASK_COMPLETED = "task_completed"
COMMENT_CREATED = "comment_created"
MEMBER_PENDING = "member_pending"


def record_event(
    db: Session,
    *,
    project_id: int,
    event_type: str,
    actor: Assignee,
    task_id: int | None = None,
) -> None:
    db.add(
        AnalyticsEvent(
            project_id=project_id,
            event_type=event_type,
            task_id=task_id,
            actor_id=actor.id,
            actor_name=actor.name,
        )
    )


def record_audit(
    db: Session,
    *,
    actor: Assignee,
    action: str,
    entity_type: str,
    entity_id: int | None = None,
    project_id: int | None = None,
    details: dict[str, Any] | None = None,
) -> None:
    db.add(
        AuditEvent(
            actor_id=actor.id,
            actor_name=actor.name,
            action=action,
            entity_type=entity_type,
            entity_id=entity_id,
            project_id=project_id,
            details=json.dumps(details) if details is not None else None,
        )
    )


def notify(
    db: Session,
    *,
    account_id: int,
    type: str,
    title: str,
    body: str | None = None,
    payload: str | None = None,
) -> None:
    db.add(
        Notification(
            account_id=account_id,
            type=type,
            title=title,
            body=body,
            payload=payload,
        )
    )
