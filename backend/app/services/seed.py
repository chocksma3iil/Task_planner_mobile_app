"""Idempotent demo data for local development.

Seeding bypasses the normal first-signup admin bootstrap, so it is gated by
``SEED_DEMO_DATA`` and refused in production. Existing accounts, projects, and
tasks are never modified or duplicated.
"""
from datetime import date, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..core.rules import (
    ACTIVE,
    ADMIN,
    PROJECT_OWNER,
    TASK_COMPLETED,
    TASK_TODO,
    USER,
)
from ..core.security import hash_password
from ..core.time import utc_now
from ..models import Assignee, Project, Task

DEMO_PASSWORD = "12345678"
DEMO_PROJECT_NAME = "Demo Project"
DEMO_ADMIN_EMAIL = "admin@demo.local"
DEMO_MANAGER_EMAIL = "manager@demo.local"
DEMO_STAFF_EMAILS = (
    "staff1@demo.local",
    "staff2@demo.local",
    "staff3@demo.local",
)


def seed_demo_data(db: Session) -> None:
    """Create the demo admin, manager, staff, project, and tasks if missing."""
    project = _ensure_project(db)
    admin = _ensure_account(
        db,
        name="Demo Admin",
        email=DEMO_ADMIN_EMAIL,
        position="Administrator",
        role=ADMIN,
        project_id=None,
    )
    manager = _ensure_account(
        db,
        name="Demo Project Manager",
        email=DEMO_MANAGER_EMAIL,
        position="Project Manager",
        role=PROJECT_OWNER,
        project_id=project.id,
        approved_by=admin.id,
    )
    staff = [
        _ensure_account(
            db,
            name="Demo Staff One",
            email=DEMO_STAFF_EMAILS[0],
            position="Developer",
            role=USER,
            project_id=project.id,
            approved_by=manager.id,
        ),
        _ensure_account(
            db,
            name="Demo Staff Two",
            email=DEMO_STAFF_EMAILS[1],
            position="Designer",
            role=USER,
            project_id=project.id,
            approved_by=manager.id,
        ),
        _ensure_account(
            db,
            name="Demo Staff Three",
            email=DEMO_STAFF_EMAILS[2],
            position="QA Engineer",
            role=USER,
            project_id=project.id,
            approved_by=manager.id,
        ),
    ]
    if project.owner_id is None:
        project.owner_id = manager.id

    today = date.today()
    now = utc_now()
    _ensure_task(
        db,
        project_id=project.id,
        title="Review demo project plan",
        description="Check the plan and confirm the next steps.",
        assignee_id=manager.id,
        priority="high",
        due_date=today + timedelta(days=2),
    )
    _ensure_task(
        db,
        project_id=project.id,
        title="Prepare weekly status report",
        description="Summarize progress for the project owner.",
        assignee_id=staff[0].id,
        priority="medium",
        due_date=today + timedelta(days=3),
    )
    _ensure_task(
        db,
        project_id=project.id,
        title="Update project documentation",
        description="Refresh the shared documentation for the whole project.",
        assignee_id=None,
        priority="low",
        due_date=today + timedelta(days=5),
    )
    _ensure_task(
        db,
        project_id=project.id,
        title="Set up development environment",
        description="Install the tools and run the app locally.",
        assignee_id=staff[1].id,
        priority="medium",
        due_date=today - timedelta(days=1),
        status=TASK_COMPLETED,
        completed_at=now,
    )
    _ensure_task(
        db,
        project_id=project.id,
        title="Test the login flow",
        description="Verify login, logout, and pending-account behavior.",
        assignee_id=staff[2].id,
        priority="high",
        due_date=today + timedelta(days=1),
    )
    _ensure_task(
        db,
        project_id=project.id,
        title="Run the release checklist",
        description="Complete the pre-release checks.",
        assignee_id=staff[0].id,
        priority="low",
        due_date=today - timedelta(days=3),
        status=TASK_COMPLETED,
        completed_at=now,
    )
    db.commit()


def _ensure_project(db: Session) -> Project:
    project = db.scalar(select(Project).where(Project.name == DEMO_PROJECT_NAME))
    if project is not None:
        return project
    project = Project(
        name=DEMO_PROJECT_NAME,
        description="Seeded demo project for local development.",
    )
    db.add(project)
    db.flush()
    return project


def _ensure_account(
    db: Session,
    *,
    name: str,
    email: str,
    position: str,
    role: str,
    project_id: int | None,
    approved_by: int | None = None,
) -> Assignee:
    account = db.scalar(select(Assignee).where(Assignee.email == email))
    if account is not None:
        return account
    account = Assignee(
        name=name,
        email=email,
        position=position,
        password_hash=hash_password(DEMO_PASSWORD),
        role=role,
        status=ACTIVE,
        project_id=project_id,
        approved_by=approved_by,
    )
    db.add(account)
    db.flush()
    return account


def _ensure_task(
    db: Session,
    *,
    project_id: int,
    title: str,
    description: str,
    assignee_id: int | None,
    priority: str,
    due_date: date,
    status: str = TASK_TODO,
    completed_at: datetime | None = None,
) -> Task:
    task = db.scalar(
        select(Task).where(Task.project_id == project_id, Task.title == title)
    )
    if task is not None:
        return task
    task = Task(
        project_id=project_id,
        title=title,
        description=description,
        assignee_id=assignee_id,
        priority=priority,
        due_date=due_date,
        status=status,
        completed_at=completed_at,
    )
    db.add(task)
    db.flush()
    return task
