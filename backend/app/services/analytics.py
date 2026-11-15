"""Project dashboard metrics computed from tasks and recorded events."""
from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..core.errors import NotFoundError
from ..core.rules import require_project_access
from ..core.time import utc_now
from ..models import AnalyticsEvent, Assignee, Project, Task


def dashboard(
    db: Session, *, actor: Assignee, project_id: int
) -> dict:
    project = db.get(Project, project_id)
    if project is None:
        raise NotFoundError("Project not found.")
    require_project_access(actor.role, actor.project_id, project_id)

    rows = db.execute(
        select(
            Task.status,
            Task.priority,
            Task.due_date,
            Task.completed_at,
        ).where(Task.project_id == project_id)
    ).all()
    total = len(rows)
    today = date.today()
    completed = sum(1 for row in rows if row.status == "completed")
    pending = total - completed
    overdue = sum(
        1
        for row in rows
        if row.status != "completed"
        and row.due_date is not None
        and row.due_date < today
    )
    priority_mix = {"low": 0, "medium": 0, "high": 0}
    for row in rows:
        if row.priority in priority_mix:
            priority_mix[row.priority] += 1

    window_start = utc_now() - timedelta(days=28)
    recent_completions = sum(
        1
        for row in rows
        if row.completed_at is not None and row.completed_at >= window_start
    )

    events = list(
        db.scalars(
            select(AnalyticsEvent)
            .where(AnalyticsEvent.project_id == project_id)
            .order_by(
                AnalyticsEvent.created_at.desc(), AnalyticsEvent.id.desc()
            )
            .limit(10)
        ).all()
    )

    return {
        "project_id": project.id,
        "project_name": project.name,
        "total_tasks": total,
        "completed_tasks": completed,
        "pending_tasks": pending,
        "overdue_tasks": overdue,
        "completion_rate": round(100 * completed / total, 1) if total else 0.0,
        "overdue_rate": round(100 * overdue / total, 1) if total else 0.0,
        "priority_mix": priority_mix,
        "velocity_per_week": round(recent_completions / 4, 2),
        "recent_events": events,
    }
