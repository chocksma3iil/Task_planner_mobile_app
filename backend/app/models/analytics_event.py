"""Analytics events table.

One row per task status change or lifecycle event, used to compute project
dashboard metrics (completion rate, overdue %, velocity, priority mix).
"""
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from ..core.database import Base
from ..core.time import utc_now


class AnalyticsEvent(Base):
    __tablename__ = "analytics_events"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    project_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("projects.id"), index=True, nullable=False
    )
    actor_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("assignees.id"), index=True, nullable=False
    )
    event_type: Mapped[str] = mapped_column(String(64), nullable=False)
    task_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    payload: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=utc_now, server_default=func.now()
    )

    project = relationship("Project", foreign_keys=[project_id])
    actor = relationship("Assignee", foreign_keys=[actor_id])
