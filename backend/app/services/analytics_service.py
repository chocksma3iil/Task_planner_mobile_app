"""Project analytics dashboard computations."""
from datetime import datetime, timedelta

from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from ..core.time import utc_now
from ..models import AnalyticsEvent, Assignee, Project, Task
from ..schemas.analytics import DashboardEventOut, DashboardOut


def record_event(
    db: Session,
    *,
    project_id: int,
    actor_id: int,
    event_type: str,
    task_id: int | None = None,
    payload: str | None = None,
) -> None:
    """Persist one analytics event for dashboard computations."""
    db.add(
        AnalyticsEvent(
            project_id=project_id,
            actor_id=actor_id,
            event_type=event_type,
            task_id=task_id,
            payload=payload,
        )
    )


def purge_old_events(db: Session, *, days: int) -> int:
    """Delete analytics events older than [days] and return the row count.

    Dashboard KPIs do not depend on the raw log (velocity is computed from
    task completion timestamps), so pruning only shortens the "recent
    activity" history.
    """
    if days <= 0:
        raise ValueError("days must be a positive number of days.")
    cutoff = utc_now() - timedelta(days=days)
    result = db.execute(
        delete(AnalyticsEvent).where(AnalyticsEvent.created_at < cutoff)
    )
    db.commit()
    return int(result.rowcount or 0)


def get_dashboard(db: Session, *, project_id: int) -> DashboardOut:
    """Compute dashboard metrics for one project."""
    project = db.get(Project, project_id)
    if project is None:
        from ..core.errors import NotFoundError

        raise NotFoundError("Project not found.")

    now = utc_now()
    # All tasks of the project.
    tasks = list(
        db.scalars(select(Task).where(Task.project_id == project_id)).all()
    )
    total = len(tasks)
    completed = [t for t in tasks if t.status == "completed"]
    pending = [t for t in tasks if t.status != "completed"]

    # Overdue: incomplete + due_date < today.
    today = now.date()
    overdue = [
        t
        for t in pending
        if t.due_date is not None and t.due_date < today
    ]

    completion_rate = round((len(completed) / total * 100), 1) if total else 0.0
    overdue_rate = round((len(overdue) / total * 100), 1) if total else 0.0

    # Priority mix.
    priority_mix: dict[str, int] = {"low": 0, "medium": 0, "high": 0}
    for t in tasks:
        key = t.priority if t.priority in priority_mix else "medium"
        priority_mix[key] += 1

    # Velocity: completed tasks per week over the last 4 weeks.
    four_weeks_ago = now - timedelta(weeks=4)
    recent_completed = [
        t
        for t in completed
        if t.completed_at is not None
        and t.completed_at >= four_weeks_ago
    ]
    velocity_per_week = round(len(recent_completed) / 4.0, 1)

    # Recent events (last 20).
    recent_rows = list(
        db.scalars(
            select(AnalyticsEvent)
            .where(AnalyticsEvent.project_id == project_id)
            .order_by(AnalyticsEvent.created_at.desc(), AnalyticsEvent.id.desc())
            .limit(20)
        ).all()
    )
    actor_names: dict[int, str] = {}
    recent_events: list[DashboardEventOut] = []
    for ev in recent_rows:
        if ev.actor_id not in actor_names:
            actor = db.get(Assignee, ev.actor_id)
            actor_names[ev.actor_id] = actor.name if actor else "Unknown"
        recent_events.append(
            DashboardEventOut(
                id=ev.id,
                event_type=ev.event_type,  # type: ignore[arg-type]
                task_id=ev.task_id,
                actor_id=ev.actor_id,
                actor_name=actor_names[ev.actor_id],
                created_at=ev.created_at,
            )
        )

    return DashboardOut(
        project_id=project.id,
        project_name=project.name,
        total_tasks=total,
        completed_tasks=len(completed),
        pending_tasks=len(pending),
        overdue_tasks=len(overdue),
        completion_rate=completion_rate,
        overdue_rate=overdue_rate,
        priority_mix=priority_mix,
        velocity_per_week=velocity_per_week,
        recent_events=recent_events,
    )
