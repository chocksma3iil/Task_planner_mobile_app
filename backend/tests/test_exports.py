"""Project exports (E03): CSV and PDF report downloads."""
from helpers import auth_headers, bootstrap, login_token

HEADER = "id,title,status,priority,due_date,assignee,created_at,completed_at"


def _create_member(client, headers, project_id, name, email, role="user"):
    response = client.post(
        "/api/v1/members",
        json={
            "name": name,
            "email": email,
            "password": "password123",
            "project_id": project_id,
            "role": role,
        },
        headers=headers,
    )
    assert response.status_code == 201, response.text
    return response.json()


def _create_task(client, headers, project_id, title, **extra):
    body = {"title": title, "project_id": project_id, **extra}
    response = client.post("/api/v1/tasks", json=body, headers=headers)
    assert response.status_code == 201, response.text
    return response.json()


def test_csv_export_has_header_and_quoted_rows(client):
    _, headers, project = bootstrap(client)
    bob = _create_member(client, headers, project["id"], "Bob", "bob@example.com")
    _create_task(client, headers, project["id"], 'Review "final", please')
    _create_task(
        client, headers, project["id"], "Assigned task", assignee_id=bob["id"]
    )

    response = client.get(
        f"/api/v1/projects/{project['id']}/export?format=csv", headers=headers
    )

    assert response.status_code == 200, response.text
    assert response.headers["content-type"].startswith("text/csv")
    assert (
        response.headers["content-disposition"]
        == f'attachment; filename="project-{project["id"]}-report.csv"'
    )
    lines = response.text.splitlines()
    assert lines[0] == HEADER
    assert len(lines) == 3
    assert '"Review ""final"", please"' in response.text
    assert "2,Assigned task,todo,medium,,Bob," in response.text
    # Project-level tasks name the project as the assignee.
    assert "Whole project" in response.text


def test_pdf_export_returns_a_pdf(client):
    _, headers, project = bootstrap(client)
    _create_task(client, headers, project["id"], "PDF task")

    response = client.get(
        f"/api/v1/projects/{project['id']}/export?format=pdf", headers=headers
    )

    assert response.status_code == 200, response.text
    assert response.headers["content-type"].startswith("application/pdf")
    assert response.content.startswith(b"%PDF")
    assert len(response.content) > 1000


def test_viewers_and_users_can_export_their_project(client):
    _, headers, project = bootstrap(client)
    _create_member(
        client, headers, project["id"], "Vera Viewer", "vera@example.com", role="viewer"
    )

    viewer_headers = auth_headers(client, "vera@example.com")
    response = client.get(
        f"/api/v1/projects/{project['id']}/export?format=csv", headers=viewer_headers
    )

    assert response.status_code == 200, response.text
    assert response.text.startswith(HEADER)


def test_export_requires_project_access(client):
    _, headers, alpha = bootstrap(client)
    beta = client.post(
        "/api/v1/projects", json={"name": "Beta"}, headers=headers
    ).json()
    owner = client.post(
        "/api/v1/members",
        json={
            "name": "Olive",
            "email": "olive@example.com",
            "password": "password123",
            "project_id": alpha["id"],
            "role": "project_owner",
        },
        headers=headers,
    ).json()
    owner_headers = auth_headers(client, "olive@example.com")

    foreign = client.get(
        f"/api/v1/projects/{beta['id']}/export?format=csv", headers=owner_headers
    )
    assert foreign.status_code == 403
    assert (
        client.get(f"/api/v1/projects/{alpha['id']}/export?format=csv").status_code
        == 401
    )
    assert (
        client.get("/api/v1/projects/999999/export?format=csv", headers=headers).status_code
        == 404
    )
    assert owner["email"] == "olive@example.com"


def test_export_handles_due_dates_and_completed_tasks(client):
    """Regression: `due_date` is a `date`, not a `datetime` (E19 caught it)."""
    _, headers, project = bootstrap(client)
    task = _create_task(client, headers, project["id"], "Dated task", due_date="2026-11-15")
    assert task["due_date"] == "2026-11-15", task
    completed = client.patch(
        f"/api/v1/tasks/{task['id']}/complete", headers=headers
    )
    assert completed.status_code == 200, completed.text

    csv_response = client.get(
        f"/api/v1/projects/{project['id']}/export?format=csv", headers=headers
    )
    assert csv_response.status_code == 200, csv_response.text
    row = [
        line.split(",")
        for line in csv_response.text.splitlines()
        if "Dated task" in line
    ][0]
    assert row[1:6] == [
        "Dated task",
        "completed",
        "medium",
        "2026-11-15",
        "Whole project",
    ]
    # The completion timestamp column is filled in for completed tasks.
    assert row[7] != ""

    pdf_response = client.get(
        f"/api/v1/projects/{project['id']}/export?format=pdf", headers=headers
    )
    assert pdf_response.status_code == 200, pdf_response.text
    assert pdf_response.content.startswith(b"%PDF")


def test_export_scales_to_many_tasks(client):
    _, headers, project = bootstrap(client)
    for index in range(30):
        _create_task(client, headers, project["id"], f"Task {index}")

    response = client.get(
        f"/api/v1/projects/{project['id']}/export?format=csv", headers=headers
    )

    assert response.status_code == 200
    assert len(response.text.splitlines()) == 31
    assert login_token(client, "root@example.com") != ""
