"""Business rules — server-side port of task_planner/lib/core/rules.dart.

The server is the enforcer; the Dart copy stays as a UX-side check only.
"""
from .errors import AssignmentError, RuleError

# Roles (cumulative: admin > project owner > user).
ADMIN = "admin"
PROJECT_OWNER = "project_owner"
USER = "user"
ROLES = (ADMIN, PROJECT_OWNER, USER)

# Membership states.
PENDING = "pending"
ACTIVE = "active"

# Task states and priorities.
TASK_TODO = "todo"
TASK_COMPLETED = "completed"
PRIORITIES = ("low", "medium", "high")


def can_log_in(status: str) -> bool:
    """Only active accounts may log in; pending accounts await approval."""
    return status == ACTIVE


def is_admin(role: str) -> bool:
    return role == ADMIN


def is_owner_or_admin(role: str) -> bool:
    return role in (ADMIN, PROJECT_OWNER)


def require_admin(role: str) -> None:
    if not is_admin(role):
        raise RuleError("Only an admin can do this.")


def require_owner_or_admin(role: str) -> None:
    if not is_owner_or_admin(role):
        raise RuleError("Only a project owner or admin can do this.")


def validate_task_assignment(
    task_project_id: int, assignee_id: int | None, assignee_project_id: int | None
) -> None:
    """A task is assigned to its project (None) or one same-project person."""
    if assignee_id is not None and assignee_project_id != task_project_id:
        raise AssignmentError("Assignee must belong to the task project.")


def require_project_access(
    role: str, actor_project_id: int | None, project_id: int
) -> None:
    """Admins manage any project; everyone else only their own."""
    if not is_admin(role) and actor_project_id != project_id:
        raise RuleError("You can only manage your own project tasks.")
