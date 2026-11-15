"""Comments, subtasks, bulk task actions, and notification shapes."""
import json
from typing import Annotated

from pydantic import AfterValidator, BaseModel, ConfigDict, Field, field_validator

from .common import RequiredText, UtcDateTime


def _comment_body(value: str) -> str:
    text = value.strip()
    if not text:
        raise ValueError("Comment cannot be empty.")
    if len(text) > 2000:
        raise ValueError("Comment is too long (max 2000 characters).")
    return text


CommentBody = Annotated[str, AfterValidator(_comment_body)]


class CommentOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    task_id: int
    author_id: int
    body: str
    mentions: list[int] = Field(default_factory=list)
    created_at: UtcDateTime
    edited_at: UtcDateTime | None = None
    deleted_at: UtcDateTime | None = None

    @field_validator("mentions", mode="before")
    @classmethod
    def _parse_mentions(cls, value: object) -> list[int]:
        if value is None:
            return []
        if isinstance(value, str):
            try:
                parsed = json.loads(value)
            except ValueError:
                return []
            return [int(item) for item in parsed] if isinstance(parsed, list) else []
        return value  # type: ignore[return-value]


class CommentIn(BaseModel):
    task_id: int | None = None
    body: CommentBody
    parent_id: int | None = None


class CommentUpdate(BaseModel):
    body: CommentBody


class CommentList(BaseModel):
    items: list[CommentOut]
    total: int


class SubtaskOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    task_id: int
    title: str
    completed: bool
    sort_order: int
    created_at: UtcDateTime


class SubtaskIn(BaseModel):
    task_id: int | None = None
    title: RequiredText
    completed: bool = False
    sort_order: int = 0


class SubtaskUpdate(BaseModel):
    title: RequiredText | None = None
    completed: bool | None = None
    sort_order: int | None = None


class SubtaskList(BaseModel):
    items: list[SubtaskOut]
    total: int


class BulkTaskIn(BaseModel):
    task_ids: list[int] = Field(min_length=1, max_length=200)


class BulkReassignIn(BulkTaskIn):
    assignee_id: int


class BulkTaskItemOut(BaseModel):
    task_id: int
    success: bool
    error: str | None = None


class BulkTaskOut(BaseModel):
    results: list[BulkTaskItemOut]
    total: int
    succeeded: int
    failed: int


class NotificationOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    type: str
    title: str
    body: str | None = None
    payload: str | None = None
    read_at: UtcDateTime | None = None
    created_at: UtcDateTime


class NotificationPage(BaseModel):
    items: list[NotificationOut]
    total: int
    unread: int
    limit: int
    offset: int


class NotificationReadIn(BaseModel):
    notification_ids: list[int] = Field(min_length=1, max_length=500)
