"""Sign-up (with first-account admin bootstrap), login, session lookup, and
self-service password reset (A10)."""
from fastapi import APIRouter, Request

from ...core.errors import UnauthorizedError
from ...core.rate_limit import login_throttle
from ...models import Assignee
from ...schemas import (
    AccountOut,
    ForgotPasswordIn,
    LoginIn,
    LoginOut,
    MessageOut,
    ResetPasswordIn,
    SignUpIn,
    TwoFactorDisableIn,
    TwoFactorEnrollOut,
    TwoFactorStatusOut,
    TwoFactorVerifyIn,
    TwoFactorVerifyOut,
)
from ...core.security import create_token
from ...services import auth as auth_service
from ...services.auth import consume_challenge
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
def login(body: LoginIn, db: DbSession, request: Request) -> LoginOut:
    """Authenticate; repeated failures for the same client + email are 429.

    If the account has 2FA enabled, returns two_factor_required=true with a
    challenge_id; the client must then call POST /auth/2fa/verify.
    """
    client = request.client.host if request.client else "unknown"
    key = f"{client}:{body.email.strip().lower()}"
    login_throttle.check(key)
    try:
        account, token, challenge_id = auth_service.login(
            db, email=body.email, password=body.password
        )
    except UnauthorizedError:
        login_throttle.fail(key)
        raise
    login_throttle.reset(key)
    if challenge_id is not None:
        return LoginOut(
            two_factor_required=True,
            challenge_id=challenge_id,
            account=account,
        )
    return LoginOut(access_token=token, account=account)


@router.post("/forgot-password", response_model=MessageOut, status_code=202)
def forgot_password(
    body: ForgotPasswordIn, db: DbSession, request: Request
) -> MessageOut:
    """Start a password reset; the answer never reveals whether the email exists.

    Every request counts against the login throttle so the endpoint cannot be
    used to flood a mailbox.
    """
    client = request.client.host if request.client else "unknown"
    key = f"reset:{client}:{body.email.strip().lower()}"
    login_throttle.check(key)
    login_throttle.fail(key)
    auth_service.request_password_reset(db, email=body.email)
    return MessageOut(
        message="If the account exists, a reset code has been sent."
    )


@router.post("/reset-password", response_model=MessageOut)
def reset_password(body: ResetPasswordIn, db: DbSession) -> MessageOut:
    """Set a new password from an emailed code and revoke old sessions."""
    auth_service.reset_password(
        db,
        email=body.email,
        code=body.code,
        new_password=body.new_password,
    )
    return MessageOut(message="Password updated. Log in with the new password.")


@router.get("/me", response_model=AccountOut)
def me(user: CurrentUser) -> Assignee:
    return user


@router.post("/2fa/enroll", response_model=TwoFactorEnrollOut)
def enroll_2fa(db: DbSession, user: CurrentUser) -> TwoFactorEnrollOut:
    """Generate a TOTP secret and backup codes (2FA not yet active)."""
    secret, backup_codes = auth_service.enroll_2fa(db, user)
    return TwoFactorEnrollOut(secret=secret, backup_codes=backup_codes)


@router.post("/2fa/verify", response_model=TwoFactorVerifyOut)
def verify_2fa_enrollment(
    body: TwoFactorVerifyIn, db: DbSession, user: CurrentUser
) -> TwoFactorVerifyOut:
    """Verify a TOTP code and enable 2FA; return backup codes."""
    backup_codes = auth_service.verify_2fa_enrollment(db, user, body.code)
    token = create_token(user.id, user.token_version)
    return TwoFactorVerifyOut(access_token=token, account_id=user.id)


@router.post("/2fa/login", response_model=TwoFactorVerifyOut)
def verify_2fa_login(
    body: TwoFactorVerifyIn, db: DbSession
) -> TwoFactorVerifyOut:
    """Verify a TOTP code using a login challenge; return the full token."""
    account_id = consume_challenge(body.challenge_id)
    if account_id is None:
        raise UnauthorizedError("Invalid or expired challenge.")
    account = db.get(Assignee, account_id)
    if account is None:
        raise UnauthorizedError("Unknown account.")
    if not auth_service.verify_2fa_code(db, account, body.code):
        raise UnauthorizedError("Invalid verification code.")
    token = create_token(account.id, account.token_version)
    return TwoFactorVerifyOut(access_token=token, account_id=account.id)


@router.post("/2fa/disable", response_model=MessageOut)
def disable_2fa(db: DbSession, user: CurrentUser) -> MessageOut:
    """Disable 2FA."""
    auth_service.disable_2fa(db, user)
    return MessageOut(message="2FA disabled.")


@router.get("/2fa/status", response_model=TwoFactorStatusOut)
def two_factor_status(user: CurrentUser) -> TwoFactorStatusOut:
    """Return 2FA status for the current account."""
    return TwoFactorStatusOut(
        totp_enabled=user.totp_enabled,
        has_backup_codes=bool(user.totp_backup_codes),
    )
