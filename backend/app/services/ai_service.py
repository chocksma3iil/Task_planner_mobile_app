"""AI layer (v2.0): planning agent over local Ollama + mock provider.

All AI methods return *proposals only*. Nothing is written to the database
by this layer: a human must approve before any task/subtask is created.
"""

import json
from datetime import date, timedelta
from typing import Any

from ..core.config import AI_BASE_URL, AI_MODEL, AI_PROVIDER, AI_TIMEOUT_SECONDS
from ..core.errors import AIServiceUnavailableError, ForbiddenError, NotFoundError
from ..models import Assignee, Project, Task
from .ai_providers.base import AIProvider, AIProviderError
from .ai_providers.mock_provider import MockProvider
from .ai_providers.ollama_provider import OllamaProvider

_PRIORITIES = {"low", "medium", "high"}
_STATUSES = {"todo", "in_progress", "completed"}


_PROVIDERS: dict[str, type[AIProvider]] = {
    "ollama": OllamaProvider,
    "mock": MockProvider,
}


def _provider() -> AIProvider:
    """Instantiate the configured AI provider."""
    provider_cls = _PROVIDERS.get(AI_PROVIDER)
    if provider_cls is None:
        raise ForbiddenError(f"Unknown AI provider: {AI_PROVIDER}")
    if provider_cls is OllamaProvider:
        return OllamaProvider(
            base_url=AI_BASE_URL,
            model=AI_MODEL,
            timeout=AI_TIMEOUT_SECONDS,
        )
    return provider_cls()


def require_ai_consent(project: Project) -> None:
    """Raise 403 if the project has not opted into AI."""
    if not project.ai_opt_in:
        raise ForbiddenError(
            "AI is disabled for this project. Enable it in project settings."
        )


def _clean_text(value: Any, *, limit: int = 500) -> str:
    """Coerce a model field to a trimmed string of bounded length."""
    if value is None:
        return ""
    return str(value).strip()[:limit]


def _clean_priority(value: Any) -> str:
    priority = _clean_text(value, limit=20).lower()
    return priority if priority in _PRIORITIES else "medium"


def _clean_status(value: Any) -> str:
    status = _clean_text(value, limit=20).lower()
    return status if status in _STATUSES else "todo"


def _clean_due_date(value: Any) -> str | None:
    """Keep only real ISO dates; the model sometimes returns prose or ''."""
    text = _clean_text(value, limit=10)
    if not text:
        return None
    try:
        date.fromisoformat(text)
    except ValueError:
        return None
    return text


def _extract_json(raw: str) -> dict[str, Any] | None:
    """Parse a JSON object even when the model wraps it in prose or fences."""
    text = raw.strip()
    if text.startswith("```"):
        # Drop the opening fence (``` or ```json) and the closing fence.
        text = text.split("\n", 1)[1] if "\n" in text else ""
        if text.rstrip().endswith("```"):
            text = text.rstrip()[:-3]
    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end <= start:
        return None
    try:
        data = json.loads(text[start : end + 1])
    except json.JSONDecodeError:
        return None
    return data if isinstance(data, dict) else None


def _task_summary(task: Task) -> dict[str, Any]:
    """Safe subset of a task sent to the AI (no secrets, no PII beyond title)."""
    return {
        "id": task.id,
        "title": task.title,
        "description": task.description,
        "priority": task.priority,
        "due_date": str(task.due_date) if task.due_date else None,
        "status": task.status,
    }


