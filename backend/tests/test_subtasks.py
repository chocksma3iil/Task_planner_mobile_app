"""Subtasks: CRUD, ordering, project scoping, and viewer read-only rule."""
from helpers import auth_headers, bootstrap, list_items, sign_up


def _setup(client):
    """Admin, Bob in Alpha, and a task in Alpha."""
    _, headers, project = bootstrap(client, "Alpha")
    bob = sign_up(client, "bob@example.com", name="Bob", project_id=project["id"])
    client.post(f"/api/v1/members/{bob['id']}/confirm", headers=headers)
    task = client.post(
        "/api/v1/tasks",
        json={"project_id": project["id"], "title": "Release"},
        headers=headers,
    ).json()
    return headers, project, bob, task, auth_headers(client, "bob@example.com")


def _add_subtask(client, headers, task_id, title, sort_order=0):
    response = client.post(
        f"/api/v1/tasks/{task_id}/subtasks",
        json={"task_id": task_id, "title": title, "sort_order": sort_order},
        headers=headers,
    )
    assert response.status_code == 200, response.text
    return response.json()


def test_subtask_crud_round_trip_keeps_sort_order(client):
    headers, _, _, task, bob_headers = _setup(client)
    late = _add_subtask(client, bob_headers, task["id"], "Write docs", 2)
    early = _add_subtask(client, bob_headers, task["id"], "Write tests", 1)

    listed = client.get(
        f"/api/v1/tasks/{task['id']}/subtasks", headers=bob_headers
    )
    assert listed.status_code == 200
    body = listed.json()
    assert body["total"] == 2
    assert [row["title"] for row in list_items(body)] == [
        "Write tests",
        "Write docs",
    ]

    updated = client.patch(
        f"/api/v1/tasks/subtasks/{late['id']}",
        json={"title": "Write the docs", "completed": True, "sort_order": 0},
        headers=bob_headers,
    )
    assert updated.status_code == 200, updated.text
    assert updated.json()["title"] == "Write the docs"
    assert updated.json()["completed"] is True
    assert updated.json()["sort_order"] == 0

    reordered = client.get(
        f"/api/v1/tasks/{task['id']}/subtasks", headers=bob_headers
    ).json()
    assert [row["title"] for row in list_items(reordered)] == [
        "Write the docs",
        "Write tests",
    ]

    deleted = client.delete(
        f"/api/v1/tasks/subtasks/{early['id']}", headers=bob_headers
    )
    assert deleted.status_code == 200
    remaining = client.get(
        f"/api/v1/tasks/{task['id']}/subtasks", headers=headers
    ).json()
    assert remaining["total"] == 1
    assert list_items(remaining)[0]["id"] == late["id"]


def test_subtasks_are_scoped_to_the_task_project(client):
    _, admin_headers, project_a = bootstrap(client, "Alpha")
    beta = client.post(
        "/api/v1/projects", json={"name": "Beta"}, headers=admin_headers
    ).json()
    task_a = client.post(
        "/api/v1/tasks",
        json={"project_id": project_a["id"], "title": "Alpha task"},
        headers=admin_headers,
    ).json()
    task_b = client.post(
        "/api/v1/tasks",
        json={"project_id": beta["id"], "title": "Beta task"},
        headers=admin_headers,
    ).json()
    bob = sign_up(client, "bob@example.com", name="Bob",
                  project_id=project_a["id"])
    client.post(f"/api/v1/members/{bob['id']}/confirm", headers=admin_headers)
    bob_headers = auth_headers(client, "bob@example.com")

    # Bob can use subtasks in his own project.
    _add_subtask(client, bob_headers, task_a["id"], "Allowed")

    read = client.get(
        f"/api/v1/tasks/{task_b['id']}/subtasks", headers=bob_headers
    )
    assert read.status_code == 403
    assert read.json()["detail"] == (
        "You can only view subtasks of your own project tasks."
    )

    create = client.post(
        f"/api/v1/tasks/{task_b['id']}/subtasks",
        json={"task_id": task_b["id"], "title": "Sneaky"},
        headers=bob_headers,
    )
    assert create.status_code == 403
    assert create.json()["detail"] == (
        "You can only add subtasks to your own project tasks."
    )

    beta_subtask = _add_subtask(client, admin_headers, task_b["id"], "Beta item")
    patch = client.patch(
        f"/api/v1/tasks/subtasks/{beta_subtask['id']}",
        json={"title": "Hijacked"},
        headers=bob_headers,
    )
    assert patch.status_code == 403
    assert patch.json()["detail"] == (
        "You can only manage subtasks of your own project tasks."
    )

    delete = client.delete(
        f"/api/v1/tasks/subtasks/{beta_subtask['id']}", headers=bob_headers
    )
    assert delete.status_code == 403

    # The admin can manage any project's subtasks.
    assert client.patch(
        f"/api/v1/tasks/subtasks/{beta_subtask['id']}",
        json={"completed": True},
        headers=admin_headers,
    ).status_code == 200


def test_viewers_can_read_but_not_mutate_subtasks(client):
    _, headers, project = bootstrap(client, "Alpha")
    viewer = client.post(
        "/api/v1/members",
        json={
            "name": "Vic Viewer",
            "email": "vic@example.com",
            "password": "password123",
            "project_id": project["id"],
            "role": "viewer",
        },
        headers=headers,
    )
    assert viewer.status_code == 201, viewer.text
    assert viewer.json()["role"] == "viewer"
    viewer_headers = auth_headers(client, "vic@example.com")

    task = client.post(
        "/api/v1/tasks",
        json={"project_id": project["id"], "title": "Read only"},
        headers=headers,
    ).json()
    subtask = _add_subtask(client, headers, task["id"], "Existing")

    listed = client.get(
        f"/api/v1/tasks/{task['id']}/subtasks", headers=viewer_headers
    )
    assert listed.status_code == 200
    assert listed.json()["total"] == 1

    create = client.post(
        f"/api/v1/tasks/{task['id']}/subtasks",
        json={"task_id": task["id"], "title": "Viewer item"},
        headers=viewer_headers,
    )
    assert create.status_code == 403
    assert create.json()["detail"] == "Viewers cannot make changes."

    patch = client.patch(
        f"/api/v1/tasks/subtasks/{subtask['id']}",
        json={"completed": True},
        headers=viewer_headers,
    )
    assert patch.status_code == 403
    assert patch.json()["detail"] == "Viewers cannot make changes."

    delete = client.delete(
        f"/api/v1/tasks/subtasks/{subtask['id']}", headers=viewer_headers
    )
    assert delete.status_code == 403
    assert delete.json()["detail"] == "Viewers cannot make changes."


def test_missing_task_or_subtask_returns_404(client):
    headers, _, _, task, _ = _setup(client)
    missing_task = client.get("/api/v1/tasks/9999/subtasks", headers=headers)
    assert missing_task.status_code == 404
    assert missing_task.json()["detail"] == "Task not found."

    missing_create = client.post(
        "/api/v1/tasks/9999/subtasks",
        json={"task_id": 9999, "title": "Ghost"},
        headers=headers,
    )
    assert missing_create.status_code == 404

    missing_update = client.patch(
        "/api/v1/tasks/subtasks/9999", json={"completed": True}, headers=headers
    )
    assert missing_update.status_code == 404
    assert missing_update.json()["detail"] == "Subtask not found."

    missing_delete = client.delete(
        "/api/v1/tasks/subtasks/9999", headers=headers
    )
    assert missing_delete.status_code == 404

    assert task["id"]
