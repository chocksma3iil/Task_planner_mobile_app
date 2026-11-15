"""Member leave / transfer (B08)."""
from helpers import auth_headers, bootstrap, sign_up


def _create_member_and_confirm(client, headers, project, email, name, role="user"):
    member = sign_up(client, email, name=name, project_id=project["id"])
    client.post(f"/api/v1/members/{member['id']}/confirm", headers=headers)
    return member, auth_headers(client, email)


def _leave(client, user_id, headers):
    response = client.patch(
        f"/api/v1/members/{user_id}/leave", json={}, headers=headers
    )
    return response


def _transfer(client, user_id, project_id, headers):
    response = client.patch(
        f"/api/v1/members/{user_id}/transfer",
        json={"project_id": project_id},
        headers=headers,
    )
    return response


def test_member_can_leave_own_project(client):
    _, headers, project = bootstrap(client)
    bob, bob_headers = _create_member_and_confirm(
        client, headers, project, "bob@example.com", "Bob"
    )
    # Bob leaves his own project.
    response = _leave(client, bob["id"], bob_headers)
    assert response.status_code == 200, response.text
    assert response.json()["project_id"] is None
    assert response.json()["status"] == "pending"

    # Bob cannot log in (pending).
    login = client.post(
        "/api/v1/auth/login",
        json={"email": "bob@example.com", "password": "password123"},
    )
    assert login.status_code == 403, login.text


def test_member_cannot_leave_twice(client):
    _, headers, project = bootstrap(client)
    bob, bob_headers = _create_member_and_confirm(
        client, headers, project, "bob@example.com", "Bob"
    )
    # Bob leaves his own project (allowed).
    response = _leave(client, bob["id"], bob_headers)
    assert response.status_code == 200, response.text

    # Bob is now pending; trying to leave again -> 409.
    response = _leave(client, bob["id"], bob_headers)
    assert response.status_code == 409, response.text


def test_member_leave_reverts_assigned_tasks(client):
    _, headers, project = bootstrap(client)
    bob, bob_headers = _create_member_and_confirm(
        client, headers, project, "bob@example.com", "Bob"
    )
    # Alice creates a task assigned to Bob.
    task = client.post(
        "/api/v1/tasks",
        json={
            "project_id": project["id"],
            "title": "Bob's task",
            "assignee_id": bob["id"],
        },
        headers=headers,
    )
    assert task.status_code == 201, task.text

    # Bob leaves.
    _leave(client, bob["id"], bob_headers)

    # Task's assignee is now NULL (whole project).
    listed = client.get(
        f"/api/v1/tasks?project_id={project['id']}", headers=headers
    ).json()
    row = [t for t in listed["items"] if t["id"] == task.json()["id"]][0]
    assert row["assignee_id"] is None


def test_admin_cannot_leave_owned_project(client):
    _, headers, project = bootstrap(client)
    # Admin is the owner of the project.
    response = _leave(client, 1, headers)
    assert response.status_code == 409, response.text


def test_admin_can_transfer_member(client):
    _, headers, project_a = bootstrap(client)
    project_b = client.post(
        "/api/v1/projects", json={"name": "Beta"}, headers=headers
    ).json()
    bob, bob_headers = _create_member_and_confirm(
        client, headers, project_a, "bob@example.com", "Bob"
    )

    # Transfer Bob to Beta.
    response = _transfer(client, bob["id"], project_b["id"], headers)
    assert response.status_code == 200, response.text
    assert response.json()["project_id"] == project_b["id"]

    # Bob is now in Beta: verify via Bob's own scoped member list.
    bob_in_beta = client.get(
        f"/api/v1/members?project_id={project_b['id']}", headers=bob_headers
    ).json()["items"]
    assert any(m["id"] == bob["id"] for m in bob_in_beta)


def test_admin_cannot_transfer_project_owner(client):
    _, headers, project = bootstrap(client)
    # Admin owns the project -> cannot be transferred.
    response = _transfer(client, 1, 999, headers)
    assert response.status_code == 409, response.text


def test_non_admin_cannot_transfer(client):
    _, headers, project = bootstrap(client)
    bob, bob_headers = _create_member_and_confirm(
        client, headers, project, "bob@example.com", "Bob"
    )
    project_b = client.post(
        "/api/v1/projects", json={"name": "Beta"}, headers=headers
    ).json()
    # Bob (plain user) tries to transfer himself -> 403.
    response = _transfer(
        client, bob["id"], project_b["id"], bob_headers
    )
    assert response.status_code == 403, response.text
