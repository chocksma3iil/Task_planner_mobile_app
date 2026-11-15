"""In-process failed-login throttle.

The first release runs a single API process, so a small in-memory sliding
window blunts password guessing without a new dependency or a shared store.
Replace it with a shared store before running several API workers.
"""
from collections import defaultdict, deque
from threading import Lock
from time import monotonic

from .config import LOGIN_MAX_ATTEMPTS, LOGIN_WINDOW_SECONDS
from .errors import RateLimitedError


class LoginThrottle:
    """Counts failed logins per key inside a sliding window."""

    def __init__(self, *, max_attempts: int, window_seconds: float) -> None:
        self.max_attempts = max_attempts
        self.window_seconds = window_seconds
        self._failures: dict[str, deque[float]] = defaultdict(deque)
        self._lock = Lock()

    def check(self, key: str, *, now: float | None = None) -> None:
        """Raise [RateLimitedError] when [key] used all its attempts."""
        moment = monotonic() if now is None else now
        with self._lock:
            if len(self._recent(key, moment)) >= self.max_attempts:
                raise RateLimitedError()

    def fail(self, key: str, *, now: float | None = None) -> None:
        """Record one failed attempt for [key]."""
        moment = monotonic() if now is None else now
        with self._lock:
            self._recent(key, moment).append(moment)

    def reset(self, key: str) -> None:
        """Forget the failures of [key] after a successful login."""
        with self._lock:
            self._failures.pop(key, None)

    def clear(self) -> None:
        """Forget every counter (tests and maintenance)."""
        with self._lock:
            self._failures.clear()

    def _recent(self, key: str, moment: float) -> deque[float]:
        """Drop attempts older than the window and return the rest."""
        attempts = self._failures[key]
        cutoff = moment - self.window_seconds
        while attempts and attempts[0] <= cutoff:
            attempts.popleft()
        return attempts


login_throttle = LoginThrottle(
    max_attempts=LOGIN_MAX_ATTEMPTS,
    window_seconds=LOGIN_WINDOW_SECONDS,
)
