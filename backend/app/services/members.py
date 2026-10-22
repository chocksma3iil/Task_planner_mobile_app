"""Member management: creation, owner confirmation, admin role changes.

Scoping mirrors the Flutter MemberService: admins see/manage everyone,
owners only their own project, plain users only see their roster.
"""
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..core.errors import ConflictError, NotFoundError, RuleError
from ..core.rules import (
    ACTIVE,
    USER,
    is_admin,
    require_admin,
    require_owner_or_admin,
)
from ..core.security import hash_password
from ..models import Assignee, Project


def list_members(db: Session, *, actor: Assignee) -> list[Assignee]:
    query = select(Assignee).order_by(Assignee.name)
    if not is_admin(actor.role):
        if actor.project_id is None:
            raise RuleError("Account has not been assigned to a project.")
        query = query.where(Assignee.project_id == actor.project_id)
    return list(db.scalars(query).all())


def create_member(
    db: Session,
    *,
    actor: Assignee,
    name: str,
    email: str,
    password: str,
    position: str | None,
    project_id: int | None,
    role: str,
) -> Assignee:
    if not is_admin(actor.role):
        require_owner_or_admin(actor.role)
        if role != USER or project_id != actor.project_id:
            raise RuleError("Owners can only add plain users to their project.")
    if db.scalar(select(Assignee).where(Assignee.email == email)):
        raise ConflictError("An account with this email already exists.")
    if project_id is not None and db.get(Project, project_id) is None:
        raise NotFoundError("Project not found.")
    account = Assignee(
        name=name,
        email=email,
        password_hash=hash_password(password),
        position=position,
        project_id=project_id,
        role=role,
        status=ACTIVE,
        approved_by=actor.id,
    )
    db.add(account)
    db.commit()
    db.refresh(account)
    return account


def confirm_member(
    db: Session, *, actor: Assignee, user_id: int
) -> Assignee:
    target = db.get(Assignee, user_id)
    if target is None:
        raise NotFoundError("Account not found.")
    if not is_admin(actor.role):
        require_owner_or_admin(actor.role)
        if actor.project_id is None or target.project_id != actor.project_id:
            raise RuleError("You can only confirm your own project members.")
    target.status = ACTIVE
    target.approved_by = actor.id
    db.commit()
    db.refresh(target)
    return target


def change_role(
    db: Session, *, actor: Assignee, user_id: int, role: str
) -> Assignee:
    require_admin(actor.role)
    target = db.get(Assignee, user_id)
    if target is None:
        raise NotFoundError("Account not found.")
    target.role = role
    db.commit()
    db.refresh(target)
    return target