class AIService:
    """Orchestrates AI proposals; never writes to the database."""

    def __init__(self, db, actor: Assignee) -> None:
        self.db = db
        self.actor = actor
        self.provider = _provider()

    async def _complete(
        self,
        prompt: str,
        *,
        operation: str,
        json_mode: bool = True,
    ) -> str:
        """Call the provider and turn provider failures into a readable 503."""
        try:
            return await self.provider.complete(
                prompt,
                operation=operation,
                json_mode=json_mode,
            )
        except AIProviderError as exc:
            raise AIServiceUnavailableError(str(exc)) from exc

    async def propose_weekly_plan(self, project_id: int) -> dict[str, Any]:
        """Propose a weekly plan for a project (read-only proposal)."""
        project = self.db.get(Project, project_id)
        if project is None:
            raise NotFoundError("Project not found.")
        require_ai_consent(project)

        tasks = list(
            self.db.query(Task)
            .filter(Task.project_id == project_id)
            .order_by(Task.created_at.desc())
            .limit(100)
            .all()
        )
        plan = await self._complete(
            self._build_weekly_plan_prompt(project, tasks),
            operation="weekly_plan",
        )
        return self._parse_plan(plan)

    async def decompose(self, task_id: int) -> dict[str, Any]:
        """Propose subtasks for a task (read-only proposal)."""
        task = self.db.get(Task, task_id)
        if task is None:
            raise NotFoundError("Task not found.")
        project = self.db.get(Project, task.project_id)
        if project is None:
            raise NotFoundError("Project not found.")
        require_ai_consent(project)

        result = await self._complete(
            self._build_decompose_prompt(task),
            operation="decompose",
        )
        return self._parse_decompose(result)

    async def briefing(self, project_id: int) -> dict[str, Any]:
        """Propose a natural-language summary of a project (read-only)."""
        project = self.db.get(Project, project_id)
        if project is None:
            raise NotFoundError("Project not found.")
        require_ai_consent(project)

        tasks = list(
            self.db.query(Task).filter(Task.project_id == project_id).all()
        )
        summary = await self._complete(
            self._build_briefing_prompt(project, tasks),
            operation="briefing",
            json_mode=False,
        )
        text = summary.strip()
        if not text:
            raise AIServiceUnavailableError(
                "The AI did not return a briefing. Try again."
            )
        return {"briefing": text}

    async def capture(self, project_id: int, text: str) -> dict[str, Any]:
        """Propose a task from natural-language input (read-only)."""
        project = self.db.get(Project, project_id)
        if project is None:
            raise NotFoundError("Project not found.")
        require_ai_consent(project)

        result = await self._complete(
            self._build_capture_prompt(text),
            operation="capture",
        )
        return self._parse_capture(result)

    # --- Prompt builders (only title/description/priority/due_date/status) ---

    def _build_weekly_plan_prompt(self, project: Project, tasks: list[Task]) -> str:
        today = date.today()
        horizon = today + timedelta(days=7)
        task_list = "\n".join(
            f"- {t.title} (priority={t.priority}, due={t.due_date}, status={t.status})"
            for t in tasks
        ) or "(no tasks yet)"
        return (
            f"You are a planning assistant for project '{project.name}'.\n"
            f"Today is {today.isoformat()}.\n"
            f"Existing tasks:\n{task_list}\n\n"
            "Propose 3 to 5 NEW tasks for the coming week ("
            f"{today.isoformat()} to {horizon.isoformat()}).\n"
            "Do not repeat titles that already exist. Each task must be "
            "concrete and independently actionable.\n"
            "Return ONLY a JSON object with:\n"
            '{"title": "Weekly Plan", "tasks": [{"title": "...", '
            '"description": "...", "priority": "low|medium|high", '
            '"due_date": "YYYY-MM-DD or null", '
            '"status": "todo|in_progress|completed"}]}\n'
            "Do not include explanations outside the JSON."
        )

    def _build_decompose_prompt(self, task: Task) -> str:
        return (
            f"Task: {task.title}\n"
            f"Description: {task.description or ''}\n"
            f"Priority: {task.priority}\n"
            f"Due date: {task.due_date or 'none'}\n\n"
            "Break this task into 3 to 6 concrete subtasks. Return ONLY a JSON "
            'object: {"subtasks": [{"title": "...", "description": "...", '
            '"priority": "low|medium|high"}]}\n'
            "Do not include explanations outside the JSON."
        )

    def _build_briefing_prompt(self, project: Project, tasks: list[Task]) -> str:
        today = date.today()
        total = len(tasks)
        completed = sum(1 for t in tasks if t.status == "completed")
        overdue = sum(
            1
            for t in tasks
            if t.status != "completed"
            and t.due_date
            and date.fromisoformat(str(t.due_date)) < today
        )
        due_soon = sum(
            1
            for t in tasks
            if t.status != "completed"
            and t.due_date
            and today <= date.fromisoformat(str(t.due_date)) <= today + timedelta(days=7)
        )
        return (
            f"Project '{project.name}' has {total} tasks: {completed} completed, "
            f"{overdue} overdue, {due_soon} due within 7 days. "
            f"Today is {today.isoformat()}.\n"
            "Write a short briefing (2 to 3 sentences) in English for the "
            "project's team. Be specific about what needs attention. "
            "Return ONLY the text, no JSON, no explanations."
        )

    def _build_capture_prompt(self, text: str) -> str:
        return (
            f"Today is {date.today().isoformat()}.\n"
            f"User input: '{text}'\n\n"
            "Extract a single task proposal. Return ONLY a JSON object:\n"
            '{"title": "...", "description": "...", "priority": "low|medium|high", '
            '"due_date": "YYYY-MM-DD or null", "status": "todo"}\n'
            "Do not include explanations outside the JSON."
        )

    # --- Parsers (validate shape, never write) ---

    def _parse_plan(self, raw: str) -> dict[str, Any]:
        data = _extract_json(raw)
        if data is None:
            return {"title": "Weekly Plan", "tasks": []}

        tasks: list[dict[str, Any]] = []
        for item in data.get("tasks", []) if isinstance(data.get("tasks"), list) else []:
            if not isinstance(item, dict):
                continue
            title = _clean_text(item.get("title"), limit=255)
            if not title:
                continue
            tasks.append(
                {
                    "title": title,
                    "description": _clean_text(item.get("description")) or None,
                    "priority": _clean_priority(item.get("priority")),
                    "due_date": _clean_due_date(item.get("due_date")),
                    "status": _clean_status(item.get("status")),
                }
            )
            if len(tasks) == 7:
                break
        return {"title": _clean_text(data.get("title")) or "Weekly Plan", "tasks": tasks}

    def _parse_decompose(self, raw: str) -> dict[str, Any]:
        data = _extract_json(raw)
        if data is None:
            return {"subtasks": []}

        subtasks: list[dict[str, Any]] = []
        items = data.get("subtasks")
        for item in items if isinstance(items, list) else []:
            if not isinstance(item, dict):
                continue
            title = _clean_text(item.get("title"), limit=255)
            if not title:
                continue
            subtasks.append(
                {
                    "title": title,
                    "description": _clean_text(item.get("description")) or None,
                    "priority": _clean_priority(item.get("priority")),
                }
            )
            if len(subtasks) == 8:
                break
        return {"subtasks": subtasks}

    def _parse_capture(self, raw: str) -> dict[str, Any]:
        data = _extract_json(raw)
        if data is None:
            raise AIServiceUnavailableError(
                "The AI could not turn that into a task. Try rephrasing."
            )
        title = _clean_text(data.get("title"), limit=255)
        if not title:
            raise AIServiceUnavailableError(
                "The AI could not turn that into a task. Try rephrasing."
            )
        return {
            "title": title,
            "description": _clean_text(data.get("description")) or None,
            "priority": _clean_priority(data.get("priority")),
            "due_date": _clean_due_date(data.get("due_date")),
            "status": _clean_status(data.get("status")),
        }
