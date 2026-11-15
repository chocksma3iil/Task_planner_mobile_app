"""Account table (historically named `assignees`).

One row per person; accounts double as project members and task assignees.
"""
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, JSON, String, func
from sqlalchemy.orm import Mapped, mapped_column

from ..core.database import Base
from ..core.time import utc_now


class Assignee(Base):
    __tablename__ = "assignees"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(255))
    position: Mapped[str | None] = mapped_column(String(127), nullable=True)
    project_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("projects.id"), nullable=True, index=True
    )
    email: Mapped[str] = mapped_column(String(255), unique=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    role: Mapped[str] = mapped_column(String(32), server_default="user")
    status: Mapped[str] = mapped_column(String(32), server_default="pending")
    # Plain id on purpose (no SQL self-FK): enforced in the service layer.
    approved_by: Mapped[int | None] = mapped_column(Integer, nullable=True)
    # Bumped on password reset (A11): every older token fails its version check.
    token_version: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    # 2FA (A12): TOTP secret (base32), enabled flag, and single-use backup codes.
    totp_secret: Mapped[str | None] = mapped_column(String(255), nullable=True)
    totp_enabled: Mapped[bool] = mapped_column(
        Integer, server_default="0", default=False, nullable=False
    )
    totp_backup_codes: Mapped[list[str] | None] = mapped_column(
        JSON, nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=utc_now, server_default=func.now()
    )
