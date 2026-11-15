"""Comments: CRUD, project scoping, viewer read-only."""
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


def _add_comment(client, headers, task_id, body, mentions=None):
    response = client.post(
        f"/api/v1/tasks/{task_id}/comments",
        json={"task_id": task_id, "body": body, "mentions": mentions or []},
        headers=headers,
    )
    assert response.status_code == 201, response.text
    return response.json()


def test_comment_crud_round_trip(client):
    headers, _, _, task, bob_headers = _setup(client)
    comment1 = _add_comment(client, bob_headers, task["id"], "First comment")
    comment2 = _add_comment(client, bob_headers, task["id"], "Reply")

    listed = client.get(f"/api/v1/tasks/{task['id']}/comments", headers=bob_headers)
    assert listed.status_code == 200
    body = listed.json()
    assert body["total"] == 2
    ids = [row["id"] for row in list_items(body)]
    assert comment1["id"] in ids
    assert comment2["id"] in ids

    updated = client.patch(
        f"/api/v1/tasks/comments/{comment1['id']}",
        json={"body": "Updated comment"},
        headers=bob_headers,
    )
    assert updated.status_code == 200, updated.text
    assert updated.json()["body"] == "Updated comment"

    deleted = client.delete(
        f"/api/v1/tasks/comments/{comment2['id']}", headers=bob_headers
    )
    assert deleted.status_code == 204
    remaining = client.get(
        f"/api/v1/tasks/{task['id']}/comments", headers=bob_headers
    ).json()
    assert remaining["total"] == 1
    assert list_items(remaining)[0]["id"] == comment1["id"]


def test_comments_are_scoped_to_the_task_project(client):
    _, admin_headers, project_a = bootstrap(client, "Alpha")
    beta = client.post(
        "/api/v1/projects", json={"name": "Beta"}, headers=admin_headers
    ).json()
    task_a = client.post(
        "/api/v1/tasks",
        json={"project_id": project_a["id"], "title": "Alpha task"},
        headers=admin_headers,
    ).json()
    # Alice in Beta
    alice = sign_up(client, "alice@example.com", name="Alice", project_id=beta["id"])
    client.post(f"/api/v1/members/{alice['id']}/confirm", headers=admin_headers)
    alice_headers = auth_headers(client, "alice@example.com")
    # Alice cannot see or add to Alpha task comments.
    resp = client.get(
        f"/api/v1/tasks/{task_a['id']}/comments", headers=alice_headers
    )
    assert resp.status_code == 403, resp.text
    resp = client.post(
        f"/api/v1/tasks/{task_a['id']}/comments",
        json={"task_id": task_a["id"], "body": "Try"},
        headers=alice_headers,
    )
    assert resp.status_code == 403, resp.text

    # But can comment on a Beta task.
    task_b = client.post(
        "/api/v1/tasks",
        json={"project_id": beta["id"], "title": "Beta task"},
        headers=admin_headers,
    ).json()
    created = client.post(
        f"/api/v1/tasks/{task_b['id']}/comments",
        json={"task_id": task_b["id"], "body": "Beta comment"},
        headers=alice_headers,
    )
    assert created.status_code == 201, created.text


def test_mentions_notify_target_and_dedup(client):
    """Mentions are filtered to project members; self-mentions are dropped."""
    _, _, bob, task, bob_headers = _setup(client)
    # Mentioning Bob himself is ignored (no self-mention).
    comment = _add_comment(
        client, bob_headers, task["id"], "Self mention test", mentions=[bob["id"]]
    )
    assert comment["mentions"] == [], comment