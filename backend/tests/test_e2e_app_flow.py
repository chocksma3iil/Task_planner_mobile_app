"""End-to-end app flow over the real API: onboarding through reporting."""
from helpers import auth_headers, bootstrap, sign_up


def test_full_app_flow(client):
    admin, admin_headers, project = bootstrap(client, "E2E")
    project_id = project["id"]

    bob = sign_up(client, "bob@example.com", name="Bob", project_id=project_id)
    client.post(
        f"/api/v1/members/{bob['id']}/confirm", headers=admin_headers
    )
    assigned = client.post(
        f"/api/v1/projects/{project_id}/assign-owner",
        json={"owner_id": bob["id"]},
        headers=admin_headers,
    )
    assert assigned.status_code == 200
    bob_headers = auth_headers(client, "bob@example.com")

    lead = client.post(
        "/api/v1/members",
        json={
            "name": "Lea",
            "email": "lea@example.com",
            "password": "password123",
            "project_id": project_id,
            "role": "team_lead",
        },
        headers=admin_headers,
    ).json()
    dana = sign_up(
        client, "dana@example.com", name="Dana", project_id=project_id
    )

    bob_inbox = client.get(
        "/api/v1/notifications", headers=bob_headers
    ).json()
    assert bob_inbox["items"][0]["type"] == "member_pending"

    lead_headers = auth_headers(client, "lea@example.com")
    confirmed = client.post(
        f"/api/v1/members/{dana['id']}/confirm", headers=lead_headers
    )
    assert confirmed.status_code == 200

    task = client.post(
        "/api/v1/tasks",
        json={
            "project_id": project_id,
            "title": "Ship the release",
            "description": "Finish the pre-release checklist.",
            "priority": "high",
            "assignee_id": dana["id"],
        },
        headers=bob_headers,
    ).json()

    dana_headers = auth_headers(client, "dana@example.com")
    dana_inbox = client.get(
        "/api/v1/notifications", headers=dana_headers
    ).json()
    assert dana_inbox["items"][0]["type"] == "task_assigned"

    comment = client.post(
        f"/api/v1/tasks/{task['id']}/comments",
        json={"task_id": task["id"], "body": "Started on it."},
        headers=dana_headers,
    )
    assert comment.status_code == 201
    subtask = client.post(
        f"/api/v1/tasks/{task['id']}/subtasks",
        json={"task_id": task["id"], "title": "Run checks"},
        headers=dana_headers,
    ).json()
    client.patch(
        f"/api/v1/tasks/subtasks/{subtask['id']}",
        json={"completed": True},
        headers=dana_headers,
    )

    completed = client.patch(
        f"/api/v1/tasks/{task['id']}/complete", headers=bob_headers
    )
    assert completed.json()["status"] == "completed"

    stats = client.get(
        f"/api/v1/analytics/dashboard?project_id={project_id}",
        headers=bob_headers,
    ).json()
    assert stats["total_tasks"] == 1
    assert stats["completed_tasks"] == 1
    assert stats["completion_rate"] == 100.0
    assert stats["recent_events"][0]["event_type"] == "task_completed"

    audit = client.get(
        "/api/v1/audit-logs", headers=admin_headers
    ).json()
    actions = {row["action"] for row in audit["items"]}
    assert {"project.created", "project.owner_assigned",
            "member.confirmed"} <= actions

    export = client.get(
        f"/api/v1/projects/{project_id}/export?format=csv",
        headers=bob_headers,
    )
    assert export.status_code == 200
    assert b"Ship the release" in export.content

    plan = client.patch(
        f"/api/v1/projects/{project_id}/ai-opt-in",
        json={"ai_opt_in": True},
        headers=bob_headers,
    )
    assert plan.status_code == 200
    ai = client.post(
        f"/api/v1/ai/briefing?project_id={project_id}", headers=bob_headers
    )
    assert ai.status_code == 200

    archived = client.patch(
        f"/api/v1/projects/{project_id}/archive", headers=admin_headers
    )
    assert archived.json()["status"] == "archived"
    restored = client.patch(
        f"/api/v1/projects/{project_id}/restore", headers=admin_headers
    )
    assert restored.json()["status"] == "active"

    lead_view = client.get(
        "/api/v1/members", headers=lead_headers
    ).json()
    assert {row["email"] for row in lead_view["items"]} >= {
        "bob@example.com",
        "lea@example.com",
        "dana@example.com",
    }
