"""Bulk task actions: partial success, validation, notifications, viewers."""
from helpers import auth_headers, bootstrap, sign_up


def _setup(client, count=3):
    """Admin, Bob in Alpha, and `count` unassigned tasks. Returns context."""
    _, headers, project = bootstrap(client, "Alpha")
    bob = sign_up(client, "bob@example.com", name="Bob", project_id=project["id"])
    client.post(f"/api/v1/members/{bob['id']}/confirm", headers=headers)
    tasks = []
    for i in range(count):
        tasks.append(
            client.post(
                "/api/v1/tasks",
                json={"project_id": project["id"], "title": f"Task {i + 1}"},
                headers=headers,
            ).json()
        )
    return headers, project, bob, tasks, auth_headers(client, "bob@example.com")


def test_bulk_complete_reports_each_task_outcome(client):
    headers, _, _, tasks, _ = _setup(client)
    ids = [t["id"] for t in tasks[:2]] + [9999]

    response = client.post(
        "/api/v1/tasks/bulk/complete", json={"task_ids": ids}, headers=headers
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["total"] == 3
    assert body["succeeded"] == 2
    assert body["failed"] == 1
    failures = [row for row in body["results"] if not row["success"]]
    assert failures[0]["task_id"] == 9999
    assert failures[0]["error"] == "Task not found."

    listed = client.get(
        f"/api/v1/tasks?project_id={tasks[0]['project_id']}", headers=headers
    ).json()["items"]
    statuses = {row["title"]: row["status"] for row in listed}
    assert statuses["Task 1"] == "completed"
    assert statuses["Task 2"] == "completed"
    assert statuses["Task 3"] == "todo"


def test_bulk_reassign_validates_assignee_and_notifies(client):
    headers, project, bob, tasks, bob_headers = _setup(client)

    assigned = client.post(
        "/api/v1/tasks/bulk/reassign",
        json={"task_ids": [tasks[0]["id"]], "assignee_id": bob["id"]},
        headers=headers,
    )
    assert assigned.status_code == 200, assigned.text
    assert assigned.json()["succeeded"] == 1
    assert assigned.json()["failed"] == 0

    kinds = [
        row["type"]
        for row in client.get(
            "/api/v1/notifications", headers=bob_headers
        ).json()["items"]
    ]
    assert kinds[0] == "task_assigned"

    # Another project's account is rejected per task, not silently assigned.
    beta = client.post(
        "/api/v1/projects", json={"name": "Beta"}, headers=headers
    ).json()
    eve = sign_up(client, "eve@example.com", name="Eve", project_id=beta["id"])
    client.post(f"/api/v1/members/{eve['id']}/confirm", headers=headers)

    cross = client.post(
        "/api/v1/tasks/bulk/reassign",
        json={"task_ids": [tasks[1]["id"]], "assignee_id": eve["id"]},
        headers=headers,
    )
    assert cross.status_code == 200
    assert cross.json()["succeeded"] == 0
    assert cross.json()["failed"] == 1
    assert cross.json()["results"][0]["error"] == (
        "Assignee must belong to the task project."
    )
    untouched = client.get(
        f"/api/v1/tasks?project_id={project['id']}", headers=headers
    ).json()["items"]
    target = next(row for row in untouched if row["id"] == tasks[1]["id"])
    assert target["assignee_id"] is None


def test_bulk_reassign_requires_an_assignee(client):
    headers, _, _, tasks, _ = _setup(client, count=1)
    response = client.post(
        "/api/v1/tasks/bulk/reassign",
        json={"task_ids": [tasks[0]["id"]]},
        headers=headers,
    )
    assert response.status_code == 400
    assert response.json()["detail"] == "assignee_id is required for reassign"


def test_bulk_delete_notifies_former_assignee(client):
    headers, _, bob, tasks, bob_headers = _setup(client, count=1)
    client.patch(
        f"/api/v1/tasks/{tasks[0]['id']}",
        json={"assignee_id": bob["id"]},
        headers=headers,
    )

    response = client.post(
        "/api/v1/tasks/bulk/delete",
        json={"task_ids": [tasks[0]["id"], 9999]},
        headers=headers,
    )
    assert response.status_code == 200
    assert response.json()["succeeded"] == 1
    assert response.json()["failed"] == 1

    remaining = client.get(
        "/api/v1/tasks?project_id=" + str(tasks[0]["project_id"]), headers=headers
    ).json()
    assert remaining["total"] == 0

    kinds = [
        row["type"]
        for row in client.get(
            "/api/v1/notifications", headers=bob_headers
        ).json()["items"]
    ]
    assert kinds[0] == "task_deleted"


def test_viewers_cannot_use_bulk_actions(client):
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
    ).json()
    task = client.post(
        "/api/v1/tasks",
        json={"project_id": project["id"], "title": "Stable"},
        headers=headers,
    ).json()
    viewer_headers = auth_headers(client, "vic@example.com")

    for action, body in (
        ("complete", {"task_ids": [task["id"]]}),
        ("reassign", {"task_ids": [task["id"]], "assignee_id": viewer["id"]}),
        ("delete", {"task_ids": [task["id"]]}),
    ):
        response = client.post(
            f"/api/v1/tasks/bulk/{action}", json=body, headers=viewer_headers
        )
        assert response.status_code == 403, (action, response.text)
        assert response.json()["detail"] == "Viewers cannot make changes."

    still_there = client.get(
        f"/api/v1/tasks?project_id={project['id']}", headers=headers
    ).json()
    assert still_there["total"] == 1
    assert still_there["items"][0]["status"] == "todo"
