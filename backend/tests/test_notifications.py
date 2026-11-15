"""Notifications: creation triggers, listing, unread filter, mark-as-read."""
from helpers import auth_headers, bootstrap, list_items, sign_up


def _setup(client):
    """Admin, Bob in Alpha, and Bob's headers. Returns (admin, headers, project, bob, bob_headers)."""
    admin, headers, project = bootstrap(client, "Alpha")
    bob = sign_up(client, "bob@example.com", name="Bob", project_id=project["id"])
    client.post(f"/api/v1/members/{bob['id']}/confirm", headers=headers)
    bob_headers = auth_headers(client, "bob@example.com")
    # Confirming the membership itself creates a `member_confirmed`
    # notification. Mark the baseline read so each test starts from a clean
    # unread inbox.
    baseline = client.get("/api/v1/notifications", headers=bob_headers).json()
    baseline_ids = [row["id"] for row in baseline["items"]]
    if baseline_ids:
        client.patch(
            "/api/v1/notifications/read",
            json={"notification_ids": baseline_ids},
            headers=bob_headers,
        )
    return admin, headers, project, bob, bob_headers


def _create_task(client, headers, project, assignee_id, title="Fix login"):
    response = client.post(
        "/api/v1/tasks",
        json={
            "project_id": project["id"],
            "title": title,
            "assignee_id": assignee_id,
        },
        headers=headers,
    )
    assert response.status_code == 201, response.text
    return response.json()


def test_assigning_a_task_notifies_the_assignee_only(client):
    _, headers, project, bob, bob_headers = _setup(client)
    task = _create_task(client, headers, project, bob["id"])

    inbox = client.get("/api/v1/notifications", headers=bob_headers).json()
    assert inbox["total"] == 2
    assert inbox["unread"] == 1
    notification = inbox["items"][0]
    assert notification["type"] == "task_created"
    assert notification["payload"] == str(task["id"])
    assert notification["read_at"] is None
    assert "Fix login" in notification["title"]

    # The actor does not notify themselves.
    assert client.get("/api/v1/notifications", headers=headers).json()["total"] == 0


def test_mark_read_reports_only_really_marked_rows(client):
    _, headers, project, bob, bob_headers = _setup(client)
    _create_task(client, headers, project, bob["id"])
    notification_id = client.get(
        "/api/v1/notifications", headers=bob_headers
    ).json()["items"][0]["id"]

    # Another account cannot mark Bob's notification, and the count stays 0.
    foreign = client.patch(
        "/api/v1/notifications/read",
        json={"notification_ids": [notification_id]},
        headers=headers,
    )
    assert foreign.status_code == 200
    assert foreign.json() == {"marked": 0}

    first = client.patch(
        "/api/v1/notifications/read",
        json={"notification_ids": [notification_id]},
        headers=bob_headers,
    )
    assert first.status_code == 200
    assert first.json() == {"marked": 1}

    # Marking an already-read notification is a no-op.
    again = client.patch(
        "/api/v1/notifications/read",
        json={"notification_ids": [notification_id]},
        headers=bob_headers,
    )
    assert again.json() == {"marked": 0}

    unread = client.get(
        "/api/v1/notifications?unread_only=true", headers=bob_headers
    ).json()
    assert unread["total"] == 0
    assert unread["unread"] == 0

    everything = client.get("/api/v1/notifications", headers=bob_headers).json()
    assert everything["total"] == 2
    assert everything["items"][0]["read_at"] is not None


def test_complete_reopen_and_delete_notify_the_assignee(client):
    _, headers, project, bob, bob_headers = _setup(client)
    task = _create_task(client, headers, project, bob["id"])

    client.patch(f"/api/v1/tasks/{task['id']}/complete", headers=headers)
    client.patch(f"/api/v1/tasks/{task['id']}/reopen", headers=headers)
    client.delete(f"/api/v1/tasks/{task['id']}", headers=headers)

    types = [
        row["type"]
        for row in list_items(
            client.get("/api/v1/notifications", headers=bob_headers)
        )
        if row["type"] != "member_confirmed"
    ]
    assert types == [
        "task_deleted",
        "task_reopened",
        "task_completed",
        "task_created",
    ]


def test_self_assignment_and_self_completion_do_not_notify(client):
    _, _, project, bob, bob_headers = _setup(client)
    created = client.post(
        "/api/v1/tasks",
        json={
            "project_id": project["id"],
            "title": "My own task",
            "assignee_id": bob["id"],
        },
        headers=bob_headers,
    )
    assert created.status_code == 201
    task = created.json()

    done = client.patch(
        f"/api/v1/tasks/{task['id']}/complete", headers=bob_headers
    )
    assert done.status_code == 200
    inbox = client.get("/api/v1/notifications", headers=bob_headers).json()
    # Only the baseline member_confirmed row exists, and it is already read.
    assert inbox["total"] == 1
    assert inbox["unread"] == 0


def test_member_lifecycle_notifications(client):
    _, headers, project = bootstrap(client, "Alpha")

    added = client.post(
        "/api/v1/members",
        json={
            "name": "Mia",
            "email": "mia@example.com",
            "password": "password123",
            "project_id": project["id"],
        },
        headers=headers,
    )
    assert added.status_code == 201
    mia_headers = auth_headers(client, "mia@example.com")
    kinds = [
        row["type"]
        for row in list_items(
            client.get("/api/v1/notifications", headers=mia_headers)
        )
    ]
    assert kinds == ["member_added"]

    changed = client.post(
        f"/api/v1/members/{added.json()['id']}/role",
        json={"role": "team_lead"},
        headers=headers,
    )
    assert changed.status_code == 200
    changed_kinds = [
        row["type"]
        for row in list_items(
            client.get("/api/v1/notifications", headers=mia_headers)
        )
    ]
    assert changed_kinds[0] == "member_role_changed"

    pending = sign_up(client, "sam@example.com", name="Sam",
                      project_id=project["id"])
    confirmed = client.post(
        f"/api/v1/members/{pending['id']}/confirm", headers=headers
    )
    assert confirmed.status_code == 200
    sam_headers = auth_headers(client, "sam@example.com")
    sam_kinds = [
        row["type"]
        for row in list_items(
            client.get("/api/v1/notifications", headers=sam_headers)
        )
    ]
    assert sam_kinds == ["member_confirmed"]


def test_notification_list_is_paginated_and_unread_is_counted(client):
    _, headers, project, bob, bob_headers = _setup(client)
    _create_task(client, headers, project, bob["id"], title="One")
    _create_task(client, headers, project, bob["id"], title="Two")

    page = client.get(
        "/api/v1/notifications?limit=1&offset=0", headers=bob_headers
    ).json()
    assert page["total"] == 3
    assert page["unread"] == 2
    assert page["limit"] == 1
    assert len(list_items(page)) == 1

    second_page = client.get(
        "/api/v1/notifications?limit=1&offset=1", headers=bob_headers
    ).json()
    assert len(list_items(second_page)) == 1
    assert list_items(page)[0]["id"] != list_items(second_page)[0]["id"]

    only_unread = client.get(
        "/api/v1/notifications?unread_only=true", headers=bob_headers
    ).json()
    assert only_unread["total"] == 2
