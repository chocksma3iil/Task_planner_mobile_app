"""2FA / TOTP (A12): enrolment, verification, login challenge, backup codes."""
from helpers import auth_headers, bootstrap

from app.services.totp import totp_now


def _enroll(client, headers):
    response = client.post("/api/v1/auth/2fa/enroll", headers=headers)
    assert response.status_code == 200, response.text
    return response.json()


def _verify_enroll(client, headers, code):
    response = client.post(
        "/api/v1/auth/2fa/verify",
        json={"challenge_id": "unused", "code": code},
        headers=headers,
    )
    assert response.status_code == 200, response.text
    return response.json()


def _login(client, email, password="password123"):
    response = client.post(
        "/api/v1/auth/login", json={"email": email, "password": password}
    )
    assert response.status_code == 200, response.text
    return response.json()


def _login_with_2fa(client, challenge_id, code):
    response = client.post(
        "/api/v1/auth/2fa/login",
        json={"challenge_id": challenge_id, "code": code},
    )
    assert response.status_code == 200, response.text
    return response.json()


def test_2fa_enroll_and_verify(client):
    _, headers, project = bootstrap(client)
    result = _enroll(client, headers)
    assert "secret" in result
    assert "backup_codes" in result
    assert len(result["backup_codes"]) == 8

    # Verify enrollment with a valid TOTP code.
    code = totp_now(result["secret"])
    updated = _verify_enroll(client, headers, code)
    assert "access_token" in updated


def test_2fa_login_flow(client):
    _, headers, project = bootstrap(client)
    enroll = _enroll(client, headers)
    secret = enroll["secret"]

    # Verify enrollment first (activate 2FA).
    code = totp_now(secret)
    _verify_enroll(client, headers, code)

    # Login now requires 2FA: returns challenge instead of token.
    login_result = _login(client, "root@example.com")
    assert login_result["two_factor_required"] is True
    assert "challenge_id" in login_result

    # Verify the challenge code.
    code = totp_now(secret)
    verified = _login_with_2fa(client, login_result["challenge_id"], code)
    assert "access_token" in verified


def test_2fa_backup_code_single_use(client):
    _, headers, project = bootstrap(client)
    enroll = _enroll(client, headers)
    secret = enroll["secret"]
    backup_code = enroll["backup_codes"][0]

    # Activate 2FA with TOTP first.
    _verify_enroll(client, headers, totp_now(secret))

    # Login with backup code (single-use).
    login_result = _login(client, "root@example.com")
    assert login_result["two_factor_required"] is True
    verified = _login_with_2fa(client, login_result["challenge_id"], backup_code)
    assert "access_token" in verified

    # Same backup code must be rejected (single-use).
    login_result2 = _login(client, "root@example.com")
    response = client.post(
        "/api/v1/auth/2fa/login",
        json={"challenge_id": login_result2["challenge_id"], "code": backup_code},
    )
    assert response.status_code == 401, response.text


def test_2fa_disable(client):
    _, headers, project = bootstrap(client)
    enroll = _enroll(client, headers)
    secret = enroll["secret"]

    # Verify enrollment (activate 2FA).
    code = totp_now(secret)
    _verify_enroll(client, headers, code)

    # Disable 2FA.
    response = client.post("/api/v1/auth/2fa/disable", headers=headers)
    assert response.status_code == 200, response.text

    # Status should show disabled.
    response = client.get("/api/v1/auth/2fa/status", headers=headers)
    assert response.status_code == 200, response.text
    assert response.json()["totp_enabled"] is False
    assert response.json()["has_backup_codes"] is False


def test_2fa_status_disabled_by_default(client):
    _, headers, project = bootstrap(client)
    response = client.get("/api/v1/auth/2fa/status", headers=headers)
    assert response.status_code == 200, response.text
    assert response.json()["totp_enabled"] is False
    assert response.json()["has_backup_codes"] is False
