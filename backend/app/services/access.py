"""Shared task-access lookup for comments, subtasks, bulk actions, and AI."""
from sqlalchemy.orm import Session

from ..core.errors import NotFoundError
from ..core.rules import require_can_mutate, require_project_access
from ..models import Assignee, Task


def load_task(
    db: Session, *, actor: Assignee, task_id: int, write: bool = False
) -> Task:
    """Load a task after enforcing project scoping (and write access)."""
    task = db.get(Task, task_id)
    if task is None:
        raise NotFoundError("Task not found.")
    require_project_access(actor.role, actor.project_id, task.project_id)
    if write:
        require_can_mutate(actor.role)
    return task
