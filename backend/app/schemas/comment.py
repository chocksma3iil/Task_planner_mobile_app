"""Comment request/response shapes."""
from typing import Any

from pydantic import BaseModel, ConfigDict, Field

from .common import RequiredText, UtcDateTime


class CommentOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    task_id: int
    author_id: int
    body: str
    mentions: list[int] = Field(default_factory=list)
    created_at: UtcDateTime | None = None
    edited_at: UtcDateTime | None = None
    deleted_at: UtcDateTime | None = None

    author_name: str | None = None
    can_mutate: bool | None = None


class CommentIn(BaseModel):
    task_id: int
    body: RequiredText
    mentions: list[int] = Field(default_factory=list)


class CommentUpdate(BaseModel):
    """Partial update; only body may be edited."""

    body: RequiredText


class CommentListOut(BaseModel):
    items: list[CommentOut]
    total: int
