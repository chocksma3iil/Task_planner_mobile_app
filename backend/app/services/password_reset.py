"""Single-use password-reset codes.

In development the generated code is returned as `dev_code` so the flow can
be exercised without an email service; production responses only contain the
generic confirmation message.
"""
import secrets
from datetime import timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..core.config import ENVIRONMENT
from ..core.errors import RuleError
from ..core.rules import can_log_in
from ..core.security import hash_password, verify_password
from ..core.time import utc_now
from ..models import Assignee, PasswordReset

RESET_TTL_MINUTES = 15
GENERIC_MESSAGE = "If the account exists, a reset code was sent."


def request_reset(db: Session, *, email: str) -> dict:
    account = db.scalar(select(Assignee).where(Assignee.email == email))
    if account is None or not can_log_in(account.status):
        return {"message": GENERIC_MESSAGE}

    for previous in db.scalars(
        select(PasswordReset).where(
            PasswordReset.email == email, PasswordReset.used_at.is_(None)
        )
    ).all():
        previous.used_at = utc_now()

    code = f"{secrets.randbelow(1_000_000):06d}"
    reset = PasswordReset(
        email=email,
        code_hash=hash_password(code),
        expires_at=utc_now() + timedelta(minutes=RESET_TTL_MINUTES),
    )
    db.add(reset)
    db.commit()
    response = {"message": GENERIC_MESSAGE}
    if ENVIRONMENT != "production":
        response["dev_code"] = code
    return response


def reset_password(
    db: Session, *, email: str, code: str, new_password: str
) -> dict:
    reset = db.scalar(
        select(PasswordReset)
        .where(
            PasswordReset.email == email,
            PasswordReset.used_at.is_(None),
            PasswordReset.expires_at > utc_now(),
        )
        .order_by(PasswordReset.created_at.desc(), PasswordReset.id.desc())
    )
    if reset is None or not verify_password(code, reset.code_hash):
        raise RuleError("Invalid or expired reset code.")
    account = db.scalar(select(Assignee).where(Assignee.email == email))
    if account is None:
        raise RuleError("Invalid or expired reset code.")

    reset.used_at = utc_now()
    account.password_hash = hash_password(new_password)
    account.token_version += 1
    db.commit()
    return {"message": "Password updated. Log in with the new password."}
