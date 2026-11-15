"""Extended roles (viewer, team lead), password reset, and AI proposals."""
from helpers import auth_headers, bootstrap, login_token, sign_up


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


def test_viewer_is_read_only(client):
    _, headers, project = bootstrap(client)
    _member(client, headers, project["id"], "viewer@example.com", "viewer")
    viewer_headers = auth_headers(client, "viewer@example.com")

    assert client.get(
        f"/api/v1/tasks?project_id={project['id']}", headers=viewer_headers
    ).status_code == 200
    assert client.get(
        "/api/v1/members", headers=viewer_headers
    ).status_code == 200

    denied = client.post(
        "/api/v1/tasks",
        json={"project_id": project["id"], "title": "Nope"},
        headers=viewer_headers,
    )
    assert denied.status_code == 400
    assert denied.json()["detail"] == "Viewers cannot make changes."

    bulk = client.post(
        "/api/v1/tasks/bulk/complete",
        json={"task_ids": [1]},
        headers=viewer_headers,
    )
    assert bulk.status_code == 400


def test_team_lead_confirms_and_adds_members(client):
    _, headers, project = bootstrap(client)
    lead = _member(client, headers, project["id"], "lead@example.com",
                   "team_lead")
    pending = sign_up(
        client, "new@example.com", name="New", project_id=project["id"]
    )
    lead_headers = auth_headers(client, "lead@example.com")

    confirmed = client.post(
        f"/api/v1/members/{pending['id']}/confirm", headers=lead_headers
    )
    assert confirmed.status_code == 200
    assert confirmed.json()["status"] == "active"

    created = client.post(
        "/api/v1/members",
        json={
            "name": "Second",
            "email": "second@example.com",
            "password": "password123",
            "project_id": project["id"],
        },
        headers=lead_headers,
    )
    assert created.status_code == 201

    escalation = client.post(
        "/api/v1/members",
        json={
            "name": "Boss",
            "email": "boss@example.com",
            "password": "password123",
            "project_id": project["id"],
            "role": "admin",
        },
        headers=lead_headers,
    )
    assert escalation.status_code == 400

    role_change = client.post(
        f"/api/v1/members/{lead['id']}/role",
        json={"role": "user"},
        headers=lead_headers,
    )
    assert role_change.status_code == 400


def test_password_reset_code_is_single_use_and_revokes_tokens(client):
    bootstrap(client)
    old_headers = auth_headers(client, "root@example.com")

    request = client.post(
        "/api/v1/auth/forgot-password",
        json={"email": "root@example.com"},
    )
    assert request.status_code == 200
    code = request.json()["dev_code"]

    unknown = client.post(
        "/api/v1/auth/forgot-password",
        json={"email": "ghost@example.com"},
    )
    assert unknown.status_code == 200
    assert unknown.json().get("dev_code") is None

    wrong = client.post(
        "/api/v1/auth/reset-password",
        json={
            "email": "root@example.com",
            "code": "000000",
            "new_password": "brandnew123",
        },
    )
    assert wrong.status_code == 400

    reset = client.post(
        "/api/v1/auth/reset-password",
        json={
            "email": "root@example.com",
            "code": code,
            "new_password": "brandnew123",
        },
    )
    assert reset.status_code == 200
    assert client.get(
        "/api/v1/auth/me", headers=old_headers
    ).status_code == 401

    new_token = login_token(client, "root@example.com", "brandnew123")
    assert client.get(
        "/api/v1/auth/me",
        headers={"Authorization": f"Bearer {new_token}"},
    ).status_code == 200

    reused = client.post(
        "/api/v1/auth/reset-password",
        json={
            "email": "root@example.com",
            "code": code,
            "new_password": "another123",
        },
    )
    assert reused.status_code == 400


def test_ai_endpoints_honor_project_opt_in(client):
    _, headers, project = bootstrap(client)
    task = client.post(
        "/api/v1/tasks",
        json={"project_id": project["id"], "title": "AI target"},
        headers=headers,
    ).json()

    disabled = client.post(
        f"/api/v1/ai/weekly-plan?project_id={project['id']}", headers=headers
    )
    assert disabled.status_code == 400
    assert disabled.json()["detail"] == "AI is disabled for this project."

    enabled = client.patch(
        f"/api/v1/projects/{project['id']}/ai-opt-in",
        json={"ai_opt_in": True},
        headers=headers,
    )
    assert enabled.status_code == 200
    assert enabled.json()["ai_opt_in"] is True

    plan = client.post(
        f"/api/v1/ai/weekly-plan?project_id={project['id']}", headers=headers
    )
    assert plan.status_code == 200
    assert plan.json()["tasks"][0]["title"] == "AI target"

    decomposed = client.post(
        f"/api/v1/ai/decompose?task_id={task['id']}", headers=headers
    )
    assert decomposed.status_code == 200
    assert len(decomposed.json()["subtasks"]) == 3

    briefing = client.post(
        f"/api/v1/ai/briefing?project_id={project['id']}", headers=headers
    )
    assert briefing.status_code == 200
    assert "AI target" in briefing.json()["briefing"] or briefing.json()[
        "briefing"
    ].startswith("Alpha")

    captured = client.post(
        "/api/v1/ai/capture",
        json={"project_id": project["id"], "text": "Call the supplier"},
        headers=headers,
    )
    assert captured.status_code == 200
    assert captured.json()["title"] == "Call the supplier"
