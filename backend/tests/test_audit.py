"""Audit log (D06): sensitive actions are recorded and admin-only readable."""
import json

from helpers import auth_headers, bootstrap, sign_up


def _logs(client, headers, query=""):
    response = client.get(f"/api/v1/audit-logs{query}", headers=headers)
    assert response.status_code == 200, response.text
    return response.json()


def _actions(page):
    return [item["action"] for item in page["items"]]


def test_project_creation_is_recorded_with_actor_and_details(client):
    _, headers, project = bootstrap(client)

    page = _logs(client, headers)

    assert page["total"] == 1
    entry = page["items"][0]
    assert entry["action"] == "project.created"
    assert entry["entity_type"] == "project"
    assert entry["entity_id"] == project["id"]
    assert entry["project_id"] == project["id"]
    assert entry["actor_name"] == "Root Admin"
    assert json.loads(entry["details"])["name"] == project["name"]


def test_member_lifecycle_is_recorded(client):
    _, headers, project = bootstrap(client)

    created = client.post(
        "/api/v1/members",
        json={
            "name": "Active User",
            "email": "active@example.com",
            "password": "password123",
            "project_id": project["id"],
        },
        headers=headers,
    )
    assert created.status_code == 201, created.text

    pending = sign_up(client, "pending@example.com", project_id=project["id"])
    confirmed = client.post(
        f"/api/v1/members/{pending['id']}/confirm", headers=headers
    )
    assert confirmed.status_code == 200, confirmed.text

    changed = client.post(
        f"/api/v1/members/{pending['id']}/role",
        json={"role": "team_lead"},
        headers=headers,
    )
    assert changed.status_code == 200, changed.text

    page = _logs(client, headers)
    by_action = {item["action"]: item for item in page["items"]}

    # project.created + member.created + member.confirmed + member.role_changed
    assert page["total"] == 4
    assert set(by_action) == {
        "project.created",
        "member.created",
        "member.confirmed",
        "member.role_changed",
    }
    role_details = json.loads(by_action["member.role_changed"]["details"])
    assert role_details == {"name": "Tester", "from": "user", "to": "team_lead"}
    # No password (or hash) ever lands in the trail.
    for item in page["items"]:
        assert "password" not in (item["details"] or "").lower()


def test_project_archive_restore_and_owner_assignment_are_recorded(client):
    _, headers, _ = bootstrap(client)
    project = client.post(
        "/api/v1/projects", json={"name": "Beta"}, headers=headers
    ).json()
    candidate = client.post(
        "/api/v1/members",
        json={
            "name": "New Owner",
            "email": "owner@example.com",
            "password": "password123",
            "project_id": project["id"],
        },
        headers=headers,
    ).json()

    assert (
        client.patch(
            f"/api/v1/projects/{project['id']}/archive", headers=headers
        ).status_code
        == 200
    )
    assert (
        client.patch(
            f"/api/v1/projects/{project['id']}/restore", headers=headers
        ).status_code
        == 200
    )
    assert (
        client.post(
            f"/api/v1/projects/{project['id']}/assign-owner",
            json={"owner_id": candidate["id"]},
            headers=headers,
        ).status_code
        == 200
    )

    page = _logs(client, headers)
    assert _actions(page)[:3] == [
        "project.owner_assigned",
        "project.restored",
        "project.archived",
    ]
    assignment = page["items"][0]
    assert assignment["entity_type"] == "member"
    assert assignment["entity_id"] == candidate["id"]
    assert json.loads(assignment["details"])["previous_role"] == "user"


def test_audit_log_is_admin_only(client):
    _, headers, project = bootstrap(client)
    owner = sign_up(client, "owner@example.com", project_id=project["id"])
    assert (
        client.post(
            f"/api/v1/members/{owner['id']}/confirm", headers=headers
        ).status_code
        == 200
    )
    assert (
        client.post(
            f"/api/v1/members/{owner['id']}/role",
            json={"role": "project_owner"},
            headers=headers,
        ).status_code
        == 200
    )
    owner_headers = auth_headers(client, "owner@example.com", password="password123")

    forbidden = client.get("/api/v1/audit-logs", headers=owner_headers)
    assert forbidden.status_code == 403
    assert client.get("/api/v1/audit-logs").status_code == 401


def test_project_filter_and_pagination(client):
    _, headers, alpha = bootstrap(client)
    client.post("/api/v1/projects", json={"name": "Beta"}, headers=headers)

    everything = _logs(client, headers)
    assert everything["total"] == 2

    only_alpha = _logs(client, headers, f"?project_id={alpha['id']}")
    assert only_alpha["total"] == 1
    assert only_alpha["items"][0]["project_id"] == alpha["id"]

    first = _logs(client, headers, "?limit=1&offset=0")
    second = _logs(client, headers, "?limit=1&offset=1")
    assert first["total"] == 2 and len(first["items"]) == 1
    assert len(second["items"]) == 1
    assert first["items"][0]["id"] != second["items"][0]["id"]


def test_refused_actions_leave_no_trace(client):
    _, headers, project = bootstrap(client)
    owner = sign_up(client, "owner@example.com", project_id=project["id"])
    client.post(f"/api/v1/members/{owner['id']}/confirm", headers=headers)
    client.post(
        f"/api/v1/members/{owner['id']}/role",
        json={"role": "project_owner"},
        headers=headers,
    )
    owner_headers = auth_headers(client, "owner@example.com", password="password123")
    before = _logs(client, headers)["total"]

    # Owners cannot create projects, change roles, or archive.
    assert (
        client.post(
            "/api/v1/projects", json={"name": "Hack"}, headers=owner_headers
        ).status_code
        == 403
    )
    assert (
        client.post(
            f"/api/v1/members/{owner['id']}/role",
            json={"role": "admin"},
            headers=owner_headers,
        ).status_code
        == 403
    )
    assert (
        client.patch(
            f"/api/v1/projects/{project['id']}/archive", headers=owner_headers
        ).status_code
        == 403
    )

    assert _logs(client, headers)["total"] == before
