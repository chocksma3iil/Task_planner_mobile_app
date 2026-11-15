"""Analytics dashboard, audit trail, project reports, archive lifecycle."""
import csv
import io
from datetime import date, timedelta

from helpers import auth_headers, bootstrap


def _task(client, headers, project_id, **overrides):
    body = {"project_id": project_id, "title": "Task"}
    body.update(overrides)
    response = client.post("/api/v1/tasks", json=body, headers=headers)
    assert response.status_code == 201, response.text
    return response.json()


def test_dashboard_counts_and_recent_events(client):
    _, headers, project = bootstrap(client)
    done = _task(
        client, headers, project["id"], title="Done", priority="high"
    )
    client.patch(
        f"/api/v1/tasks/{done['id']}/complete", headers=headers
    )
    _task(
        client,
        headers,
        project["id"],
        title="Late",
        priority="low",
        due_date=(date.today() - timedelta(days=2)).isoformat(),
    )
    _task(client, headers, project["id"], title="Open")

    stats = client.get(
        f"/api/v1/analytics/dashboard?project_id={project['id']}",
        headers=headers,
    ).json()
    assert stats["project_id"] == project["id"]
    assert stats["total_tasks"] == 3
    assert stats["completed_tasks"] == 1
    assert stats["pending_tasks"] == 2
    assert stats["overdue_tasks"] == 1
    assert stats["completion_rate"] == 33.3
    assert stats["overdue_rate"] == 33.3
    assert stats["priority_mix"] == {"low": 1, "medium": 1, "high": 1}
    assert stats["velocity_per_week"] == 0.25
    types = [event["event_type"] for event in stats["recent_events"]]
    assert "task_created" in types
    assert "task_completed" in types


def test_audit_log_requires_admin_and_records_project_actions(client):
    admin, headers, project = bootstrap(client)
    client.post(
        "/api/v1/members",
        json={
            "name": "Bob",
            "email": "bob@example.com",
            "password": "password123",
            "project_id": project["id"],
        },
        headers=headers,
    )
    client.patch(
        f"/api/v1/projects/{project['id']}/archive", headers=headers
    )
    client.patch(
        f"/api/v1/projects/{project['id']}/restore", headers=headers
    )

    page = client.get(
        "/api/v1/audit-logs?limit=50", headers=headers
    ).json()
    actions = {row["action"] for row in page["items"]}
    assert {"project.created", "member.created", "project.archived",
            "project.restored"} <= actions
    assert page["total"] >= 4

    bob_headers = auth_headers(client, "bob@example.com")
    denied = client.get("/api/v1/audit-logs", headers=bob_headers)
    assert denied.status_code == 400


def test_project_export_csv_and_pdf(client):
    _, headers, project = bootstrap(client)
    _task(client, headers, project["id"], title="Write docs")

    report = client.get(
        f"/api/v1/projects/{project['id']}/export?format=csv",
        headers=headers,
    )
    assert report.status_code == 200
    assert report.headers["content-type"].startswith("text/csv")
    rows = list(csv.reader(io.StringIO(report.content.decode("utf-8"))))
    assert rows[0][:3] == ["id", "title", "status"]
    assert rows[1][1] == "Write docs"

    pdf = client.get(
        f"/api/v1/projects/{project['id']}/export?format=pdf",
        headers=headers,
    )
    assert pdf.status_code == 200
    assert pdf.headers["content-type"] == "application/pdf"
    assert pdf.content.startswith(b"%PDF-1.4")
    assert pdf.content.rstrip().endswith(b"%%EOF")

    bad = client.get(
        f"/api/v1/projects/{project['id']}/export?format=xlsx",
        headers=headers,
    )
    assert bad.status_code == 400


def test_archive_hides_project_unless_requested(client):
    _, headers, project = bootstrap(client)
    client.patch(f"/api/v1/projects/{project['id']}/archive", headers=headers)
    assert client.get("/api/v1/projects").json()["total"] == 0
    with_archived = client.get(
        "/api/v1/projects?include_archived=true"
    ).json()
    assert with_archived["total"] == 1
    assert with_archived["items"][0]["status"] == "archived"

    restored = client.patch(
        f"/api/v1/projects/{project['id']}/restore", headers=headers
    )
    assert restored.status_code == 200
    assert restored.json()["status"] == "active"
