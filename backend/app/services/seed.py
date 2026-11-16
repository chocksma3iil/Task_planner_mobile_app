"""Seed data for the first run of a fresh database.

Creates a demo project, a handful of members spanning all five roles, and
sample tasks. Only runs when the `assignees` table is empty so it never
overwrites real data on restart.
"""

from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..core.security import hash_password
from ..models import Assignee, Project, Task

# ---------------------------------------------------------------------------
# Demo credentials — change these before any non-local deployment.
# ---------------------------------------------------------------------------
SEED_PASSWORD = "Planner2026!"

SEED_PROJECT = {
    "name": "Acme Website Redesign",
    "description": "Redesign the Acme corporate website with a modern design "
    "system, new navigation, and a task-driven content workflow.",
}

SEED_MEMBERS = [
    {
        "name": "Admin User",
        "email": "admin@acme.example",
        "position": "System Administrator",
        "role": "admin",
        "status": "active",
        "project_id": None,  # admin is not tied to one project
    },
    {
        "name": "Dana Owner",
        "email": "owner@acme.example",
        "position": "Project Owner",
        "role": "project_owner",
        "status": "active",
        "project_id": None,
    },
    {
        "name": "Lee Lead",
        "email": "lead@acme.example",
        "position": "Team Lead",
        "role": "team_lead",
        "status": "active",
        "project_id": None,
    },
    {
        "name": "Riley User",
        "email": "user@acme.example",
        "position": "Product Designer",
        "role": "user",
        "status": "active",
        "project_id": None,
    },
    {
        "name": "Casey Viewer",
        "email": "viewer@acme.example",
        "position": "Stakeholder",
        "role": "viewer",
        "status": "active",
        "project_id": None,
    },
    {
        "name": "Morgan Lead",
        "email": "morgan@acme.example",
        "position": "Senior Developer",
        "role": "team_lead",
        "status": "active",
        "project_id": None,
    },
    {
        "name": "Jordan User",
        "email": "jordan@acme.example",
        "position": "Frontend Developer",
        "role": "user",
        "status": "active",
        "project_id": None,
    },
    {
        "name": "Avery User",
        "email": "avery@acme.example",
        "position": "Backend Developer",
        "role": "user",
        "status": "active",
        "project_id": None,
    },
    {
        "name": "Quinn Viewer",
        "email": "quinn@acme.example",
        "position": "QA Analyst",
        "role": "viewer",
        "status": "active",
        "project_id": None,
    },
    {
        "name": "Sam Pending",
        "email": "sam@acme.example",
        "position": "Intern",
        "role": "user",
        "status": "pending",
        "project_id": None,
    },
]

