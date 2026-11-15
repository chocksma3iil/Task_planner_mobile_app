"""SMTP notification tests: configuration, sending, and failure isolation."""
from email.message import EmailMessage

import pytest

from app.services import email_service


class FakeSMTP:
    """Minimal smtplib.SMTP double recording the session."""

    instances = []

    def __init__(self, host, port, timeout=10):
        self.host = host
        self.port = port
        self.timeout = timeout
        self.started_tls = False
        self.logged_in = None
        self.message = None
        self.closed = False
        FakeSMTP.instances.append(self)

    def __enter__(self):
        return self

    def __exit__(self, *exc_info):
        self.closed = True
        return False

    def starttls(self):
        self.started_tls = True

    def login(self, user, password):
        self.logged_in = (user, password)

    def send_message(self, message: EmailMessage):
        self.message = message


class FailingSMTP(FakeSMTP):
    def send_message(self, message):
        raise OSError("SMTP is down")


@pytest.fixture
def configured(monkeypatch):
    """Configure SMTP and replace the real client with a recording double."""
    FakeSMTP.instances.clear()
    monkeypatch.setattr(email_service, "SMTP_HOST", "smtp.test")
    monkeypatch.setattr(email_service, "SMTP_PORT", 2525)
    monkeypatch.setattr(email_service, "SMTP_USER", "mailer")
    monkeypatch.setattr(email_service, "SMTP_PASS", "secret")
    monkeypatch.setattr(email_service, "SMTP_FROM", "planner@test")
    monkeypatch.setattr(email_service, "SMTP_TLS", True)
    monkeypatch.setattr(email_service.smtplib, "SMTP", FakeSMTP)


def test_unconfigured_smtp_is_a_silent_noop(monkeypatch):
    monkeypatch.setattr(email_service, "SMTP_HOST", "")
    monkeypatch.setattr(email_service, "SMTP_USER", "")
    monkeypatch.setattr(email_service, "SMTP_PASS", "")
    monkeypatch.setattr(email_service, "SMTP_FROM", "")

    assert email_service.is_configured() is False
    # Neither call reaches the network nor raises.
    assert email_service.send("bob@test", "Subject", "Body") is None
    assert email_service.send_async("bob@test", "Subject", "Body") is None


def test_send_uses_tls_and_credentials(configured):
    email_service.send("bob@test", "Task assigned", "Hello Bob")

    assert len(FakeSMTP.instances) == 1
    client = FakeSMTP.instances[0]
    assert (client.host, client.port) == ("smtp.test", 2525)
    assert client.started_tls is True
    assert client.logged_in == ("mailer", "secret")
    assert client.closed is True
    assert client.message["To"] == "bob@test"
    assert client.message["From"] == "planner@test"
    assert client.message["Subject"] == "Task assigned"
    assert "Hello Bob" in client.message.get_content()


def test_send_async_returns_a_completed_future(configured):
    future = email_service.send_async("bob@test", "Queued", "Body")

    assert future is not None
    future.result(timeout=5)
    assert len(FakeSMTP.instances) == 1
    assert FakeSMTP.instances[0].message["Subject"] == "Queued"


def test_smtp_failure_is_isolated(configured, monkeypatch):
    monkeypatch.setattr(email_service.smtplib, "SMTP", FailingSMTP)

    # A broken SMTP server must never raise into the request path.
    assert email_service.send("bob@test", "Subject", "Body") is None
    future = email_service.send_async("bob@test", "Subject", "Body")
    assert future is not None
    assert future.result(timeout=5) is None
