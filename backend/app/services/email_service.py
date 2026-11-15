"""SMTP email sending for notifications.

Uses only the Python standard library (`smtplib`, `email.message`) so no new
dependency is required. Emails are silently skipped when SMTP is not
configured (local development without an SMTP server).
"""
import logging
import smtplib
from concurrent.futures import Future, ThreadPoolExecutor
from email.message import EmailMessage

from ..core.config import (
    SMTP_FROM,
    SMTP_HOST,
    SMTP_PASS,
    SMTP_PORT,
    SMTP_TLS,
    SMTP_USER,
)

log = logging.getLogger("task_planner.email")

# One small pool keeps SMTP latency off the request thread without adding a
# dependency or a background worker to the first release.
_executor = ThreadPoolExecutor(max_workers=2, thread_name_prefix="email")


def is_configured() -> bool:
    """True when SMTP host and credentials are set."""
    return bool(SMTP_HOST and SMTP_USER and SMTP_PASS and SMTP_FROM)


def send(to: str, subject: str, body: str) -> None:
    """Send one email. No-op when SMTP is not configured."""
    if not is_configured():
        log.warning(
            "SMTP is not configured; no email sent to %s (%s). "
            "Set SMTP_HOST, SMTP_USER, SMTP_PASS and SMTP_FROM.",
            to,
            subject,
        )
        return
    msg = EmailMessage()
    msg["From"] = SMTP_FROM
    msg["To"] = to
    msg["Subject"] = subject
    msg.set_content(body)
    try:
        # Port 465 uses implicit TLS; 587 uses STARTTLS.
        if SMTP_PORT == 465:
            server = smtplib.SMTP_SSL(SMTP_HOST, SMTP_PORT, timeout=10)
        else:
            server = smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=10)
        with server:
            if SMTP_TLS and SMTP_PORT != 465:
                server.starttls()
            if SMTP_USER and SMTP_PASS:
                server.login(SMTP_USER, SMTP_PASS)
            server.send_message(msg)
    except Exception:  # noqa: BLE001 — email failure must not break the request
        log.exception("Failed to send email to %s: %s", to, subject)


def send_async(to: str, subject: str, body: str) -> "Future[None] | None":
    """Queue an email on the SMTP pool; the request never waits on it.

    Returns the future for tests/callers that want to observe completion, or
    None when SMTP is not configured (local development and CI).
    """
    if not is_configured():
        return None
    return _executor.submit(send, to, subject, body)
