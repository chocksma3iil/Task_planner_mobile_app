"""Notification request/response shapes."""
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict

from .common import UtcDateTime

NotificationType = Literal[
    "task_created",
    "task_assigned",
    "task_completed",
    "task_reopened",
    "task_deleted",
    "member_added",
    "member_confirmed",
    "member_role_changed",
]


class NotificationOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    type: NotificationType
    title: str
    body: str | None = None
    payload: str | None = None
    read_at: datetime | None = None
    created_at: UtcDateTime


class NotificationListOut(BaseModel):
    items: list[NotificationOut]
    total: int
    unread: int
    limit: int
    offset: int


class MarkReadIn(BaseModel):
    notification_ids: list[int]
