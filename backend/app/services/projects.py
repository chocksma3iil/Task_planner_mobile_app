"""Project management: admin-only creation and owner assignment."""
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..core.errors import NotFoundError, RuleError
from ..core.rules import PROJECT_OWNER, can_log_in, require_admin
from ..models import Assignee, Project


def list_projects(db: Session) -> list[Project]:
    """All projects, sorted by name (public for the sign-up screen)."""
    return list(db.scalars(select(Project).order_by(Project.name)).all())


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
    db.commit()
    db.refresh(project)
    return project
