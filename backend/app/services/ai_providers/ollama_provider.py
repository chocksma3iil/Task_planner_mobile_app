"""Ollama AI Provider - Local, privacy-first implementation.

Uses only the standard library (`urllib`) so no extra pip dependency is
required (PyPI is unreachable from the api container).
"""

import asyncio
import json
import time
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
        # Fast failure when Ollama itself is down: do not wait the full
        # generation timeout just to discover the server is unreachable.
        self._connect_timeout = 8
        self._max_retries = 3
        self._retry_delay = 2  # seconds, exponential backoff between retries

    @property
    def model_name(self) -> str:
        return f"ollama:{self.model}"

    @property
    def supports_local(self) -> bool:
        return True

    def _health_check(self) -> None:
        """Fail fast if Ollama is not reachable or the model is missing."""
        req = urllib.request.Request(
            f"{self.base_url}/api/tags",
            headers={"Content-Type": "application/json"},
            method="GET",
        )
        try:
            with urllib.request.urlopen(req, timeout=self._connect_timeout) as resp:
                body = resp.read()
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                raise AIProviderError(
                    "Ollama is reachable but returned 404 for /api/tags. "
                    "Check the Ollama log and that the server is healthy."
                ) from exc
            raise AIProviderError(
                f"Ollama responded with HTTP {exc.code}. Check the Ollama log."
            ) from exc
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            raise AIProviderError(
                "The local AI model is not reachable. "
                "Start Ollama and check AI_BASE_URL."
            ) from exc
        try:
            tags = json.loads(body)
        except json.JSONDecodeError as exc:
            raise AIProviderError(
                "Ollama returned an invalid /api/tags response."
            ) from exc
        available = {
            m.get("name")
            for m in tags.get("models", [])
            if isinstance(m, dict) and m.get("name")
        }
        if self.model not in available and f"{self.model}:latest" not in available:
            raise AIProviderError(
                f"The AI model '{self.model}' is not installed. "
                "Run: ollama pull " + self.model
            )

    def _post_json(
        self, path: str, payload: dict, timeout: int | None = None
    ) -> dict:
        """Blocking POST with JSON body; returns parsed JSON.

        Retries transient failures (connection reset, timeout) with backoff so
        a briefly-overloaded Ollama does not fail the whole request. Provider
        failures become [AIProviderError] so the API can answer with a
        readable 503 instead of a bare 500 or a long hang.
        """
        data = json.dumps(payload).encode("utf-8")
        last_error: Exception | None = None
        for attempt in range(1, self._max_retries + 1):
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
                try:
                    return json.loads(body)
                except json.JSONDecodeError as exc:
                    raise AIProviderError(
                        "The AI model returned an invalid response."
                    ) from exc
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
                last_error = exc
                if attempt == self._max_retries:
                    raise AIProviderError(
                        "The local AI model is not reachable. "
                        "Start Ollama and check AI_BASE_URL."
                    ) from exc
                time.sleep(self._retry_delay * attempt)
        raise AIProviderError(
            "The local AI model is not reachable. "
            "Start Ollama and check AI_BASE_URL."
        ) from last_error

    async def complete(self, prompt: str, **kwargs) -> str:
        """Generate a completion using Ollama (non-streaming).

        `json_mode=False` is used for free-text answers (briefings); every
        structured operation enables Ollama's JSON mode instead of relying on
        the prompt alone.

        A fast health check runs first so a dead Ollama returns a 503 in
        seconds instead of burning the full generation timeout.
        """
        await asyncio.to_thread(self._health_check)

        payload = {
            "model": self.model,
            "prompt": prompt,
            "stream": False,
            "options": {"temperature": 0.3, "num_predict": 2000},
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
