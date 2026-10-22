"""Auth: bootstrap admin, pending sign-ups, login states, token session."""
from helpers import auth_headers, bootstrap, login_token, sign_up


def test_first_signup_becomes_admin_and_can_use_session(client):
    admin = sign_up(client, "root@example.com", name="Root")
    assert admin["role"] == "admin"
    assert admin["status"] == "active"

    headers = auth_headers(client, "root@example.com")
    me = client.get("/api/v1/auth/me", headers=headers)
    assert me.status_code == 200
    assert me.json()["id"] == admin["id"]


def test_signup_without_project_rejected_after_bootstrap(client):
    bootstrap(client)
    response = client.post(
        "/api/v1/auth/signup",
        json={"name": "Sara", "email": "sara@example.com", "password": "password123"},
    )
    assert response.status_code == 400
    assert response.json()["detail"] == {
        "code": "project_required",
        "message": "Choose a project to join.",
    }


def test_pending_signup_cannot_login_until_confirmed(client):
    admin, headers, project = bootstrap(client)
    pending = sign_up(
        client, "sara@example.com", name="Sara", project_id=project["id"]
    )
    assert pending["status"] == "pending"

    blocked = client.post(
        "/api/v1/auth/login", json={"email": "sara@example.com", "password": "password123"}
    )
    assert blocked.status_code == 403
    assert blocked.json()["detail"] == (
        "Account is waiting for project owner confirmation."
    )

    confirm = client.post(f"/api/v1/members/{pending['id']}/confirm", headers=headers)
    assert confirm.status_code == 200
    assert confirm.json()["status"] == "active"
    assert confirm.json()["approved_by"] == admin["id"]

    assert login_token(client, "sara@example.com")


def test_duplicate_email_rejected(client):
    sign_up(client, "root@example.com")
    response = client.post(
        "/api/v1/auth/signup",
        json={"name": "Root Again", "email": "root@example.com", "password": "password123"},
    )
    assert response.status_code == 409
    assert response.json()["detail"] == "An account with this email already exists."


def test_wrong_password_rejected(client):
    sign_up(client, "root@example.com")
    response = client.post(
        "/api/v1/auth/login", json={"email": "root@example.com", "password": "nope"}
    )
    assert response.status_code == 401
    assert response.json()["detail"] == "Wrong email or password."


def test_me_requires_a_valid_token(client):
    assert client.get("/api/v1/auth/me").status_code == 401
    assert (
        client.get(
            "/api/v1/auth/me", headers={"Authorization": "Bearer not-a-token"}
        ).status_code
        == 401
    )
