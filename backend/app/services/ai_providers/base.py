"""AI Provider abstraction for the Task Planner backend."""

from abc import ABC, abstractmethod
from collections.abc import AsyncIterator
from typing import List


class AIProviderError(Exception):
    """Provider-side failure (model unreachable, timeout, invalid payload)."""


class AIProvider(ABC):
    """Abstract base class for AI providers."""
    
    @abstractmethod
    async def complete(self, prompt: str, **kwargs) -> str:
        """Generate a completion for the given prompt."""
        raise NotImplementedError
    
    @abstractmethod
    async def stream_complete(self, prompt: str, **kwargs) -> AsyncIterator[str]:
        """Stream a completion for the given prompt."""
        raise NotImplementedError
    
    @abstractmethod
    async def embed(self, texts: List[str]) -> List[List[float]]:
        """Generate embeddings for the given texts."""
        raise NotImplementedError
    
    @property
    @abstractmethod
    def model_name(self) -> str:
        """Return the model name used by this provider."""
        raise NotImplementedError
    
    @property
    @abstractmethod
    def supports_local(self) -> bool:
        """Whether this provider can run locally (privacy-first)."""
        raise NotImplementedError