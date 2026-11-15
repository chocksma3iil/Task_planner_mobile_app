"""Per-account notifications."""
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from ..core.database import Base
from ..core.time import utc_now


class Notification(Base):
    __tablename__ = "notifications"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    account_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("assignees.id"), index=True
    )
    type: Mapped[str] = mapped_column(String(32))
    title: Mapped[str] = mapped_column(String(255))
    body: Mapped[str | None] = mapped_column(Text, nullable=True)
    payload: Mapped[str | None] = mapped_column(String(255), nullable=True)
    read_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=utc_now, server_default=func.now(), index=True
    )
