"""Project management: admin-only creation and owner assignment."""
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..core.errors import NotFoundError, RuleError
from ..core.rules import (
    PROJECT_OWNER,
    VIEWER,
    can_log_in,
    is_admin,
    is_viewer,
    require_admin,
    require_can_mutate,
)
from ..models import Assignee, Project
from . import audit


def list_projects(
    db: Session,
    *,
    limit: int = 20,
    offset: int = 0,
    include_archived: bool = False,
) -> tuple[list[Project], int]:
    """All projects, sorted by name (public for the sign-up screen).

    By default excludes archived projects unless [include_archived] is true.
    """
    query = select(Project).order_by(Project.name)
    if not include_archived:
        query = query.where(Project.status != "archived")
    total = db.scalar(select(func.count()).select_from(query.subquery()))
    items = list(db.scalars(query.limit(limit).offset(offset)).all())
    return items, total


def archive_project(db: Session, *, actor: Assignee, project_id: int) -> Project:
    """Archive a project (admin only). Archiving hides it from default lists."""
    require_can_mutate(actor.role)
    require_admin(actor.role)
    project = db.get(Project, project_id)
    if project is None:
        raise NotFoundError("Project not found.")
    project.status = "archived"
    audit.record(
        db,
        actor=actor,
        action="project.archived",
        entity_type="project",
        entity_id=project.id,
        project_id=project.id,
        details={"name": project.name},
    )
    db.commit()
    db.refresh(project)
    return project


def restore_project(db: Session, *, actor: Assignee, project_id: int) -> Project:
    """Restore an archived project (admin only)."""
    require_can_mutate(actor.role)
    require_admin(actor.role)
    project = db.get(Project, project_id)
    if project is None:
        raise NotFoundError("Project not found.")
    project.status = "active"
    audit.record(
        db,
        actor=actor,
        action="project.restored",
        entity_type="project",
        entity_id=project.id,
        project_id=project.id,
        details={"name": project.name},
    )
    db.commit()
    db.refresh(project)
    return project


def create_project(
    db: Session,
    *,
    actor: Assignee,
    name: str,
    description: str | None,
) -> Project:
    require_can_mutate(actor.role)
    require_admin(actor.role)
    project = Project(name=name, description=description)
    db.add(project)
    db.flush()
    audit.record(
        db,
        actor=actor,
        action="project.created",
        entity_type="project",
        entity_id=project.id,
        project_id=project.id,
        details={"name": name},
    )
    db.commit()
    db.refresh(project)
    return project


def assign_owner(
    db: Session,
    *,
    actor: Assignee,
    project_id: int,
    owner_id: int,
) -> Project:
    require_can_mutate(actor.role)
    require_admin(actor.role)
    project = db.get(Project, project_id)
    if project is None:
        raise NotFoundError("Project not found.")
    owner = db.get(Assignee, owner_id)
    if owner is None:
        raise NotFoundError("Account not found.")
    if not can_log_in(owner.status):
        raise RuleError("The owner account must be active.")
    previous_role = owner.role
    previous_project = owner.project_id
    owner.project_id = project_id
    owner.role = PROJECT_OWNER
    project.owner_id = owner.id
    audit.record(
        db,
        actor=actor,
        action="project.owner_assigned",
        entity_type="member",
        entity_id=owner.id,
        project_id=project.id,
        details={
            "owner_id": owner.id,
            "owner_name": owner.name,
            "previous_role": previous_role,
            "previous_project_id": previous_project,
        },
    )
    db.commit()
    db.refresh(project)
    return project
