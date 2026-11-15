"""Member management: creation, owner confirmation, admin role changes.

Scoping mirrors the Flutter MemberService: admins see/manage everyone,
owners only their own project, plain users only see their roster.
"""
from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from ..core.errors import ConflictError, ForbiddenError, NotFoundError, RuleError
from ..core.rules import (
    ACTIVE,
    PENDING,
    TEAM_LEAD,
    USER,
    VIEWER,
    is_admin,
    is_owner_or_admin,
    is_team_lead,
    is_viewer,
    require_admin,
    require_can_mutate,
    require_owner_or_admin,
)
from ..core.security import hash_password
from ..models import Assignee, Project, Task
from . import audit, notification_service


def list_members(db: Session, *, actor: Assignee, limit: int = 20, offset: int = 0) -> tuple[list[Assignee], int]:
    query = select(Assignee).order_by(Assignee.name)
    if not is_admin(actor.role):
        if actor.project_id is None:
            raise RuleError("Account has not been assigned to a project.")
        query = query.where(Assignee.project_id == actor.project_id)
    total = db.scalar(select(func.count()).select_from(query.subquery()))
    items = list(db.scalars(query.limit(limit).offset(offset)).all())
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
    require_can_mutate(actor.role)
    if not is_admin(actor.role):
        if not (is_owner_or_admin(actor.role) or is_team_lead(actor.role)):
            raise ForbiddenError("Only admins, owners, and team leads can add members.")
        if role != USER or project_id != actor.project_id:
            raise ForbiddenError("Owners and team leads can only add plain users to their project.")
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
    audit.record(
        db,
        actor=actor,
        action="member.created",
        entity_type="member",
        entity_id=account.id,
        project_id=project_id,
        details={"name": account.name, "role": role},
    )
    db.commit()
    db.refresh(account)
    # Notify the new member (if added by someone else).
    if account.id != actor.id:
        project = db.get(Project, project_id) if project_id else None
        notification_service.notify_member_added(
            db,
            member=account,
            actor=actor,
            project_name=project.name if project else "",
        )
        db.commit()
    return account


def confirm_member(
    db: Session, *, actor: Assignee, user_id: int
) -> Assignee:
    target = db.get(Assignee, user_id)
    if target is None:
        raise NotFoundError("Account not found.")
    require_can_mutate(actor.role)
    if not is_admin(actor.role):
        if not (is_owner_or_admin(actor.role) or is_team_lead(actor.role)):
            raise ForbiddenError("Only admins, owners, and team leads can confirm members.")
        if actor.project_id is None or target.project_id != actor.project_id:
            raise ForbiddenError("You can only confirm your own project members.")
    target.status = ACTIVE
    target.approved_by = actor.id
    audit.record(
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
    # Notify the confirmed member (if confirmed by someone else).
    if target.id != actor.id:
        project = db.get(Project, target.project_id) if target.project_id else None
        notification_service.notify_member_confirmed(
            db,
            member=target,
            actor=actor,
            project_name=project.name if project else "",
        )
        db.commit()
    return target


def change_role(
    db: Session, *, actor: Assignee, user_id: int, role: str
) -> Assignee:
    require_can_mutate(actor.role)
    require_admin(actor.role)
    target = db.get(Assignee, user_id)
    if target is None:
        raise NotFoundError("Account not found.")
    previous_role = target.role
    target.role = role
    audit.record(
        db,
        actor=actor,
        action="member.role_changed",
        entity_type="member",
        entity_id=target.id,
        project_id=target.project_id,
        details={"name": target.name, "from": previous_role, "to": role},
    )
    db.commit()
    db.refresh(target)
    # Notify the member (if changed by someone else).
    if target.id != actor.id:
        project = db.get(Project, target.project_id) if target.project_id else None
        notification_service.notify_member_role_changed(
            db,
            member=target,
            actor=actor,
            project_name=project.name if project else "",
            new_role=role,
        )
        db.commit()
    return target


def leave_project(
    db: Session, *, actor: Assignee, user_id: int
) -> Assignee:
    """A member leaves their own project (or is removed by an admin/owner).

    The member's project_id is cleared and their status is set to pending so
    they cannot log in until they join another project. Tasks they were
    assigned to revert to the whole project (assignee_id = NULL).
    """
    target = db.get(Assignee, user_id)
    if target is None:
        raise NotFoundError("Account not found.")
    require_can_mutate(actor.role)
    # A member can leave their own project; admins/owners can remove anyone.
    if actor.id != user_id and not is_admin(actor.role) and not is_owner_or_admin(
        actor.role
    ):
        raise ForbiddenError("You can only leave your own project.")
    if target.project_id is None:
        raise ConflictError("Account is not assigned to any project.")
    # An owner cannot leave their own project (must transfer ownership first).
    project = db.get(Project, target.project_id)
    if project is not None and project.owner_id == target.id:
        raise ConflictError(
            "Project owner cannot leave; transfer ownership first."
        )
    previous_project_id = target.project_id
    target.project_id = None
    target.status = PENDING
    # Revert assigned tasks to the whole project.
    from ..models import Task

    db.execute(
        update(Task)
        .where(Task.assignee_id == user_id, Task.project_id == previous_project_id)
        .values(assignee_id=None)
    )
    audit.record(
        db,
        actor=actor,
        action="member.left",
        entity_type="member",
        entity_id=target.id,
        project_id=previous_project_id,
        details={"name": target.name, "from_project": previous_project_id},
    )
    db.commit()
    db.refresh(target)
    return target


def transfer_member(
    db: Session, *, actor: Assignee, user_id: int, project_id: int
) -> Assignee:
    """Move a member to another project (admin or owner only).

    The member's tasks in the source project revert to the whole project
    (assignee_id = NULL). The target project must exist.
    """
    require_can_mutate(actor.role)
    if not (is_admin(actor.role) or is_owner_or_admin(actor.role)):
        raise ForbiddenError("Only admins and owners can transfer members.")
    target = db.get(Assignee, user_id)
    if target is None:
        raise NotFoundError("Account not found.")
    if target.project_id is None:
        raise ConflictError("Account is not assigned to any project.")
    target_project = db.get(Project, project_id)
    if target_project is None:
        raise NotFoundError("Target project not found.")
    if target.project_id == project_id:
        raise ConflictError("Account is already in that project.")
    # An owner cannot be transferred out of their own project.
    source_project = db.get(Project, target.project_id)
    if source_project is not None and source_project.owner_id == target.id:
        raise ConflictError(
            "Project owner cannot be transferred; transfer ownership first."
        )
    previous_project_id = target.project_id
    target.project_id = project_id
    # Revert assigned tasks in the source project to the whole project.
    from ..models import Task

    db.execute(
        update(Task)
        .where(
            Task.assignee_id == user_id, Task.project_id == previous_project_id
        )
        .values(assignee_id=None)
    )
    audit.record(
        db,
        actor=actor,
        action="member.transferred",
        entity_type="member",
        entity_id=target.id,
        project_id=project_id,
        details={
            "name": target.name,
            "from_project": previous_project_id,
            "to_project": project_id,
        },
    )
    db.commit()
    db.refresh(target)
    return target
