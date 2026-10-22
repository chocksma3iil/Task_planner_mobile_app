"""Time helpers.

MySQL DATETIME has no timezone, so the server stores naive UTC and the API
serializes it with an explicit `+00:00` offset.
"""
from datetime import datetime, timezone


def utc_now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)
