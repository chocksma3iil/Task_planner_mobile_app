"""Team lead and viewer roles: delegated member management and read-only."""
from helpers import auth_headers, bootstrap, sign_up


def _account(client, headers, name, email, project_id, role):
    response = client.post(
        "/api/v1/members",
        json={
            "name": name,
            "email": email,
            "password": "password123",
            "project_id": project_id,
            "role": role,
        },
        headers=headers,
    )
    assert response.status_code == 201, response.text
    return response.json()


def test_team_lead_manages_own_project_members_only(client):
    _, admin_headers, project_a = bootstrap(client, "Alpha")
    project_b = client.post(
        "/api/v1/projects", json={"name": "Beta"}, headers=admin_headers
    ).json()
    _account(
        client, admin_headers, "Tara Lead", "tara@example.com",
        project_a["id"], "team_lead",
    )
    lead_headers = auth_headers(client, "tara@example.com")

    created = client.post(
        "/api/v1/members",
        json={
            "name": "New User",
            "email": "new@example.com",
            "password": "password123",
            "project_id": project_a["id"],
        },
        headers=lead_headers,
    )
    assert created.status_code == 201, created.text
    assert created.json()["status"] == "active"
    assert created.json()["role"] == "user"

    wrong_project = client.post(
        "/api/v1/members",
        json={
            "name": "Beta User",
            "email": "beta@example.com",
            "password": "password123",
            "project_id": project_b["id"],
        },
        headers=lead_headers,
    )
    assert wrong_project.status_code == 403
    assert wrong_project.json()["detail"] == (
        "Owners and team leads can only add plain users to their project."
    )

    elevated = client.post(
        "/api/v1/members",
        json={
            "name": "Second Lead",
            "email": "second@example.com",
            "password": "password123",
            "project_id": project_a["id"],
            "role": "team_lead",
        },
        headers=lead_headers,
    )
    assert elevated.status_code == 403

    pending = sign_up(client, "sam@example.com", name="Sam",
                      project_id=project_a["id"])
    confirmed = client.post(
        f"/api/v1/members/{pending['id']}/confirm", headers=lead_headers
    )
    assert confirmed.status_code == 200
    assert confirmed.json()["status"] == "active"

    other_pending = sign_up(client, "dan@example.com", name="Dan",
                            project_id=project_b["id"])
    denied = client.post(
        f"/api/v1/members/{other_pending['id']}/confirm", headers=lead_headers
    )
    assert denied.status_code == 403
    assert denied.json()["detail"] == (
        "You can only confirm your own project members."
    )

    role_change = client.post(
        f"/api/v1/members/{created.json()['id']}/role",
        json={"role": "project_owner"},
        headers=lead_headers,
    )
    assert role_change.status_code == 403
    assert role_change.json()["detail"] == "Only an admin can do this."

    project_create = client.post(
        "/api/v1/projects", json={"name": "Lead Project"}, headers=lead_headers
    )
    assert project_create.status_code == 403
    assert project_create.json()["detail"] == "Only an admin can do this."


def test_team_lead_can_work_on_tasks_in_own_project(client):
    _, admin_headers, project = bootstrap(client, "Alpha")
    _account(
        client, admin_headers, "Tara Lead", "tara@example.com",
        project["id"], "team_lead",
    )
    lead_headers = auth_headers(client, "tara@example.com")

    task = client.post(
        "/api/v1/tasks",
        json={"project_id": project["id"], "title": "Lead task"},
        headers=lead_headers,
    )
    assert task.status_code == 201, task.text

    done = client.patch(
        f"/api/v1/tasks/{task.json()['id']}/complete", headers=lead_headers
    )
    assert done.status_code == 200
    assert done.json()["status"] == "completed"


def test_viewer_is_read_only_everywhere(client):
    _, admin_headers, project = bootstrap(client, "Alpha")
    viewer = _account(
        client, admin_headers, "Vic Viewer", "vic@example.com",
        project["id"], "viewer",
    )
    assert viewer["role"] == "viewer"
    viewer_headers = auth_headers(client, "vic@example.com")

    task = client.post(
        "/api/v1/tasks",
        json={"project_id": project["id"], "title": "Read only"},
        headers=admin_headers,
    ).json()
    pending = sign_up(client, "sam@example.com", name="Sam",
                      project_id=project["id"])

    # Reads are allowed.
    assert client.get("/api/v1/members", headers=viewer_headers).status_code == 200
    assert client.get(
        f"/api/v1/tasks?project_id={project['id']}", headers=viewer_headers
    ).status_code == 200

    write_attempts = [
        (
            "POST",
            "/api/v1/tasks",
            {"project_id": project["id"], "title": "Viewer task"},
        ),
        ("PATCH", f"/api/v1/tasks/{task['id']}", {"title": "Edited"}),
        ("PATCH", f"/api/v1/tasks/{task['id']}/complete", None),
        ("PATCH", f"/api/v1/tasks/{task['id']}/reopen", None),
        ("DELETE", f"/api/v1/tasks/{task['id']}", None),
        ("POST", "/api/v1/projects", {"name": "Viewer project"}),
        ("PATCH", f"/api/v1/projects/{project['id']}/archive", None),
        (
            "POST",
            "/api/v1/members",
            {
                "name": "Blocked",
                "email": "blocked@example.com",
                "password": "password123",
                "project_id": project["id"],
            },
        ),
        ("POST", f"/api/v1/members/{pending['id']}/confirm", None),
        (
            "POST",
            f"/api/v1/projects/{project['id']}/assign-owner",
            {"owner_id": viewer["id"]},
        ),
    ]
    for method, path, body in write_attempts:
        response = client.request(
            method, path, json=body, headers=viewer_headers
        )
        assert response.status_code == 403, (method, path, response.text)
        assert response.json()["detail"] == "Viewers cannot make changes."

    # The task was not altered by any rejected attempt.
    listed = client.get(
        f"/api/v1/tasks?project_id={project['id']}", headers=admin_headers
    ).json()["items"]
    assert listed[0]["title"] == "Read only"
    assert listed[0]["status"] == "todo"


def test_admin_can_move_between_team_lead_and_viewer_roles(client):
    _, admin_headers, project = bootstrap(client, "Alpha")
    account = sign_up(client, "bob@example.com", name="Bob",
                      project_id=project["id"])
    client.post(f"/api/v1/members/{account['id']}/confirm", headers=admin_headers)
    bob_headers = auth_headers(client, "bob@example.com")

    for role in ("team_lead", "viewer", "user"):
        response = client.post(
            f"/api/v1/members/{account['id']}/role",
            json={"role": role},
            headers=admin_headers,
        )
        assert response.status_code == 200, response.text
        assert response.json()["role"] == role

    # Back to user: task creation works again.
    created = client.post(
        "/api/v1/tasks",
        json={"project_id": project["id"], "title": "After demotion"},
        headers=bob_headers,
    )
    assert created.status_code == 201
