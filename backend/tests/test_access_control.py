"""Access-control matrix: authentication gate and role-scoped operations."""
import pytest

from helpers import auth_headers, bootstrap, list_items, sign_up

PROTECTED_REQUESTS = [
    ("GET", "/api/v1/auth/me", None),
    ("GET", "/api/v1/members", None),
    (
        "POST",
        "/api/v1/members",
        {
            "name": "New",
            "email": "new@example.com",
            "password": "password123",
            "project_id": 1,
        },
    ),
    ("POST", "/api/v1/members/1/confirm", None),
    ("POST", "/api/v1/members/1/role", {"role": "user"}),
    ("POST", "/api/v1/projects", {"name": "No Token"}),
    ("POST", "/api/v1/projects/1/assign-owner", {"owner_id": 1}),
    ("GET", "/api/v1/tasks?project_id=1", None),
    ("POST", "/api/v1/tasks", {"project_id": 1, "title": "No Token"}),
    ("PATCH", "/api/v1/tasks/1", {"title": "No Token"}),
    ("PATCH", "/api/v1/tasks/1/complete", None),
    ("PATCH", "/api/v1/tasks/1/reopen", None),
    ("DELETE", "/api/v1/tasks/1", None),
]


@pytest.mark.parametrize(("method", "path", "body"), PROTECTED_REQUESTS)
def test_protected_routes_reject_missing_token(client, method, path, body):
    response = client.request(method, path, json=body)
    assert response.status_code == 401
    assert response.json()["detail"] == "Not authenticated."


def _owner_in_project(client, admin_headers, project, email, name):
    member = sign_up(client, email, name=name, project_id=project["id"])
    client.post(
        f"/api/v1/members/{member['id']}/confirm", headers=admin_headers
    )
    client.post(
        f"/api/v1/projects/{project['id']}/assign-owner",
        json={"owner_id": member["id"]},
        headers=admin_headers,
    )
    return member, auth_headers(client, email)


def test_owner_cannot_view_another_projects_tasks(client):
    _, admin_headers, project_a = bootstrap(client, "Alpha")
    beta = client.post(
        "/api/v1/projects", json={"name": "Beta"}, headers=admin_headers
    ).json()
    _, owner_headers = _owner_in_project(
        client, admin_headers, project_a, "olive@example.com", "Olive"
    )

    denied = client.get(
        f"/api/v1/tasks?project_id={beta['id']}", headers=owner_headers
    )
    assert denied.status_code == 403
    assert denied.json()["detail"] == (
        "You can only view your own project tasks."
    )


def test_plain_user_cannot_use_owner_or_admin_operations(client):
    _, admin_headers, project = bootstrap(client)
    bob = sign_up(client, "bob@example.com", name="Bob",
                  project_id=project["id"])
    client.post(f"/api/v1/members/{bob['id']}/confirm", headers=admin_headers)
    user_headers = auth_headers(client, "bob@example.com")
    pending = sign_up(client, "sara@example.com", name="Sara",
                      project_id=project["id"])

    attempts = [
        (
            "POST",
            "/api/v1/members",
            {
                "name": "Created By User",
                "email": "created@example.com",
                "password": "password123",
                "project_id": project["id"],
            },
            "Only admins, owners, and team leads can add members.",
        ),
        (
            "POST",
            f"/api/v1/members/{pending['id']}/confirm",
            None,
            "Only admins, owners, and team leads can confirm members.",
        ),
        (
            "POST",
            f"/api/v1/members/{pending['id']}/role",
            {"role": "admin"},
            "Only an admin can do this.",
        ),
        (
            "POST",
            "/api/v1/projects",
            {"name": "User Project"},
            "Only an admin can do this.",
        ),
        (
            "POST",
            f"/api/v1/projects/{project['id']}/assign-owner",
            {"owner_id": bob["id"]},
            "Only an admin can do this.",
        ),
    ]

    for method, path, body, detail in attempts:
        response = client.request(method, path, json=body, headers=user_headers)
        assert response.status_code == 403, (method, path, response.text)
        assert response.json()["detail"] == detail, (method, path, response.text)


def test_admin_can_manage_members_and_tasks_in_any_project(client):
    _, admin_headers, project_a = bootstrap(client, "Alpha")
    project_b = client.post(
        "/api/v1/projects", json={"name": "Beta"}, headers=admin_headers
    ).json()

    task = client.post(
        "/api/v1/tasks",
        json={"project_id": project_b["id"], "title": "Beta task"},
        headers=admin_headers,
    )
    assert task.status_code == 201

    members = client.get("/api/v1/members", headers=admin_headers)
    assert members.status_code == 200

    tasks_a = client.get(
        f"/api/v1/tasks?project_id={project_a['id']}", headers=admin_headers
    )
    tasks_b = client.get(
        f"/api/v1/tasks?project_id={project_b['id']}", headers=admin_headers
    )
    assert tasks_a.status_code == tasks_b.status_code == 200
    assert [row["title"] for row in list_items(tasks_b)] == ["Beta task"]
