"""AI proposal endpoints backed by the Grok (xAI) API.

Endpoints return proposals only; nothing is persisted without user approval
through the normal task endpoints. Every call falls back to a deterministic
local proposal when the Grok API is unavailable or returns invalid JSON.
"""
import json
from datetime import date

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..core.errors import NotFoundError, RuleError
from ..core.rules import require_can_mutate, require_project_access
from ..models import Assignee, Project, Task
from .access import load_task
from .grok import get_grok_client

_SYSTEM = "You are a task planning assistant. Return only valid JSON."


def weekly_plan(
    db: Session, *, actor: Assignee, project_id: int
) -> dict:
    project = _load_opted_in_project(db, actor=actor, project_id=project_id)
    pending = list(
        db.scalars(
            select(Task)
            .where(Task.project_id == project_id, Task.status != "completed")
            .order_by(Task.priority.desc(), Task.due_date, Task.id)
            .limit(10)
        ).all()
    )
    task_summaries = [
        f"- {t.title} (priority: {t.priority}, due: {t.due_date or 'none'})"
        for t in pending
    ]
    prompt = f"""You are a planning assistant for project "{project.name}".
Current pending tasks:
{chr(10).join(task_summaries) if task_summaries else "(none)"}

Propose a weekly plan as JSON with this exact structure:
{{
  "title": "Weekly Plan",
  "tasks": [
    {{"title": "...", "description": "...", "priority": "low|medium|high", "due_date": "YYYY-MM-DD|null", "status": "todo"}}
  ]
}}

Create 1-3 actionable tasks for the coming week. Prioritize high-priority and overdue items.
Return ONLY valid JSON."""
    try:
        content = _ask_grok(prompt)
        return json.loads(content)
    except Exception:
        return _fallback_weekly_plan(project, pending)


def decompose(db: Session, *, actor: Assignee, task_id: int) -> dict:
    task = load_task(db, actor=actor, task_id=task_id, write=True)
    _require_opt_in(db, project_id=task.project_id)
    prompt = f"""Break down this task into 3 subtasks:
Task: {task.title}
Description: {task.description or "(none)"}
Priority: {task.priority}

Return JSON with this exact structure:
{{
  "subtasks": [
    {{"title": "...", "description": "...", "priority": "low|medium|high"}},
    {{"title": "...", "description": "...", "priority": "low|medium|high"}},
    {{"title": "...", "description": "...", "priority": "low|medium|high"}}
  ]
}}
Return ONLY valid JSON."""
    try:
        content = _ask_grok(prompt)
        return json.loads(content)
    except Exception:
        return _fallback_decompose(task)


def briefing(db: Session, *, actor: Assignee, project_id: int) -> dict:
    project = _load_opted_in_project(db, actor=actor, project_id=project_id)
    tasks = list(
        db.scalars(select(Task).where(Task.project_id == project_id)).all()
    )
    total = len(tasks)
    done = sum(1 for t in tasks if t.status == "completed")
    pending = total - done
    overdue = sum(
        1
        for t in tasks
        if t.status != "completed" and t.due_date and t.due_date < date.today()
    )
    prompt = f"""Write a brief project status briefing for "{project.name}":
- Total tasks: {total}
- Completed: {done}
- Pending: {pending}
- Overdue: {overdue}

Provide a concise paragraph (2-3 sentences) summarizing status and recommending focus.
Return JSON: {{"briefing": "..."}}"""
    try:
        content = _ask_grok(prompt)
        return json.loads(content)
    except Exception:
        return _fallback_briefing(project, total, done, pending, overdue)


def capture(
    db: Session, *, actor: Assignee, project_id: int, text: str
) -> dict:
    _load_opted_in_project(db, actor=actor, project_id=project_id)
    prompt = f"""Convert this natural language input into a task proposal:
Input: "{text}"

Return JSON with this exact structure:
{{
  "title": "...",
  "description": "...",
  "priority": "low|medium|high",
  "due_date": "YYYY-MM-DD|null",
  "status": "todo"
}}
Extract a clear title, relevant description, appropriate priority, and due date if mentioned.
Return ONLY valid JSON."""
    try:
        content = _ask_grok(prompt)
        return json.loads(content)
    except Exception:
        return _fallback_capture(text)


def _ask_grok(prompt: str) -> str:
    """Call Grok once and return the raw assistant content."""
    client = get_grok_client()
    result = client.chat_completion(
        [
            {"role": "system", "content": _SYSTEM},
            {"role": "user", "content": prompt},
        ]
    )
    return result["choices"][0]["message"]["content"]


def _load_opted_in_project(
    db: Session, *, actor: Assignee, project_id: int
) -> Project:
    require_can_mutate(actor.role)
    project = db.get(Project, project_id)
    if project is None:
        raise NotFoundError("Project not found.")
    require_project_access(actor.role, actor.project_id, project_id)
    _require_opt_in(db, project_id=project_id)
    return project


def _require_opt_in(db: Session, *, project_id: int) -> None:
    project = db.get(Project, project_id)
    if project is None:
        raise NotFoundError("Project not found.")
    if not project.ai_opt_in:
        raise RuleError("AI is disabled for this project.")


# Fallback functions (used when Grok API is unavailable or returns invalid JSON)
def _fallback_weekly_plan(project: Project, pending: list[Task]) -> dict:
    tasks = [
        {
            "title": t.title,
            "description": t.description,
            "priority": t.priority,
            "due_date": t.due_date.isoformat() if t.due_date else None,
            "status": t.status,
        }
        for t in pending[:3]
    ]
    if not tasks:
        tasks = [{
            "title": f"Plan the week for {project.name}",
            "description": "Break the next project goal into small tasks.",
            "priority": "medium",
            "due_date": None,
            "status": "todo",
        }]
    return {"title": "Weekly Plan", "tasks": tasks}


def _fallback_decompose(task: Task) -> dict:
    return {
        "subtasks": [
            {
                "title": f"Clarify the scope of \"{task.title}\"",
                "description": "List the expected outcome and constraints.",
                "priority": "high",
            },
            {
                "title": "Do the main work",
                "description": "Focus on the smallest valuable increment.",
                "priority": "medium",
            },
            {
                "title": "Review and wrap up",
                "description": "Check the result and record what changed.",
                "priority": "low",
            },
        ]
    }


def _fallback_briefing(project: Project, total: int, done: int, pending: int, overdue: int) -> dict:
    line = (
        f"{project.name} has {total} tasks: {done} completed and "
        f"{pending} still open."
    )
    if overdue:
        line += f" {overdue} tasks are overdue."
    if pending:
        line += " Focus on the open items with the nearest due dates."
    return {"briefing": line}


def _fallback_capture(text: str) -> dict:
    title = text.strip()
    if len(title) > 255:
        title = title[:252] + "..."
    return {
        "title": title,
        "description": f"Captured from: {text.strip()}",
        "priority": "medium",
        "due_date": None,
        "status": "todo",
    }