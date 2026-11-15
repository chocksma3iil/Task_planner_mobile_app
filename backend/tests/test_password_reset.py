"""Password reset (A10) and session revocation (A11).

Covers the generic anti-enumeration answer, single-use/expiring codes, the
new-password login path, and the fact that tokens issued before a reset stop
working immediately.
"""
import re
from datetime import timedelta

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.database import engine
from app.core.time import utc_now
from app.models import Assignee, PasswordResetToken
from helpers import bootstrap, login_token, sign_up

GENERIC_MESSAGE = "If the account exists, a reset code has been sent."


@pytest.fixture
def mailbox(monkeypatch):
    """Capture queued emails instead of talking to SMTP."""
    sent = []

    def capture(to, subject, body):
        sent.append({"to": to, "subject": subject, "body": body})

    monkeypatch.setattr(
        "app.services.auth.email_service.send_async",
        capture,
    )
    return sent


def request_reset(client, email):
    return client.post("/api/v1/auth/forgot-password", json={"email": email})


def reset_password(client, email, code, new_password="new-password-123"):
    return client.post(
        "/api/v1/auth/reset-password",
        json={"email": email, "code": code, "new_password": new_password},
    )


def _code_from(mail):
    match = re.search(r"password:\n\n(\S+)", mail["body"])
    assert match, mail["body"]
    return match.group(1)


def _reset_rows(email):
    with Session(engine) as session:
        account = session.scalar(select(Assignee).where(Assignee.email == email))
        assert account is not None
        return list(
            session.scalars(
                select(PasswordResetToken).where(
                    PasswordResetToken.account_id == account.id
                )
            )
        )


def test_forgot_password_is_generic_for_unknown_email(client, mailbox):
    response = request_reset(client, "nobody@example.com")

    assert response.status_code == 202
    assert response.json() == {"message": GENERIC_MESSAGE}
    assert mailbox == []


def test_forgot_password_answers_the_same_way_for_a_real_account(
    client, mailbox
):
    bootstrap(client)

    response = request_reset(client, "root@example.com")

    assert response.status_code == 202
    assert response.json() == {"message": GENERIC_MESSAGE}
    assert len(mailbox) == 1
    assert mailbox[0]["to"] == "root@example.com"


def test_reset_code_sets_a_new_password_and_is_single_use(client, mailbox):
    bootstrap(client)
    request_reset(client, "root@example.com")
    code = _code_from(mailbox[0])

    response = reset_password(client, "root@example.com", code)

    assert response.status_code == 200, response.text
    assert response.json() == {
        "message": "Password updated. Log in with the new password."
    }
    # The old password no longer works; the new one does.
    assert (
        client.post(
            "/api/v1/auth/login",
            json={"email": "root@example.com", "password": "password123"},
        ).status_code
        == 401
    )
    assert (
        client.post(
            "/api/v1/auth/login",
            json={"email": "root@example.com", "password": "new-password-123"},
        ).status_code
        == 200
    )
    # The code is consumed: a second use is refused.
    assert reset_password(client, "root@example.com", code).status_code == 400


def test_only_the_newest_code_works(client, mailbox):
    bootstrap(client)
    request_reset(client, "root@example.com")
    first = _code_from(mailbox[0])
    request_reset(client, "root@example.com")
    second = _code_from(mailbox[1])

    assert reset_password(client, "root@example.com", first).status_code == 400
    assert reset_password(client, "root@example.com", second).status_code == 200


def test_wrong_and_expired_codes_are_refused(client, mailbox):
    bootstrap(client)
    # Wrong code: refused, the password is untouched.
    assert reset_password(client, "root@example.com", "not-the-code").status_code == 400
    assert login_token(client, "root@example.com") != ""

    # Expired code: refused.
    request_reset(client, "root@example.com")
    code = _code_from(mailbox[0])
    with Session(engine) as session:
        row = session.scalars(select(PasswordResetToken)).one()
        row.expires_at = utc_now() - timedelta(minutes=1)
        session.commit()

    response = reset_password(client, "root@example.com", code)
    assert response.status_code == 400
    assert response.json()["detail"] == "Invalid or expired reset code."
    assert login_token(client, "root@example.com") != ""


def test_reset_revokes_every_previous_token(client, mailbox):
    bootstrap(client)
    old_token = login_token(client, "root@example.com")
    headers = {"Authorization": f"Bearer {old_token}"}
    assert client.get("/api/v1/auth/me", headers=headers).status_code == 200

    request_reset(client, "root@example.com")
    code = _code_from(mailbox[0])
    assert reset_password(client, "root@example.com", code).status_code == 200

    # The token issued before the reset is rejected (A11).
    response = client.get("/api/v1/auth/me", headers=headers)
    assert response.status_code == 401
    assert response.json()["detail"] == "Session is no longer valid."
    # A fresh login issues a working token again.
    new_token = login_token(client, "root@example.com", password="new-password-123")
    assert (
        client.get(
            "/api/v1/auth/me", headers={"Authorization": f"Bearer {new_token}"}
        ).status_code
        == 200
    )


def test_pending_accounts_get_no_code(client, mailbox):
    _, _, project = bootstrap(client)
    sign_up(client, "carol@example.com", project_id=project["id"])

    response = request_reset(client, "carol@example.com")

    assert response.status_code == 202
    assert mailbox == []


def test_reset_input_is_validated(client):
    bootstrap(client)

    short_password = reset_password(
        client, "root@example.com", "long-enough-code", new_password="short"
    )
    assert short_password.status_code == 422
    short_code = reset_password(client, "root@example.com", "tiny")
    assert short_code.status_code == 422


def test_forgot_password_is_throttled(client, mailbox):
    bootstrap(client)

    statuses = [
        request_reset(client, "root@example.com").status_code for _ in range(11)
    ]

    assert statuses[:10] == [202] * 10
    assert statuses[10] == 429
