"""Mock AI Provider - deterministic responses for tests and demos."""

from collections.abc import AsyncIterator
from typing import List

from .base import AIProvider


class MockProvider(AIProvider):
    """Deterministic provider keyed by the caller's `operation` hint."""

    @property
    def model_name(self) -> str:
        return "mock"

    @property
    def supports_local(self) -> bool:
        return True

    async def complete(self, prompt: str, **kwargs) -> str:
        """Return a fixed shape per operation, never an ambiguous fallback."""
        operation = kwargs.get("operation")
        if operation == "weekly_plan":
            return (
                '{"title": "Weekly Plan", "tasks": ['
                '{"title": "Review the week priorities", "description": '
                '"Agree on the three most important outcomes.", "priority": '
                '"high", "due_date": null, "status": "todo"}, '
                '{"title": "Clear blocked tasks", "description": '
                '"Unblock work that is waiting on decisions.", "priority": '
                '"medium", "due_date": null, "status": "todo"}]}'
            )
        if operation == "decompose":
            return (
                '{"subtasks": ['
                '{"title": "Define the scope", "description": '
                '"List what is in and out of this task.", "priority": "medium"}, '
                '{"title": "Do the work", "description": '
                '"Complete the main deliverable.", "priority": "medium"}, '
                '{"title": "Check the result", "description": '
                '"Verify the deliverable against the scope.", "priority": "low"}]}'
            )
        if operation == "briefing":
            return (
                "The project is moving forward. A few tasks are due soon; "
                "review the overdue ones first."
            )
        if operation == "capture":
            return (
                '{"title": "Captured task", "description": "Created from '
                'natural language.", "priority": "medium", "due_date": null, '
                '"status": "todo"}'
            )

        # Fallback for direct calls in tests.
        prompt_lower = prompt.lower()
        if "priority" in prompt_lower:
            return '{"priority": "high", "confidence": 0.85}'
        return '{"response": "Mock AI response"}'

    async def stream_complete(self, prompt: str, **kwargs) -> AsyncIterator[str]:
        """Stream a mock response."""
        yield await self.complete(prompt, **kwargs)

    async def embed(self, texts: List[str]) -> List[List[float]]:
        """Return mock embeddings."""
        return [[0.1, 0.2, 0.3] for _ in texts]
