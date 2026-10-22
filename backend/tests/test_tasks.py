"""Tasks: assignment rule, access scoping, status transitions, reads."""
from helpers import auth_headers, bootstrap, sign_up


def _setup(client):
    """Admin, project Alpha, active member Bob in Alpha. Returns ids."""
    _, headers, project = bootstrap(client, "Alpha")
    member = sign_up(client, "bob@example.com", name="Bob",
                     project_id=project["id"])
    client.post(f"/api/v1/members/{member['id']}/confirm", headers=headers)
    return headers, project, member


def test_cross_project_assignment_rejected(client):
    _, headers, project_a = bootstrap(client, "Alpha")
    client.post("/api/v1/projects", json={"name": "Beta"}, headers=headers)
    project_b = client.get("/api/v1/projects").json()[-1]
    outsider = sign_up(client, "eve@example.com", name="Eve",
                       project_id=project_b["id"])
    client.post(f"/api/v1/members/{outsider['id']}/confirm", headers=headers)

    response = client.post(
        "/api/v1/tasks",
        json={"project_id": project_a["id"], "title": "Fix login",
              "assignee_id": outsider["id"]},
        headers=headers,
    )
    assert response.status_code == 400
    assert response.json()["detail"] == {
        "code": "invalid_assignment",
        "message": "Assignee must belong to the task project.",
    }


def test_pending_member_cannot_receive_tasks(client):
    _, headers, project = bootstrap(client)
    pending = sign_up(client, "sara@example.com", name="Sara",
                      project_id=project["id"])
    response = client.post(
        "/api/v1/tasks",
        json={"project_id": project["id"], "title": "For Sara",
              "assignee_id": pending["id"]},
        headers=headers,
    )
    assert response.status_code == 400
    assert response.json()["detail"] == (
        "Tasks can only be assigned to active members."
    )


def test_non_admin_cannot_create_in_another_project(client):
    _, headers, project_a = bootstrap(client, "Alpha")
    client.post("/api/v1/projects", json={"name": "Beta"}, headers=headers)
    project_b = client.get("/api/v1/projects").json()[-1]
    member = sign_up(client, "bob@example.com", name="Bob",
                     project_id=project_a["id"])
    client.post(f"/api/v1/members/{member['id']}/confirm", headers=headers)
    user_headers = auth_headers(client, "bob@example.com")

    response = client.post(
        "/api/v1/tasks",
        json={"project_id": project_b["id"], "title": "Sneaky"},
        headers=user_headers,
    )
    assert response.status_code == 400
    assert response.json()["detail"] == (
        "You can only manage your own project tasks."
    )


def test_complete_then_reopen_stamps_and_clears(client):
    headers, project, _ = _setup(client)
    created = client.post(
        "/api/v1/tasks",
        json={"project_id": project["id"], "title": "Fix login"},
        headers=headers,
    ).json()
    assert created["status"] == "todo"
    assert created["completed_at"] is None

    done = client.patch(f"/api/v1/tasks/{created['id']}/complete", headers=headers)
    assert done.status_code == 200
    assert done.json()["status"] == "completed"
    assert done.json()["completed_at"] is not None

    reopened = client.patch(f"/api/v1/tasks/{created['id']}/reopen", headers=headers)
    assert reopened.status_code == 200
    assert reopened.json()["status"] == "todo"
    assert reopened.json()["completed_at"] is None


def test_delete_removes_task(client):
    headers, project, _ = _setup(client)
    created = client.post(
        "/api/v1/tasks",
        json={"project_id": project["id"], "title": "Temporary"},
        headers=headers,
    ).json()

    deleted = client.delete(f"/api/v1/tasks/{created['id']}", headers=headers)
    assert deleted.status_code == 204

    remaining = client.get(
        f"/api/v1/tasks?project_id={project['id']}", headers=headers
    )
    assert remaining.json() == []


def test_task_reads_are_scoped_and_validated(client):
    headers, project_a, member = _setup(client)
    client.post("/api/v1/projects", json={"name": "Beta"}, headers=headers)
    project_b = client.get("/api/v1/projects").json()[-1]
    user_headers = auth_headers(client, "bob@example.com")

    # Missing / duplicated filters.
    for query in ("", f"?project_id={project_a['id']}&assignee_id={member['id']}"):
        response = client.get(f"/api/v1/tasks{query}", headers=headers)
        assert response.status_code == 400
        assert response.json()["detail"] == "Provide project_id or assignee_id."

    # Another project's tasks are off-limits for non-admins.
    denied = client.get(f"/api/v1/tasks?project_id={project_b['id']}",
                        headers=user_headers)
    assert denied.status_code == 403
    assert denied.json()["detail"] == "You can only view your own project tasks."

    # Admin reads any project.
    assert client.get(f"/api/v1/tasks?project_id={project_b['id']}",
                      headers=headers).status_code == 200


