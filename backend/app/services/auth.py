"""Sign-up (admin bootstrap), login, token creation, and password reset."""
import hashlib
import secrets
import time
from datetime import timedelta
from typing import Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..core.config import PASSWORD_RESET_TTL_MINUTES
from ..core.errors import (
    ConflictError,
    NotFoundError,
    PendingAccountError,
    ProjectRequiredError,
    RuleError,
    UnauthorizedError,
)
from ..core.rules import ACTIVE, ADMIN, PENDING, USER, can_log_in
from ..core.security import create_token, hash_password, verify_password
from ..core.time import utc_now
from ..models import Assignee, PasswordResetToken, Project
from . import email_service
from . import notification_service
from . import totp

RESET_CODE_TTL = timedelta(minutes=PASSWORD_RESET_TTL_MINUTES)

# In-memory 2FA challenges: challenge_id -> (account_id, expires_at).
# Lost on restart; acceptable for MVP (user re-starts enrollment/login).
_2fa_challenges: dict[str, tuple[int, float]] = {}


def _make_challenge(account_id: int) -> str:
    token = secrets.token_urlsafe(32)
    _2fa_challenges[token] = (account_id, time.time() + 300)  # 5 min TTL
    return token


def consume_challenge(challenge_id: str) -> Optional[int]:
    entry = _2fa_challenges.pop(challenge_id, None)
    if entry is None:
        return None
    account_id, expires_at = entry
    if time.time() > expires_at:
        return None
    return account_id


def _hash_reset_code(code: str) -> str:
    """Store only a digest of the emailed code, never the code itself."""
    return hashlib.sha256(code.encode()).hexdigest()


def sign_up(
    db: Session,
    *,
    name: str,
    email: str,
    password: str,
    position: str | None,
    project_id: int | None,
) -> Assignee:
    """First account becomes the active admin; later sign-ups start pending.

    The row lock on existing accounts serializes two concurrent first
    sign-ups so only one can take the admin bootstrap.
    """
    existing = db.scalars(select(Assignee).with_for_update()).all()
    if any(account.email == email for account in existing):
        raise ConflictError("An account with this email already exists.")
    if not existing:
        role, status, project_id = ADMIN, ACTIVE, None
    else:
        if project_id is None:
            raise ProjectRequiredError()
        if db.get(Project, project_id) is None:
            raise NotFoundError("Project not found.")
        role, status = USER, PENDING
    account = Assignee(
        name=name,
        email=email,
        password_hash=hash_password(password),
        position=position,
        project_id=project_id,
        role=role,
        status=status,
    )
    db.add(account)
    db.commit()
    db.refresh(account)
    # Notify the project owner that a self-signed member needs confirmation.
    if status == PENDING and project_id is not None:
        project = db.get(Project, project_id)
        if project is not None and project.owner_id is not None:
            owner = db.get(Assignee, project.owner_id)
            if owner is not None:
                notification_service.notify_pending_signup(
                    db,
                    owner=owner,
                    new_member=account,
                    project_name=project.name,
                )
        db.commit()
    return account


def login(
    db: Session, *, email: str, password: str
) -> tuple[Assignee, str | None, str | None]:
    """Return the active account and a fresh token.

    If the account has 2FA enabled, returns (account, None, challenge_id):
    the client must then call POST /auth/2fa/verify with the challenge_id
    and a valid TOTP code to obtain the full token.
    """
    account = db.scalar(select(Assignee).where(Assignee.email == email))
    if account is None or not verify_password(password, account.password_hash):
        raise UnauthorizedError("Wrong email or password.")
    if not can_log_in(account.status):
        raise PendingAccountError()
    if account.totp_enabled:
        challenge_id = _make_challenge(account.id)
        return account, None, challenge_id
    return account, create_token(account.id, account.token_version), None


def request_password_reset(db: Session, *, email: str) -> None:
    """Email a single-use reset code to an existing active account.

    The caller always answers the same way, so this never reveals whether the
    account exists. Any code the account still has outstanding is invalidated
    first: only the newest code works.
    """
    account = db.scalar(select(Assignee).where(Assignee.email == email))
    if account is None or not can_log_in(account.status):
        return
    now = utc_now()
    for stale in db.scalars(
        select(PasswordResetToken).where(
            PasswordResetToken.account_id == account.id,
            PasswordResetToken.used_at.is_(None),
        )
    ):
        stale.used_at = now
    code = secrets.token_urlsafe(32)
    db.add(
        PasswordResetToken(
            account_id=account.id,
            token_hash=_hash_reset_code(code),
            expires_at=now + RESET_CODE_TTL,
        )
    )
    db.commit()
    email_service.send_async(
        account.email,
        "Task Planner password reset",
        f"Use this code to set a new password:\n\n{code}\n\n"
        f"It expires in {PASSWORD_RESET_TTL_MINUTES} minutes and can be used "
        "once. If you did not ask for a reset, ignore this email.",
    )


def reset_password(
    db: Session, *, email: str, code: str, new_password: str
) -> None:
    """Set a new password from a valid code and revoke every old session.

    Unknown emails, wrong codes, reused codes, and expired codes all raise the
    same error so the response cannot confirm that an account exists.
    """
    account = db.scalar(select(Assignee).where(Assignee.email == email))
    row = None
    if account is not None:
        row = db.scalar(
            select(PasswordResetToken).where(
                PasswordResetToken.account_id == account.id,
                PasswordResetToken.token_hash == _hash_reset_code(code),
                PasswordResetToken.used_at.is_(None),
            )
        )
    if account is None or row is None or row.expires_at <= utc_now():
        raise RuleError("Invalid or expired reset code.")
    now = utc_now()
    for outstanding in db.scalars(
        select(PasswordResetToken).where(
            PasswordResetToken.account_id == account.id,
            PasswordResetToken.used_at.is_(None),
        )
    ):
        outstanding.used_at = now
    account.password_hash = hash_password(new_password)
    # A11: tokens issued before this reset stop working immediately.
    account.token_version += 1
    db.commit()


def enroll_2fa(db: Session, account: Assignee) -> tuple[str, list[str]]:
    """Generate a TOTP secret and backup codes; store secret (not yet enabled)."""
    secret = totp.generate_secret()
    backup_codes = totp.generate_backup_codes()
    account.totp_secret = secret
    account.totp_backup_codes = backup_codes
    db.commit()
    return secret, backup_codes


def verify_2fa_enrollment(db: Session, account: Assignee, code: str) -> list[str]:
    """Verify a TOTP code and enable 2FA; return backup codes."""
    if not account.totp_secret:
        raise NotFoundError("No 2FA enrollment in progress.")
    if not totp.verify_totp(account.totp_secret, code):
        raise UnauthorizedError("Invalid verification code.")
    account.totp_enabled = True
    db.commit()
    return account.totp_backup_codes or []


def verify_2fa_code(db: Session, account: Assignee, code: str) -> bool:
    """Verify a TOTP code during login. Also accepts a single-use backup code."""
    if account.totp_secret and totp.verify_totp(account.totp_secret, code):
        return True
    if account.totp_backup_codes and code in account.totp_backup_codes:
        codes = list(account.totp_backup_codes)
        codes.remove(code)
        account.totp_backup_codes = codes
        db.commit()
        return True
    return False


def disable_2fa(db: Session, account: Assignee) -> None:
    """Disable 2FA and clear secret/codes."""
    account.totp_secret = None
    account.totp_enabled = False
    account.totp_backup_codes = None
    db.commit()
