"""Ollama AI Provider - Local, privacy-first implementation.

Uses only the standard library (`urllib`) so no extra pip dependency is
required (PyPI is unreachable from the api container).
"""

import asyncio
import json
import urllib.error
import urllib.request
from collections.abc import AsyncIterator
from typing import List

from .base import AIProvider, AIProviderError


class OllamaProvider(AIProvider):
    """Local Ollama provider - runs on local infrastructure, privacy-first."""

    def __init__(
        self,
        base_url: str = "http://localhost:11434",
        model: str = "llama3.2:latest",
        timeout: int = 180,
    ):
        self.base_url = base_url.rstrip("/")
        self.model = model
        self.timeout = timeout

    @property
    def model_name(self) -> str:
        return f"ollama:{self.model}"

    @property
    def supports_local(self) -> bool:
        return True

    def _post_json(
        self, path: str, payload: dict, timeout: int | None = None
    ) -> dict:
        """Blocking POST with JSON body; returns parsed JSON.

        Provider failures become [AIProviderError] so the API can answer with a
        readable 503 instead of a bare 500.
        """
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            f"{self.base_url}{path}",
            data=data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(
                req, timeout=timeout or self.timeout
            ) as resp:
                body = resp.read()
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", "replace").strip()
            if exc.code == 404:
                raise AIProviderError(
                    f"The AI model '{self.model}' is not installed. "
                    "Run: ollama pull " + self.model
                ) from exc
            lowered = detail.lower()
            if "out of memory" in lowered or "failed to allocate" in lowered:
                raise AIProviderError(
                    "The local AI model ran out of memory. Close other apps "
                    "and retry, or configure a smaller model in AI_MODEL."
                ) from exc
            raise AIProviderError(
                "The AI model failed to start. Check the Ollama log and that "
                "it can run on this machine."
            ) from exc
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            raise AIProviderError(
                "The local AI model is not reachable. "
                "Start Ollama and check AI_BASE_URL."
            ) from exc
        try:
            return json.loads(body)
        except json.JSONDecodeError as exc:
            raise AIProviderError(
                "The AI model returned an invalid response."
            ) from exc

    async def complete(self, prompt: str, **kwargs) -> str:
        """Generate a completion using Ollama (non-streaming).

        `json_mode=False` is used for free-text answers (briefings); every
        structured operation enables Ollama's JSON mode instead of relying on
        the prompt alone.
        """
        payload = {
            "model": self.model,
            "prompt": prompt,
            "stream": False,
            "options": {"temperature": 0.3, "num_predict": 700},
        }
        if kwargs.get("json_mode", True):
            payload["format"] = "json"
        data = await asyncio.to_thread(self._post_json, "/api/generate", payload)
        return str(data.get("response", ""))

    async def stream_complete(self, prompt: str, **kwargs) -> AsyncIterator[str]:
        """Yield one completion (kept for the provider contract)."""
        yield await self.complete(prompt, **kwargs)

    async def embed(self, texts: List[str]) -> List[List[float]]:
        """Ollama embeddings are not used by this app."""
        return []