SEED_TASKS = [
    {
        "title": "Design homepage mockups",
        "description": "Create high-fidelity Figma mockups for the new "
        "homepage, including hero, features, and pricing sections.",
        "status": "todo",
        "priority": "high",
        "assignee_name": "Riley User",
    },
    {
        "title": "Set up project repository",
        "description": "Initialize the Git repo, add CI/CD pipeline, and "
        "configure branch protection rules.",
        "status": "todo",
        "priority": "medium",
        "assignee_name": "Lee Lead",
    },
    {
        "title": "Implement authentication",
        "description": "Add login, sign-up, and password-reset flows backed "
        "by the FastAPI API.",
        "status": "todo",
        "priority": "high",
        "assignee_name": "Riley User",
    },
    {
        "title": "Write API documentation",
        "description": "Document all REST endpoints in Swagger/OpenAPI and "
        "publish the developer guide.",
        "status": "todo",
        "priority": "low",
        "assignee_name": "Lee Lead",
    },
    {
        "title": "Deploy to staging",
        "description": "Deploy the application to the staging environment and "
        "run smoke tests.",
        "status": "completed",
        "priority": "medium",
        "assignee_name": "Lee Lead",
    },
    {
        "title": "Build navigation component",
        "description": "Create a reusable top-nav bar with dropdowns, "
        "mobile hamburger menu, and active-link highlighting.",
        "status": "todo",
        "priority": "high",
        "assignee_name": "Jordan User",
    },
    {
        "title": "Design system components",
        "description": "Build the shared UI kit: buttons, inputs, cards, "
        "modals, and toast notifications.",
        "status": "in_progress",
        "priority": "high",
        "assignee_name": "Riley User",
    },
    {
        "title": "Implement task CRUD API",
        "description": "Add create, read, update, delete endpoints for tasks "
        "with pagination and filtering.",
        "status": "todo",
        "priority": "high",
        "assignee_name": "Avery User",
    },
    {
        "title": "Add task filtering and sort",
        "description": "Let users filter tasks by status, priority, assignee, "
        "and sort by due date or created date.",
        "status": "todo",
        "priority": "medium",
        "assignee_name": "Jordan User",
    },
    {
        "title": "Write unit tests",
        "description": "Add pytest coverage for auth, projects, tasks, and "
        "members service layers. Target 90%+ coverage.",
        "status": "todo",
        "priority": "medium",
        "assignee_name": "Morgan Lead",
    },
    {
        "title": "Deploy to production",
        "description": "Deploy the application to the production environment "
        "and run post-deploy smoke tests.",
        "status": "todo",
        "priority": "high",
        "assignee_name": "Lee Lead",
    },
    {
        "title": "Performance audit",
        "description": "Run Lighthouse audits, identify slow queries, and "
        "optimize the task list page load time.",
        "status": "todo",
        "priority": "low",
        "assignee_name": "Avery User",
    },
    {
        "title": "Accessibility review",
        "description": "Audit color contrast, keyboard navigation, and screen "
        "reader compatibility against WCAG 2.1 AA.",
        "status": "todo",
        "priority": "low",
        "assignee_name": "Quinn Viewer",
    },
    {
        "title": "Fix login redirect bug",
        "description": "After login, users are redirected to the wrong tab. "
        "Fix the go_router redirect logic.",
        "status": "completed",
        "priority": "high",
        "assignee_name": "Jordan User",
    },
]


def _already_seeded(db: Session) -> bool:
    """Return True if any assignee already exists (database is not fresh)."""
    return db.scalar(select(Assignee).limit(1)) is not None


def seed(db: Session) -> None:
    """Insert demo project, members, and tasks into an empty database."""
    if _already_seeded(db):
        return

    project = Project(**SEED_PROJECT, ai_opt_in=True)
    db.add(project)
    db.flush()  # get project.id without committing

    # Admin is not tied to a project (NULL project_id); everyone else joins it.
    member_map: dict[str, Assignee] = {}
    for member in SEED_MEMBERS:
        if member["role"] == "admin":
            pid = None
        else:
            pid = project.id if member.get("project_id") is None else member["project_id"]
        account = Assignee(
            name=member["name"],
            email=member["email"],
            password_hash=hash_password(SEED_PASSWORD),
            position=member["position"],
            project_id=pid,
            role=member["role"],
            status=member["status"],
        )
        db.add(account)
        db.flush()
        member_map[member["name"]] = account

    # Set the project owner to the project_owner member.
    owner = member_map["Dana Owner"]
    project.owner_id = owner.id

    today = date.today()
    for task in SEED_TASKS:
        assignee = member_map.get(task["assignee_name"])
        due = today + timedelta(days=7 + SEED_TASKS.index(task) * 3)
        db.add(
            Task(
                title=task["title"],
                description=task["description"],
                status=task["status"],
                priority=task["priority"],
                due_date=due,
                project_id=project.id,
                assignee_id=assignee.id if assignee else None,
            )
        )

    db.commit()


def seed_if_empty(db: Session) -> None:
    """Public entry point: seed the database if it is empty."""
    try:
        seed(db)
    except Exception:
        db.rollback()
        raise
