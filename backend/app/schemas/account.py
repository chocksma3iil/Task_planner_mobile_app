"""Account, auth, and member request/response shapes."""
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

from .common import Email, Position, RequiredText, UtcDateTime

Role = Literal["admin", "project_owner", "team_lead", "user", "viewer"]


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
    access_token: str | None = None
    token_type: str = "bearer"
    account: AccountOut
    two_factor_required: bool = False
    challenge_id: str | None = None


class ForgotPasswordIn(BaseModel):
    email: Email


class ResetPasswordIn(BaseModel):
    email: Email
    code: str = Field(min_length=8, max_length=128)
    new_password: str = Field(min_length=8, max_length=72)


class MessageOut(BaseModel):
    message: str


class MemberIn(BaseModel):
    name: RequiredText
    email: Email
    password: str = Field(min_length=8, max_length=72)
    position: Position = None
    project_id: int | None = None
    role: Role = "user"


class RoleIn(BaseModel):
    role: Role


class AccountListOut(BaseModel):
    items: list[AccountOut]
    total: int
    limit: int
    offset: int


# --- 2FA (A12) ---


class TwoFactorEnrollOut(BaseModel):
    secret: str
    backup_codes: list[str]


class TwoFactorVerifyIn(BaseModel):
    challenge_id: str
    code: str = Field(min_length=6, max_length=8)


class TwoFactorVerifyOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    account_id: int


class TwoFactorDisableIn(BaseModel):
    pass


class TwoFactorStatusOut(BaseModel):
    totp_enabled: bool
    has_backup_codes: bool


class TransferMemberIn(BaseModel):
    project_id: int
