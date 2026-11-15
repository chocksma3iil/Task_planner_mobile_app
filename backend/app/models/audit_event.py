"""Admin audit trail rows."""
from datetime import datetime

from sqlalchemy import DateTime, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from ..core.database import Base
from ..core.time import utc_now


class AuditEvent(Base):
    __tablename__ = "audit_events"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    actor_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    actor_name: Mapped[str] = mapped_column(String(255))
    action: Mapped[str] = mapped_column(String(64))
    entity_type: Mapped[str] = mapped_column(String(32))
    entity_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    project_id: Mapped[int | None] = mapped_column(
        Integer, nullable=True, index=True
    )
    details: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=utc_now, server_default=func.now()
    )
