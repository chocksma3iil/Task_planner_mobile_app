"""Projects: admin-only creation and owner assignment."""
from helpers import auth_headers, bootstrap, sign_up


def test_project_list_is_public(client):
    bootstrap(client)
    response = client.get("/api/v1/projects")  # no token â€” sign-up screen needs this
    assert response.status_code == 200
    assert [p["name"] for p in response.json()] == ["Alpha"]


def test_only_admin_creates_projects(client):
    _, admin_headers, project = bootstrap(client)
    bob = sign_up(client, "bob@example.com", name="Bob", project_id=project["id"])
    client.post(f"/api/v1/members/{bob['id']}/confirm", headers=admin_headers)
    user_headers = auth_headers(client, "bob@example.com")

    denied = client.post("/api/v1/projects", json={"name": "Nope"}, headers=user_headers)
    assert denied.status_code == 400
    assert denied.json()["detail"] == "Only an admin can do this."

    allowed = client.post(
        "/api/v1/projects", json={"name": "Beta"}, headers=admin_headers
    )
    assert allowed.status_code == 201


def test_assign_owner_moves_account_into_project(client):
    _, headers, project = bootstrap(client)
    member = sign_up(client, "olive@example.com", name="Olive",
                     project_id=project["id"])
    client.post(f"/api/v1/members/{member['id']}/confirm", headers=headers)

    response = client.post(
        f"/api/v1/projects/{project['id']}/assign-owner",
        json={"owner_id": member["id"]},
        headers=headers,
    )
    assert response.status_code == 200
    assert response.json()["owner_id"] == member["id"]

    me = client.get("/api/v1/auth/me", headers=auth_headers(client, "olive@example.com"))
    assert me.json()["role"] == "project_owner"
    assert me.json()["project_id"] == project["id"]


def test_assign_owner_requires_active_account(client):
    _, headers, project = bootstrap(client)
    pending = sign_up(client, "carol@example.com", name="Carol",
                      project_id=project["id"])
    response = client.post(
        f"/api/v1/projects/{project['id']}/assign-owner",
        json={"owner_id": pending["id"]},
        headers=headers,
    )
    assert response.status_code == 400
    assert response.json()["detail"] == "The owner account must be active."
