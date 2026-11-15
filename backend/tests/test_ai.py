"""AI layer (v2.0): consent gating + mock provider proposals."""
from helpers import auth_headers, bootstrap, sign_up

from app.services.ai_service import _extract_json


def _enable_ai(client, headers, project):
    """Flip ai_opt_in on a project (admin only)."""
    response = client.patch(
        f"/api/v1/projects/{project['id']}/ai-opt-in",
        json={"ai_opt_in": True},
        headers=headers,
    )
    assert response.status_code == 200, response.text


def _create_task(client, headers, project_id, title):
    response = client.post(
        "/api/v1/tasks",
        json={"project_id": project_id, "title": title},
        headers=headers,
    )
    assert response.status_code == 201, response.text
    return response.json()


def test_ai_endpoints_403_without_consent(client):
    """AI is disabled by default: every AI endpoint returns 403."""
    _, headers, project = bootstrap(client)
    task = _create_task(client, headers, project["id"], "Existing task")
    calls = [
        ("POST", f"/api/v1/ai/weekly-plan?project_id={project['id']}", None),
        ("POST", f"/api/v1/ai/decompose?task_id={task['id']}", None),
        ("POST", f"/api/v1/ai/briefing?project_id={project['id']}", None),
        ("POST", f"/api/v1/ai/capture", {"project_id": project["id"], "text": "hello"}),
    ]
    for method, path, body in calls:
        response = getattr(client, method.lower())(path, json=body, headers=headers)
        assert response.status_code == 403, f"{path}: {response.text}"


def test_ai_weekly_plan_returns_proposal(client):
    """With ai_opt_in, weekly-plan returns a mock proposal (no write)."""
    _, headers, project = bootstrap(client)
    _enable_ai(client, headers, project)

    response = client.post(
        f"/api/v1/ai/weekly-plan?project_id={project['id']}", headers=headers
    )
    assert response.status_code == 200, response.text
    data = response.json()
    assert "title" in data
    assert "tasks" in data
    assert isinstance(data["tasks"], list)
    assert len(data["tasks"]) > 0, "the AI must propose at least one task"
    assert all(task["title"] for task in data["tasks"])


def test_ai_decompose_returns_proposal(client):
    _, headers, project = bootstrap(client)
    _enable_ai(client, headers, project)
    task = _create_task(client, headers, project["id"], "Write spec")

    response = client.post(
        f"/api/v1/ai/decompose?task_id={task['id']}", headers=headers
    )
    assert response.status_code == 200, response.text
    data = response.json()
    assert "subtasks" in data
    assert isinstance(data["subtasks"], list)
    assert len(data["subtasks"]) > 0, "the AI must propose at least one subtask"
    assert all(item["title"] for item in data["subtasks"])


def test_ai_briefing_returns_text(client):
    _, headers, project = bootstrap(client)
    _enable_ai(client, headers, project)

    response = client.post(
        f"/api/v1/ai/briefing?project_id={project['id']}", headers=headers
    )
    assert response.status_code == 200, response.text
    data = response.json()
    assert "briefing" in data
    assert isinstance(data["briefing"], str)
    assert len(data["briefing"]) > 0


def test_ai_capture_returns_task_proposal(client):
    _, headers, project = bootstrap(client)
    _enable_ai(client, headers, project)

    response = client.post(
        "/api/v1/ai/capture",
        json={"project_id": project["id"], "text": "Review login page tomorrow"},
        headers=headers,
    )
    assert response.status_code == 200, response.text
    data = response.json()
    assert "title" in data
    assert data["title"], "the AI must return a usable task title"
    assert "priority" in data
    assert "status" in data


def test_ai_403_for_non_member(client):
    """A user from another project cannot use AI on this project."""
    _, admin_headers, project_a = bootstrap(client)
    _enable_ai(client, admin_headers, project_a)

    # Bob in a different project.
    beta = client.post(
        "/api/v1/projects", json={"name": "Beta"}, headers=admin_headers
    ).json()
    bob = sign_up(client, "bob@example.com", name="Bob", project_id=beta["id"])
    client.post(f"/api/v1/members/{bob['id']}/confirm", headers=admin_headers)
    bob_headers = auth_headers(client, "bob@example.com")

    response = client.post(
        f"/api/v1/ai/weekly-plan?project_id={project_a['id']}", headers=bob_headers
    )
    assert response.status_code == 403, response.text


def test_ai_does_not_write_tasks(client):
    """AI proposal must not create tasks in the database."""
    _, headers, project = bootstrap(client)
    _enable_ai(client, headers, project)
    before = client.get(
        f"/api/v1/tasks?project_id={project['id']}", headers=headers
    ).json()["total"]

    client.post(
        f"/api/v1/ai/weekly-plan?project_id={project['id']}", headers=headers
    )

    after = client.get(
        f"/api/v1/tasks?project_id={project['id']}", headers=headers
    ).json()["total"]
    assert after == before


def test_extract_json_accepts_fences_and_prose():
    """Real models wrap JSON in ```json fences or add a sentence around it."""
    fenced = '```json\n{"title": "Weekly Plan", "tasks": []}\n```'
    prose = 'Here is the plan:\n{"title": "Weekly Plan", "tasks": []}\nDone.'
    assert _extract_json(fenced) == {"title": "Weekly Plan", "tasks": []}
    assert _extract_json(prose) == {"title": "Weekly Plan", "tasks": []}
    assert _extract_json("no json here") is None
