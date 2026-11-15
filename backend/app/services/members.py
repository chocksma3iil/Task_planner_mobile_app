"""Member management: creation, owner/team-lead confirmation, role changes.

Scoping mirrors the Flutter MemberService: admins see/manage everyone,
owners and team leads manage their own project, plain users only read.
"""
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..core.errors import ConflictError, NotFoundError, RuleError
from ..core.rules import (
    ACTIVE,
    PROJECT_OWNER,
    TEAM_LEAD,
    USER,
    can_confirm_members,
    is_admin,
    require_admin,
)
from ..core.security import hash_password
from ..models import Assignee, Project
from .events import record_audit


def list_members(
    db: Session,
    *,
    actor: Assignee,
    limit: int = 20,
    offset: int = 0,
) -> tuple[list[Assignee], int]:
    """One page of visible members sorted by name, with the total count."""
    query = select(Assignee)
    if not is_admin(actor.role):
        if actor.project_id is None:
            raise RuleError("Account has not been assigned to a project.")
        query = query.where(Assignee.project_id == actor.project_id)
    total = db.scalar(select(func.count()).select_from(query.subquery()))
    items = list(
        db.scalars(
            query.order_by(Assignee.name, Assignee.id).limit(limit).offset(offset)
        ).all()
    )
    return items, total


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
        if not can_confirm_members(actor.role):
            raise RuleError(
                "Only an owner, team lead, or admin can add members."
            )
        if role != USER or project_id != actor.project_id:
            raise RuleError(
                "Owners and team leads can only add plain users to their project."
            )
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
    db.flush()
    record_audit(
        db,
        actor=actor,
        action="member.created",
        entity_type="member",
        entity_id=account.id,
        project_id=account.project_id,
        details={"name": account.name, "role": account.role},
    )
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
        if not can_confirm_members(actor.role):
            raise RuleError("Only an owner, team lead, or admin can confirm members.")
        if actor.project_id is None or target.project_id != actor.project_id:
            raise RuleError("You can only confirm your own project members.")
    target.status = ACTIVE
    target.approved_by = actor.id
    record_audit(
        db,
        actor=actor,
        action="member.confirmed",
        entity_type="member",
        entity_id=target.id,
        project_id=target.project_id,
        details={"name": target.name},
    )
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
    previous = target.role
    if target.project_id is not None:
        project = db.get(Project, target.project_id)
        if (
            project is not None
            and project.owner_id == target.id
            and role != PROJECT_OWNER
        ):
            raise RuleError(
                "Assign another owner before changing this account's role."
            )
    target.role = role
    record_audit(
        db,
        actor=actor,
        action="member.role_changed",
        entity_type="member",
        entity_id=target.id,
        project_id=target.project_id,
        details={"name": target.name, "from": previous, "to": role},
    )
    db.commit()
    db.refresh(target)
    return target