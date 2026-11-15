"""AI Agent Orchestration for the Task Planner backend.

Thin wrapper over `AIService`. All methods return proposals only — the
caller (UI) must obtain human approval before persisting anything.
"""

from typing import Any

from ..core.errors import NotFoundError
from ..models import Project, Task
from .ai_service import AIService


class PlanningAgent:
    """Proposes plans and decompositions; never writes to the database."""

    def __init__(self, db, actor) -> None:
        self.db = db
        self.actor = actor
        self.service = AIService(db, actor)

    async def propose_weekly_plan(self, project_id: int) -> dict[str, Any]:
        """Propose a weekly plan for a project (read-only proposal)."""
        project = self.db.get(Project, project_id)
        if project is None:
            raise NotFoundError("Project not found.")
        return await self.service.propose_weekly_plan(project_id)

    async def decompose(self, task_id: int) -> dict[str, Any]:
        """Propose subtasks for a task (read-only proposal)."""
        task = self.db.get(Task, task_id)
        if task is None:
            raise NotFoundError("Task not found.")
        return await self.service.decompose(task_id)

    async def briefing(self, project_id: int) -> dict[str, Any]:
        """Propose a natural-language briefing for a project (read-only)."""
        project = self.db.get(Project, project_id)
        if project is None:
            raise NotFoundError("Project not found.")
        return await self.service.briefing(project_id)

    async def capture(self, project_id: int, text: str) -> dict[str, Any]:
        """Propose a task from natural language (read-only proposal)."""
        project = self.db.get(Project, project_id)
        if project is None:
            raise NotFoundError("Project not found.")
        return await self.service.capture(project_id, text)
