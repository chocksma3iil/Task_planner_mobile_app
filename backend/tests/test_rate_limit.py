"""Failed-login throttle: window pruning, reset, and isolation per key."""
import pytest

from app.core.errors import RateLimitedError
from app.core.rate_limit import LoginThrottle


def test_attempts_are_counted_inside_the_window():
    throttle = LoginThrottle(max_attempts=2, window_seconds=60)
    throttle.check("k", now=0)
    throttle.fail("k", now=0)
    throttle.fail("k", now=1)

    with pytest.raises(RateLimitedError):
        throttle.check("k", now=2)

    # Once the window has passed, the key is allowed again.
    throttle.check("k", now=61)
    # Another key is independent.
    throttle.check("other", now=2)


def test_success_resets_the_counters():
    throttle = LoginThrottle(max_attempts=1, window_seconds=60)
    throttle.fail("k", now=0)

    with pytest.raises(RateLimitedError):
        throttle.check("k", now=0)

    throttle.reset("k")
    throttle.check("k", now=0)


def test_clear_forgets_every_key():
    throttle = LoginThrottle(max_attempts=1, window_seconds=60)
    throttle.fail("a", now=0)
    throttle.fail("b", now=0)

    throttle.clear()

    throttle.check("a", now=0)
    throttle.check("b", now=0)
