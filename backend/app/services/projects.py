"""Project management: admin-only creation, owner assignment, archiving."""
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..core.errors import NotFoundError, RuleError
from ..core.rules import (
    PROJECT_OWNER,
    can_log_in,
    is_admin,
    require_admin,
    require_owner_or_admin,
)
from ..models import Assignee, Project
from .events import record_audit
from .exports import build_export


def list_projects(
    db: Session,
    *,
    limit: int = 20,
    offset: int = 0,
    include_archived: bool = False,
) -> tuple[list[Project], int]:
    """One page of projects sorted by name, with the total count.

    Public for the sign-up screen; archived rows are hidden unless
    [include_archived] is true.
    """
    query = select(Project)
    if not include_archived:
        query = query.where(Project.status != "archived")
    total = db.scalar(select(func.count()).select_from(query.subquery()))
    items = list(
        db.scalars(
            query.order_by(Project.name, Project.id).limit(limit).offset(offset)
        ).all()
    )
    return items, total


def create_project(
    db: Session,
    *,
    actor: Assignee,
    name: str,
    description: str | None,
) -> Project:
    require_admin(actor.role)
    project = Project(name=name, description=description)
    db.add(project)
    db.flush()
    record_audit(
        db,
        actor=actor,
        action="project.created",
        entity_type="project",
        entity_id=project.id,
        project_id=project.id,
        details={"name": project.name},
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
    require_admin(actor.role)
    project = db.get(Project, project_id)
    if project is None:
        raise NotFoundError("Project not found.")
    owner = db.get(Assignee, owner_id)
    if owner is None:
        raise NotFoundError("Account not found.")
    if not can_log_in(owner.status):
        raise RuleError("The owner account must be active.")
    owner.project_id = project_id
    owner.role = PROJECT_OWNER
    project.owner_id = owner.id
    record_audit(
        db,
        actor=actor,
        action="project.owner_assigned",
        entity_type="project",
        entity_id=project.id,
        project_id=project.id,
        details={"owner_id": owner.id, "owner_name": owner.name},
    )
    db.commit()
    db.refresh(project)
    return project


def archive_project(
    db: Session, *, actor: Assignee, project_id: int
) -> Project:
    project = _archived_target(db, actor=actor, project_id=project_id)
    project.status = "archived"
    record_audit(
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


def restore_project(
    db: Session, *, actor: Assignee, project_id: int
) -> Project:
    project = _archived_target(db, actor=actor, project_id=project_id)
    project.status = "active"
    record_audit(
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


def set_ai_opt_in(
    db: Session, *, actor: Assignee, project_id: int, enabled: bool
) -> Project:
    require_owner_or_admin(actor.role)
    project = db.get(Project, project_id)
    if project is None:
        raise NotFoundError("Project not found.")
    if not is_admin(actor.role) and actor.project_id != project_id:
        raise RuleError("You can only change your own project.")
    project.ai_opt_in = enabled
    db.commit()
    db.refresh(project)
    return project


def _archived_target(
    db: Session, *, actor: Assignee, project_id: int
) -> Project:
    require_admin(actor.role)
    project = db.get(Project, project_id)
    if project is None:
        raise NotFoundError("Project not found.")
    return project