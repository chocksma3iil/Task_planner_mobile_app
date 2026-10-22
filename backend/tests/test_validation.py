"""Input validation, UTC serialization, and the versioned routing surface."""
from datetime import datetime, timezone

from helpers import bootstrap


def test_health_is_unversioned(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_feature_routes_live_under_api_v1(client):
    # Unversioned feature paths no longer exist (root may redirect or 404).
    response = client.post(
        "/auth/login", json={"email": "a@example.com", "password": "whatever"}
    )
    assert response.status_code == 404


def test_short_password_rejected(client):
    response = client.post(
        "/api/v1/auth/signup",
        json={"name": "Short", "email": "short@example.com", "password": "short"},
    )
    assert response.status_code == 422
    assert "password" in response.json()["detail"]


def test_email_is_normalized_lowercased_and_unique(client):
    created = client.post(
        "/api/v1/auth/signup",
        json={
            "name": "Root",
            "email": "  Root@Example.COM ",
            "password": "password123",
        },
    )
    assert created.status_code == 201, created.text
    assert created.json()["email"] == "root@example.com"

    duplicate = client.post(
        "/api/v1/auth/signup",
        json={
            "name": "Root Again",
            "email": "ROOT@example.com",
            "password": "password123",
        },
    )
    assert duplicate.status_code == 409

    login = client.post(
        "/api/v1/auth/login",
        json={"email": "root@example.com", "password": "password123"},
    )
    assert login.status_code == 200


def test_api_timestamps_are_utc(client):
    created = client.post(
        "/api/v1/auth/signup",
        json={"name": "Root", "email": "root@example.com", "password": "password123"},
    ).json()
    assert created["created_at"].endswith("+00:00")
    stored = datetime.fromisoformat(created["created_at"])
    assert abs((datetime.now(timezone.utc) - stored).total_seconds()) < 300


def test_blank_names_and_titles_rejected(client):
    _, headers, project = bootstrap(client)

    blank_project = client.post(
        "/api/v1/projects", json={"name": "   "}, headers=headers
    )
    assert blank_project.status_code == 422
    assert "name" in blank_project.json()["detail"]

    blank_task = client.post(
        "/api/v1/tasks",
        json={"project_id": project["id"], "title": "   "},
        headers=headers,
    )
    assert blank_task.status_code == 422
    assert "title" in blank_task.json()["detail"]


def test_priority_is_validated(client):
    _, headers, project = bootstrap(client)
    response = client.post(
        "/api/v1/tasks",
        json={
            "project_id": project["id"],
            "title": "Fix login",
            "priority": "urgent",
        },
        headers=headers,
    )
    assert response.status_code == 422
    assert "priority" in response.json()["detail"]
