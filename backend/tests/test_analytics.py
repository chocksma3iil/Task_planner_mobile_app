"""Analytics dashboard, event log, and project archive/restore."""
from datetime import date, timedelta

import pytest
from sqlalchemy import select

from app.core.database import SessionLocal
from app.core.time import utc_now
from app.maintenance import main as maintenance_main
from app.models import AnalyticsEvent
from app.services.analytics_service import purge_old_events
from helpers import auth_headers, bootstrap, list_items, sign_up


def test_dashboard_counts_tasks_and_lists_events(client):
    _, headers, project = bootstrap(client, "Alpha")
    yesterday = (date.today() - timedelta(days=1)).isoformat()
    next_week = (date.today() + timedelta(days=7)).isoformat()

    overdue = client.post(
        "/api/v1/tasks",
        json={
            "project_id": project["id"],
            "title": "Overdue",
            "priority": "low",
            "due_date": yesterday,
        },
        headers=headers,
    ).json()
    client.post(
        "/api/v1/tasks",
        json={
            "project_id": project["id"],
            "title": "Upcoming",
            "priority": "high",
            "due_date": next_week,
        },
        headers=headers,
    )
    done = client.post(
        "/api/v1/tasks",
        json={"project_id": project["id"], "title": "Done", "priority": "medium"},
        headers=headers,
    ).json()
    client.patch(f"/api/v1/tasks/{done['id']}/complete", headers=headers)

    # A subtask event must not break dashboard serialization.
    client.post(
        f"/api/v1/tasks/{overdue['id']}/subtasks",
        json={"task_id": overdue["id"], "title": "Checklist"},
        headers=headers,
    )

    response = client.get(
        f"/api/v1/analytics/dashboard?project_id={project['id']}", headers=headers
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["project_id"] == project["id"]
    assert body["project_name"] == "Alpha"
    assert body["total_tasks"] == 3
    assert body["completed_tasks"] == 1
    assert body["pending_tasks"] == 2
    assert body["overdue_tasks"] == 1
    assert body["completion_rate"] == 33.3
    assert body["overdue_rate"] == 33.3
    assert body["priority_mix"] == {"low": 1, "medium": 1, "high": 1}
    assert body["velocity_per_week"] == 0.2

    events = body["recent_events"]
    assert [e["event_type"] for e in events] == [
        "subtask_created",
        "task_completed",
        "task_created",
        "task_created",
        "task_created",
    ]
    assert {e["actor_name"] for e in events} == {"Root Admin"}
    assert events[0]["task_id"] == overdue["id"]


def test_dashboard_is_scoped_and_validated(client):
    _, headers, project_a = bootstrap(client, "Alpha")
    beta = client.post(
        "/api/v1/projects", json={"name": "Beta"}, headers=headers
    ).json()
    bob = sign_up(client, "bob@example.com", name="Bob",
                  project_id=project_a["id"])
    client.post(f"/api/v1/members/{bob['id']}/confirm", headers=headers)
    bob_headers = auth_headers(client, "bob@example.com")

    denied = client.get(
        f"/api/v1/analytics/dashboard?project_id={beta['id']}",
        headers=bob_headers,
    )
    assert denied.status_code == 403
    assert denied.json()["detail"] == (
        "You can only view your own project dashboard."
    )

    own = client.get(
        f"/api/v1/analytics/dashboard?project_id={project_a['id']}",
        headers=bob_headers,
    )
    assert own.status_code == 200

    admin_any = client.get(
        f"/api/v1/analytics/dashboard?project_id={beta['id']}", headers=headers
    )
    assert admin_any.status_code == 200

    missing = client.get(
        "/api/v1/analytics/dashboard?project_id=9999", headers=headers
    )
    assert missing.status_code == 404
    assert missing.json()["detail"] == "Project not found."

    unvalidated = client.get("/api/v1/analytics/dashboard", headers=headers)
    assert unvalidated.status_code == 422


def test_archive_hides_a_project_and_restore_brings_it_back(client):
    _, headers, project = bootstrap(client, "Alpha")
    bob = sign_up(client, "bob@example.com", name="Bob",
                  project_id=project["id"])
    client.post(f"/api/v1/members/{bob['id']}/confirm", headers=headers)
    bob_headers = auth_headers(client, "bob@example.com")

    archived = client.patch(
        f"/api/v1/projects/{project['id']}/archive", headers=headers
    )
    assert archived.status_code == 200
    assert archived.json()["status"] == "archived"

    default_list = client.get("/api/v1/projects").json()
    assert default_list["total"] == 0
    assert list_items(default_list) == []

    with_archived = client.get("/api/v1/projects?include_archived=true").json()
    assert [p["name"] for p in list_items(with_archived)] == ["Alpha"]
    assert list_items(with_archived)[0]["status"] == "archived"

    denied = client.patch(
        f"/api/v1/projects/{project['id']}/restore", headers=bob_headers
    )
    assert denied.status_code == 403
    assert denied.json()["detail"] == "Only an admin can do this."

    restored = client.patch(
        f"/api/v1/projects/{project['id']}/restore", headers=headers
    )
    assert restored.status_code == 200
    assert restored.json()["status"] == "active"

    back = client.get("/api/v1/projects").json()
    assert [p["name"] for p in list_items(back)] == ["Alpha"]

def test_analytics_events_cover_each_action(client):
    _, headers, project = bootstrap(client, "Alpha")
    bob = sign_up(client, "bob@example.com", name="Bob", project_id=project["id"])
    client.post(f"/api/v1/members/{bob['id']}/confirm", headers=headers)

    task = client.post(
        "/api/v1/tasks",
        json={"project_id": project["id"], "title": "Lifecycle"},
        headers=headers,
    ).json()
    assigned = client.patch(
        f"/api/v1/tasks/{task['id']}",
        json={"assignee_id": bob["id"]},
        headers=headers,
    )
    assert assigned.status_code == 200, assigned.text
    client.patch(f"/api/v1/tasks/{task['id']}/complete", headers=headers)
    client.patch(f"/api/v1/tasks/{task['id']}/reopen", headers=headers)

    bulk_ids = [
        client.post(
            "/api/v1/tasks",
            json={"project_id": project["id"], "title": f"Bulk {i}"},
            headers=headers,
        ).json()["id"]
        for i in range(2)
    ]
    bulk = client.post(
        "/api/v1/tasks/bulk/complete",
        json={"task_ids": bulk_ids},
        headers=headers,
    )
    assert bulk.status_code == 200, bulk.text
    assert bulk.json()["succeeded"] == 2

    deleted = client.delete(f"/api/v1/tasks/{task['id']}", headers=headers)
    assert deleted.status_code == 204, deleted.text

    events = client.get(
        f"/api/v1/analytics/dashboard?project_id={project['id']}",
        headers=headers,
    ).json()["recent_events"]
    types = [e["event_type"] for e in events]
    # Newest first: the delete closes the lifecycle.
    assert types[0] == "task_deleted"
    assert types.count("task_created") == 3
    assert types.count("task_completed") == 3
    assert types.count("task_reopened") == 1
    assert types.count("task_assigned") == 1
    assert types.count("task_deleted") == 1
    assert events[0]["task_id"] == task["id"]
    assert {e["actor_name"] for e in events} == {"Root Admin"}


def test_purge_old_events_respects_the_retention_window(client):
    _, headers, project = bootstrap(client, "Alpha")
    for title in ("Old", "New"):
        client.post(
            "/api/v1/tasks",
            json={"project_id": project["id"], "title": title},
            headers=headers,
        )

    with SessionLocal() as db:
        events = list(db.scalars(select(AnalyticsEvent).order_by(AnalyticsEvent.id)))
        assert len(events) == 2
        events[0].created_at = utc_now() - timedelta(days=400)
        db.commit()

        with pytest.raises(ValueError):
            purge_old_events(db, days=0)

        assert purge_old_events(db, days=365) == 1
        remaining = list(db.scalars(select(AnalyticsEvent)))
        assert [event.id for event in remaining] == [events[1].id]

        # Running it again is a no-op.
        assert purge_old_events(db, days=365) == 0


def test_maintenance_command_reports_the_deleted_rows(client, capsys):
    _, headers, project = bootstrap(client, "Alpha")
    client.post(
        "/api/v1/tasks",
        json={"project_id": project["id"], "title": "Recent"},
        headers=headers,
    )

    assert maintenance_main(["purge-events", "--days", "365"]) == 0
    assert "Deleted 0 analytics event(s) older than 365 days." in capsys.readouterr().out
