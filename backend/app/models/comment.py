"""Task comments (soft-deleted, author-owned)."""
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from ..core.database import Base
from ..core.time import utc_now


class Comment(Base):
    __tablename__ = "comments"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    task_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("tasks.id"), index=True
    )
    author_id: Mapped[int] = mapped_column(Integer, ForeignKey("assignees.id"))
    parent_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    body: Mapped[str] = mapped_column(Text)
    mentions: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=utc_now, server_default=func.now()
    )
    edited_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
