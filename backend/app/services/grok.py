"""Grok (xAI) API client for AI proposals.

Sync client: the FastAPI endpoints run in a threadpool, so plain blocking
httpx calls are the simplest correct choice here.
"""
import json
from typing import Any

import httpx

from ..core.config import GROK_API_BASE, GROK_API_KEY, GROK_MODEL
from ..core.errors import RuleError


class GrokClient:
    def __init__(self) -> None:
        self.api_key = GROK_API_KEY
        self.base_url = GROK_API_BASE
        self.model = GROK_MODEL
        self._client: httpx.Client | None = None

    def _get_client(self) -> httpx.Client:
        if self._client is None:
            self._client = httpx.Client(
                base_url=self.base_url,
                headers={"Authorization": f"Bearer {self.api_key}"},
                timeout=30.0,
            )
        return self._client

    def close(self) -> None:
        if self._client is not None:
            self._client.close()
            self._client = None

    def chat_completion(
        self,
        messages: list[dict[str, str]],
        model: str | None = None,
        temperature: float = 0.3,
        max_tokens: int = 1000,
    ) -> dict[str, Any]:
        """Call the Groq chat completion endpoint."""
        if not self.api_key:
            raise RuleError(
                "GROK_API_KEY not configured. Set GROK_API_KEY in backend/.env"
            )
        client = self._get_client()
        payload = {
            "model": model or self.model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
        }
        response = client.post("/chat/completions", json=payload)
        response.raise_for_status()
        return response.json()

    def extract_json(self, messages: list[dict[str, str]]) -> dict[str, Any]:
        """Call Grok and extract JSON from the response content."""
        result = self.chat_completion(messages)
        content = result["choices"][0]["message"]["content"]
        try:
            return json.loads(content)
        except json.JSONDecodeError:
            return {"raw": content}


_grok_client: GrokClient | None = None


def get_grok_client() -> GrokClient:
    global _grok_client
    if _grok_client is None:
        _grok_client = GrokClient()
    return _grok_client