def test_mine_view_returns_only_assigned_tasks(client):
    headers, project, member = _setup(client)
    client.post(
        "/api/v1/tasks",
        json={"project_id": project["id"], "title": "For Bob",
              "assignee_id": member["id"]},
        headers=headers,
    )
    client.post(
        "/api/v1/tasks",
        json={"project_id": project["id"], "title": "Whole project"},
        headers=headers,
    )

    mine = client.get(f"/api/v1/tasks?assignee_id={member['id']}", headers=headers)
    assert [t["title"] for t in mine.json()] == ["For Bob"]

    as_owner = client.get(
        f"/api/v1/tasks?assignee_id={member['id']}",
        headers=auth_headers(client, "bob@example.com"),
    )
    assert [t["title"] for t in as_owner.json()] == ["For Bob"]


def test_edit_task_updates_and_clears_optional_fields(client):
    headers, project, member = _setup(client)
    created = client.post(
        "/api/v1/tasks",
        json={
            "project_id": project["id"],
            "title": "Draft",
            "description": "First pass",
            "priority": "low",
            "due_date": "2026-10-30",
            "assignee_id": member["id"],
        },
        headers=headers,
    ).json()

    edited = client.patch(
        f"/api/v1/tasks/{created['id']}",
        json={
            "title": "  Edited  ",
            "description": None,
            "priority": "high",
            "due_date": None,
            "assignee_id": None,
        },
        headers=headers,
    )
    assert edited.status_code == 200, edited.text
    body = edited.json()
    assert body["title"] == "Edited"
    assert body["description"] is None
    assert body["priority"] == "high"
    assert body["due_date"] is None
    assert body["assignee_id"] is None
    assert body["project_id"] == project["id"]


def test_edit_rejects_blank_title_and_invalid_assignee(client):
    _, headers, project_a = bootstrap(client, "Alpha")
    client.post("/api/v1/projects", json={"name": "Beta"}, headers=headers)
    project_b = client.get("/api/v1/projects").json()[-1]
    outsider = sign_up(
        client, "eve@example.com", name="Eve", project_id=project_b["id"]
    )
    client.post(f"/api/v1/members/{outsider['id']}/confirm", headers=headers)
    pending = sign_up(
        client, "sara@example.com", name="Sara", project_id=project_a["id"]
    )
    task = client.post(
        "/api/v1/tasks",
        json={"project_id": project_a["id"], "title": "Original"},
        headers=headers,
    ).json()

    blank = client.patch(
        f"/api/v1/tasks/{task['id']}",
        json={"title": "   "},
        headers=headers,
    )
    assert blank.status_code == 422

    cross_project = client.patch(
        f"/api/v1/tasks/{task['id']}",
        json={"assignee_id": outsider["id"]},
        headers=headers,
    )
    assert cross_project.status_code == 400
    assert cross_project.json()["detail"] == {
        "code": "invalid_assignment",
        "message": "Assignee must belong to the task project.",
    }

    not_active = client.patch(
        f"/api/v1/tasks/{task['id']}",
        json={"assignee_id": pending["id"]},
        headers=headers,
    )
    assert not_active.status_code == 400
    assert not_active.json()["detail"] == (
        "Tasks can only be assigned to active members."
    )


def test_edit_requires_access_to_the_task_project(client):
    _, headers, project_a = bootstrap(client, "Alpha")
    bob = sign_up(
        client, "bob@example.com", name="Bob", project_id=project_a["id"]
    )
    client.post(f"/api/v1/members/{bob['id']}/confirm", headers=headers)
    client.post("/api/v1/projects", json={"name": "Beta"}, headers=headers)
    project_b = client.get("/api/v1/projects").json()[-1]
    task_b = client.post(
        "/api/v1/tasks",
        json={"project_id": project_b["id"], "title": "Beta task"},
        headers=headers,
    ).json()

    denied = client.patch(
        f"/api/v1/tasks/{task_b['id']}",
        json={"title": "Hijacked"},
        headers=auth_headers(client, "bob@example.com"),
    )
    assert denied.status_code == 400
    assert denied.json()["detail"] == (
        "You can only manage your own project tasks."
    )

    empty = client.patch(
        f"/api/v1/tasks/{task_b['id']}", json={}, headers=headers
    )
    assert empty.status_code == 400
    assert empty.json()["detail"] == "Nothing to update."
