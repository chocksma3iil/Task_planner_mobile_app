"""Comments, subtasks, notifications, and bulk task actions."""
from helpers import auth_headers, bootstrap, sign_up


def _task(client, headers, project_id, **overrides):
    body = {"project_id": project_id, "title": "Prepare report"}
    body.update(overrides)
    response = client.post("/api/v1/tasks", json=body, headers=headers)
    assert response.status_code == 201, response.text
    return response.json()


def _member(client, headers, project_id, email, role="user"):
    response = client.post(
        "/api/v1/members",
        json={
            "name": email.split("@")[0].title(),
            "email": email,
            "password": "password123",
            "project_id": project_id,
            "role": role,
        },
        headers=headers,
    )
    assert response.status_code == 201, response.text
    return response.json()


def test_comment_lifecycle_and_author_rules(client):
    _, headers, project = bootstrap(client)
    task = _task(client, headers, project["id"])

    created = client.post(
        f"/api/v1/tasks/{task['id']}/comments",
        json={"task_id": task["id"], "body": "First note"},
        headers=headers,
    )
    assert created.status_code == 201, created.text
    comment = created.json()
    assert comment["mentions"] == []
    assert comment["edited_at"] is None

    listed = client.get(
        f"/api/v1/tasks/{task['id']}/comments", headers=headers
    ).json()
    assert listed["total"] == 1
    assert listed["items"][0]["body"] == "First note"

    other = _member(client, headers, project["id"], "other@example.com")
    other_headers = auth_headers(client, "other@example.com")
    denied = client.patch(
        f"/api/v1/comments/{comment['id']}",
        json={"body": "Hijacked"},
        headers=other_headers,
    )
    assert denied.status_code == 403

    edited = client.patch(
        f"/api/v1/comments/{comment['id']}",
        json={"body": "Updated note"},
        headers=headers,
    )
    assert edited.status_code == 200
    assert edited.json()["edited_at"] is not None

    deleted = client.delete(
        f"/api/v1/comments/{comment['id']}", headers=headers
    )
    assert deleted.status_code == 204
    listed = client.get(
        f"/api/v1/tasks/{task['id']}/comments", headers=headers
    ).json()
    assert listed["items"][0]["deleted_at"] is not None
    assert listed["items"][0]["body"] == "Updated note"

    edit_deleted = client.patch(
        f"/api/v1/comments/{comment['id']}",
        json={"body": "Again"},
        headers=headers,
    )
    assert edit_deleted.status_code == 400


def test_subtask_crud_and_pagination_shape(client):
    _, headers, project = bootstrap(client)
    task = _task(client, headers, project["id"])

    first = client.post(
        f"/api/v1/tasks/{task['id']}/subtasks",
        json={"task_id": task["id"], "title": "Draft", "sort_order": 1},
        headers=headers,
    )
    assert first.status_code == 201, first.text
    second = client.post(
        f"/api/v1/tasks/{task['id']}/subtasks",
        json={"task_id": task["id"], "title": "Review", "sort_order": 2},
        headers=headers,
    )
    assert second.status_code == 201

    listed = client.get(
        f"/api/v1/tasks/{task['id']}/subtasks", headers=headers
    ).json()
    assert [row["title"] for row in listed["items"]] == ["Draft", "Review"]
    assert listed["total"] == 2

    toggled = client.patch(
        f"/api/v1/tasks/subtasks/{first.json()['id']}",
        json={"completed": True},
        headers=headers,
    )
    assert toggled.status_code == 200
    assert toggled.json()["completed"] is True

    removed = client.delete(
        f"/api/v1/tasks/subtasks/{second.json()['id']}", headers=headers
    )
    assert removed.status_code == 204
    listed = client.get(
        f"/api/v1/tasks/{task['id']}/subtasks", headers=headers
    ).json()
    assert listed["total"] == 1


def test_task_assignment_creates_notification_for_assignee(client):
    _, headers, project = bootstrap(client)
    bob = _member(client, headers, project["id"], "bob@example.com")
    task = _task(
        client, headers, project["id"], title="Ship build",
        assignee_id=bob["id"],
    )
    bob_headers = auth_headers(client, "bob@example.com")

    inbox = client.get("/api/v1/notifications", headers=bob_headers).json()
    assert inbox["total"] == 1
    assert inbox["unread"] == 1
    assert inbox["items"][0]["type"] == "task_assigned"
    assert inbox["items"][0]["payload"] == str(task["id"])

    marked = client.patch(
        "/api/v1/notifications/read",
        json={"notification_ids": [inbox["items"][0]["id"]]},
        headers=bob_headers,
    )
    assert marked.status_code == 200
    assert marked.json()["updated"] == 1

    inbox = client.get("/api/v1/notifications", headers=bob_headers).json()
    assert inbox["unread"] == 0
    assert inbox["items"][0]["read_at"] is not None
    unread_only = client.get(
        "/api/v1/notifications?unread_only=true", headers=bob_headers
    ).json()
    assert unread_only["items"] == []


def test_pending_signup_notifies_project_owner(client):
    _, headers, project = bootstrap(client)
    owner = _member(client, headers, project["id"], "owner@example.com")
    client.post(
        f"/api/v1/projects/{project['id']}/assign-owner",
        json={"owner_id": owner["id"]},
        headers=headers,
    )
    sign_up(
        client, "waiting@example.com", name="Waiting",
        project_id=project["id"],
    )
    owner_headers = auth_headers(client, "owner@example.com")
    inbox = client.get("/api/v1/notifications", headers=owner_headers).json()
    assert inbox["items"][0]["type"] == "member_pending"


def test_bulk_actions_report_per_task_results(client):
    _, headers, project = bootstrap(client)
    first = _task(client, headers, project["id"], title="One")
    second = _task(client, headers, project["id"], title="Two")

    result = client.post(
        "/api/v1/tasks/bulk/complete",
        json={"task_ids": [first["id"], second["id"], 99999]},
        headers=headers,
    ).json()
    assert result["total"] == 3
    assert result["succeeded"] == 2
    assert result["failed"] == 1
    assert result["results"][2]["error"] == "Task not found."

    listed = client.get(
        f"/api/v1/tasks?project_id={project['id']}", headers=headers
    ).json()
    assert [task["status"] for task in listed["items"]] == [
        "completed",
        "completed",
    ]

    bulk_deleted = client.post(
        "/api/v1/tasks/bulk/delete",
        json={"task_ids": [first["id"], second["id"]]},
        headers=headers,
    ).json()
    assert bulk_deleted["succeeded"] == 2
    assert client.get(
        f"/api/v1/tasks?project_id={project['id']}", headers=headers
    ).json()["total"] == 0
