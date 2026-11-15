"""Sign-up (with first-account admin bootstrap), login, session, reset."""
from fastapi import APIRouter

from ...models import Assignee
from ...schemas import (
    AccountOut,
    ForgotPasswordIn,
    LoginIn,
    LoginOut,
    MessageOut,
    ResetPasswordIn,
    SignUpIn,
)
from ...services import auth as auth_service
from ...services import password_reset as reset_service
from ..deps import CurrentUser, DbSession

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/signup", response_model=AccountOut, status_code=201)
def sign_up(body: SignUpIn, db: DbSession) -> Assignee:
    return auth_service.sign_up(
        db,
        name=body.name,
        email=body.email,
        password=body.password,
        position=body.position,
        project_id=body.project_id,
    )


@router.post("/login", response_model=LoginOut)
def login(body: LoginIn, db: DbSession) -> LoginOut:
    account, token = auth_service.login(
        db, email=body.email, password=body.password
    )
    return LoginOut(access_token=token, account=account)


@router.get("/me", response_model=AccountOut)
def me(user: CurrentUser) -> Assignee:
    return user


@router.post("/forgot-password", response_model=MessageOut)
def forgot_password(body: ForgotPasswordIn, db: DbSession) -> dict:
    return reset_service.request_reset(db, email=body.email)


@router.post("/reset-password", response_model=MessageOut)
def reset_password(body: ResetPasswordIn, db: DbSession) -> dict:
    return reset_service.reset_password(
        db,
        email=body.email,
        code=body.code,
        new_password=body.new_password,
    )
