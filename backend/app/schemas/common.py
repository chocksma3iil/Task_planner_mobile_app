"""Shared schema types: normalized text and UTC serialization."""
from datetime import datetime, timezone
from typing import Annotated

from pydantic import AfterValidator, Field, PlainSerializer


def _normalize_email(value: str) -> str:
    """Trim + lowercase so uniqueness and login are case-insensitive."""
    email = value.strip().lower()
    local, at, domain = email.partition("@")
    if (
        not at
        or not local
        or not domain
        or "@" in domain
        or any(ch.isspace() for ch in email)
    ):
        raise ValueError("Enter a valid email address.")
    return email


Email = Annotated[str, Field(max_length=255), AfterValidator(_normalize_email)]


def _required_text(value: str) -> str:
    text = value.strip()
    if not text:
        raise ValueError("This field is required.")
    return text


RequiredText = Annotated[str, Field(max_length=255), AfterValidator(_required_text)]


def _optional_text(value: str | None) -> str | None:
    if value is None:
        return None
    text = value.strip()
    return text or None


OptionalText = Annotated[str | None, AfterValidator(_optional_text)]


def _position(value: str | None) -> str | None:
    text = _optional_text(value)
    if text is not None and len(text) > 127:
        raise ValueError("Position is too long (max 127 characters).")
    return text


Position = Annotated[str | None, AfterValidator(_position)]


def _as_utc_iso(value: datetime) -> str:
    """MySQL stores naive datetimes; treat them as UTC and label them."""
    aware = value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value
    return aware.astimezone(timezone.utc).isoformat()


UtcDateTime = Annotated[
    datetime, PlainSerializer(_as_utc_iso, return_type=str, when_used="json")
]
