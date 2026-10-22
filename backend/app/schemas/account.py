"""Account, auth, and member request/response shapes."""
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

from .common import Email, Position, RequiredText, UtcDateTime

Role = Literal["admin", "project_owner", "user"]


class AccountOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    position: str | None = None
    project_id: int | None = None
    email: str
    role: str
    status: str
    approved_by: int | None = None
    created_at: UtcDateTime


class SignUpIn(BaseModel):
    name: RequiredText
    email: Email
    password: str = Field(min_length=8, max_length=72)
    position: Position = None
    project_id: int | None = None


class LoginIn(BaseModel):
    email: Email
    password: str


class LoginOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    account: AccountOut


class MemberIn(BaseModel):
    name: RequiredText
    email: Email
    password: str = Field(min_length=8, max_length=72)
    position: Position = None
    project_id: int | None = None
    role: Role = "user"


class RoleIn(BaseModel):
    role: Role
