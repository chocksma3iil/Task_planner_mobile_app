"""Mock AI Provider - deterministic responses for tests and demos.

Parses the user's input text so responses reflect the actual request
(title, priority, due_date, assignee) instead of being hardcoded.
Intended for development when Ollama is unavailable; not a substitute
for a real model.
"""

import json
import re
from collections.abc import AsyncIterator
from datetime import date, timedelta
from typing import List

from .base import AIProvider


class MockProvider(AIProvider):
    """Deterministic provider keyed by the caller's `operation` hint.

    Extracts fields from the user's free-text input so every response is
    driven by what the user actually asked for.
    """

    @property
    def model_name(self) -> str:
        return "mock"

    @property
    def supports_local(self) -> bool:
        return True

    # ------------------------------------------------------------------
    # Parsing helpers (pure functions over the user's input text)
    # ------------------------------------------------------------------

    @staticmethod
    def _parse_priority(text: str) -> str:
        """Return 'high' / 'medium' / 'low' found in text, else 'medium'."""
        tl = text.lower()
        if re.search(r"\bhigh\b|\burgent\b|\basap\b", tl):
            return "high"
        if re.search(r"\blow\b|\bminor\b", tl):
            return "low"
        return "medium"

    @staticmethod
    def _parse_due_date(text: str) -> str | None:
        """Return an ISO date for 'tomorrow', 'next week', weekdays, etc."""
        tl = text.lower()
        today = date.today()
        if "tomorrow" in tl:
            return (today + timedelta(days=1)).isoformat()
        if "next week" in tl:
            return (today + timedelta(days=7)).isoformat()
        for i, name in enumerate(
            ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        ):
            if name in tl:
                target = (i - today.weekday()) % 7 or 7
                return (today + timedelta(days=target)).isoformat()
        m = re.search(r"\b(\d{4})-(\d{1,2})-(\d{1,2})\b", text)
        if m:
            return f"{m.group(1)}-{int(m.group(2)):02d}-{int(m.group(3)):02d}"
        return None

    @staticmethod
    def _parse_assignee(text: str) -> str | None:
        """Return a person's name from 'assign to X', 'for X', 'by X', 'staff X'."""
        patterns = [
            r"assign\s+to\s+([A-Za-z]+(?:\s+[A-Za-z]+)?)",
            r"for\s+([A-Za-z]+(?:\s+[A-Za-z]+)?)",
            r"by\s+([A-Za-z]+(?:\s+[A-Za-z]+)?)",
            r"staff\s+([A-Za-z]+(?:\s+[A-Za-z]+)?)",
            r"owner\s+([A-Za-z]+(?:\s+[A-Za-z]+)?)",
        ]
        for pat in patterns:
            m = re.search(pat, text, re.IGNORECASE)
            if m:
                return m.group(1).strip().title()
        return None

    @staticmethod
    def _extract_title(text: str) -> str:
        """Pull a short task title from free text."""
        # Strip common introductory phrases
        cleaned = re.sub(
            r"^(create|add|make|new|propose|suggest|please|can you|could you)\s+",
            "",
            text,
            flags=re.IGNORECASE,
        )
        # Remove trailing date/priority/assignee clauses
        cleaned = re.sub(
            r"\s+(with|for|by|due|on|at|assign\s+to|staff\s+).+$",
            "",
            cleaned,
            flags=re.IGNORECASE,
        )
        cleaned = cleaned.strip(" .,!?")
        if not cleaned:
            cleaned = "Untitled task"
        return cleaned[:80]

    # ------------------------------------------------------------------
    # Operations
    # ------------------------------------------------------------------

    async def complete(self, prompt: str, **kwargs) -> str:
        """Return a deterministic shape per operation, reflecting input text."""
        operation = kwargs.get("operation")
        prompt_lower = prompt.lower()

        if operation == "weekly_plan":
            m = re.search(r"project '([^']+)'", prompt)
            project_name = m.group(1) if m else "the project"
            # Extract keywords from existing tasks mentioned in the prompt
            task_lines = re.findall(r"^- (.+)", prompt, re.MULTILINE)
            tasks = []
            for line in task_lines[:5]:
                title = line.strip()
                if not title:
                    continue
                tasks.append(
                    {
                        "title": f"Follow up: {title}",
                        "description": f"Continue work on '{title}'.",
                        "priority": self._parse_priority(title),
                        "due_date": self._parse_due_date(title),
                        "status": "todo",
                        "assignee": self._parse_assignee(title),
                    }
                )
            if not tasks:
                tasks = [
                    {
                        "title": f"Review {project_name} priorities",
                        "description": f"Agree on the three most important outcomes for {project_name}.",
                        "priority": "high",
                        "due_date": None,
                        "status": "todo",
                        "assignee": None,
                    },
                    {
                        "title": f"Plan next week for {project_name}",
                        "description": "Outline upcoming work and assign owners.",
                        "priority": "medium",
                        "due_date": None,
                        "status": "todo",
                        "assignee": None,
                    },
                ]
            return json.dumps({"title": f"Weekly Plan for {project_name}", "tasks": tasks})

        if operation == "decompose":
            m = re.search(r"Task:\s*(.+)", prompt, re.IGNORECASE)
            task_title = m.group(1).strip() if m else "this task"
            desc_match = re.search(r"Description:\s*(.+)", prompt, re.IGNORECASE)
            task_desc = desc_match.group(1).strip() if desc_match else ""
            combined = f"{task_title} {task_desc}"
            base = self._extract_title(task_title)
            priority = self._parse_priority(combined)
            due_date = self._parse_due_date(combined)
            assignee = self._parse_assignee(combined)
            subtasks = [
                {
                    "title": f"Define the scope of {base}",
                    "description": "List what is in and out of this task.",
                    "priority": priority,
                },
                {
                    "title": f"Do the work: {base}",
                    "description": "Complete the main deliverable.",
                    "priority": priority,
                },
                {
                    "title": f"Check the result: {base}",
                    "description": "Verify the deliverable against the scope.",
                    "priority": "low",
                },
            ]
            return json.dumps({"subtasks": subtasks})

        if operation == "briefing":
            m = re.search(r"project '([^']+)'", prompt)
            project_name = m.group(1) if m else "the project"
            return (
                f"{project_name} is moving forward. A few tasks are due soon; "
                f"review the overdue ones first."
            )

        if operation == "capture":
            # Extract only the user's input from "User input: '...'" in the prompt.
            m = re.search(r"User input:\s*'([^']+)'", prompt)
            user_text = m.group(1) if m else prompt
            title = self._extract_title(user_text)
            priority = self._parse_priority(user_text)
            due_date = self._parse_due_date(user_text)
            assignee = self._parse_assignee(user_text)
            description = f"Created from natural language: {user_text}"
            return json.dumps(
                {
                    "title": title,
                    "description": description,
                    "priority": priority,
                    "due_date": due_date,
                    "status": "todo",
                    "assignee": assignee,
                }
            )

        # Fallback for direct calls in tests.
        if "priority" in prompt_lower:
            return '{"priority": "high", "confidence": 0.85}'
        return '{"response": "Mock AI response"}'

    async def stream_complete(self, prompt: str, **kwargs) -> AsyncIterator[str]:
        """Stream a mock response."""
        yield await self.complete(prompt, **kwargs)

    async def embed(self, texts: List[str]) -> List[List[float]]:
        """Return mock embeddings."""
        return [[0.1, 0.2, 0.3] for _ in texts]
