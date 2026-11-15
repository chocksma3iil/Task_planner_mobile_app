"""Sign-up (admin bootstrap), login, and token creation."""
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..core.errors import (
    ConflictError,
    NotFoundError,
    PendingAccountError,
    ProjectRequiredError,
    UnauthorizedError,
)
from ..core.rules import ACTIVE, ADMIN, PENDING, USER, can_log_in
from ..core.security import create_token, hash_password, verify_password
from ..models import Assignee, Project
from .events import MEMBER_PENDING, notify


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
    db.flush()
    if status == PENDING:
        _notify_project_owner(db, account=account)
    db.commit()
    db.refresh(account)
    return account


def _notify_project_owner(db: Session, *, account: Assignee) -> None:
    project = db.get(Project, account.project_id) if account.project_id else None
    if project is None or project.owner_id is None:
        return
    notify(
        db,
        account_id=project.owner_id,
        type=MEMBER_PENDING,
        title="New member waiting",
        body=f"{account.name} asked to join {project.name}.",
        payload=str(account.id),
    )


def login(db: Session, *, email: str, password: str) -> tuple[Assignee, str]:
    """Return the active account and a fresh token."""
    account = db.scalar(select(Assignee).where(Assignee.email == email))
    if account is None or not verify_password(password, account.password_hash):
        raise UnauthorizedError("Wrong email or password.")
    if not can_log_in(account.status):
        raise PendingAccountError()
    return account, create_token(account.id, account.token_version)
