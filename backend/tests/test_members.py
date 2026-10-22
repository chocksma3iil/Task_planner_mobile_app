"""Members: creation scoping, owner confirmation, role changes, visibility."""
from helpers import auth_headers, bootstrap, sign_up


def _owner_in_project(client, headers, project, email, name):
    """Create + confirm a member, then make them owner of the project."""
    member = sign_up(client, email, name=name, project_id=project["id"])
    client.post(f"/api/v1/members/{member['id']}/confirm", headers=headers)
    client.post(
        f"/api/v1/projects/{project['id']}/assign-owner",
        json={"owner_id": member["id"]},
        headers=headers,
    )
    return auth_headers(client, email)


def test_owner_creates_users_only_in_own_project(client):
    _, headers, project_a = bootstrap(client, "Alpha")
    response = client.post(
        "/api/v1/projects", json={"name": "Beta"}, headers=headers
    )
    project_b = response.json()
    owner_headers = _owner_in_project(
        client, headers, project_a, "olive@example.com", "Olive"
    )

    # Allowed: plain user in the owner's own project.
    created = client.post(
        "/api/v1/members",
        json={
            "name": "Bob",
            "email": "bob@example.com",
            "password": "password123",
            "project_id": project_a["id"],
        },
        headers=owner_headers,
    )
    assert created.status_code == 201
    assert created.json()["status"] == "active"

    # Denied: another project.
    wrong_project = client.post(
        "/api/v1/members",
        json={
            "name": "Eve",
            "email": "eve@example.com",
            "password": "password123",
            "project_id": project_b["id"],
        },
        headers=owner_headers,
    )
    assert wrong_project.status_code == 400
    assert wrong_project.json()["detail"] == (
        "Owners can only add plain users to their project."
    )

    # Denied: elevated role.
    elevated = client.post(
        "/api/v1/members",
        json={
            "name": "Mallory",
            "email": "mallory@example.com",
            "password": "password123",
            "project_id": project_a["id"],
            "role": "project_owner",
        },
        headers=owner_headers,
    )
    assert elevated.status_code == 400


def test_owner_confirms_pending_only_in_own_project(client):
    _, headers, project_a = bootstrap(client, "Alpha")
    client.post("/api/v1/projects", json={"name": "Beta"}, headers=headers)
    beta = client.get("/api/v1/projects").json()[-1]
    owner_headers = _owner_in_project(
        client, headers, project_a, "olive@example.com", "Olive"
    )

    own_pending = sign_up(client, "sara@example.com", name="Sara",
                          project_id=project_a["id"])
    ok = client.post(f"/api/v1/members/{own_pending['id']}/confirm",
                     headers=owner_headers)
    assert ok.status_code == 200
    assert ok.json()["status"] == "active"

    other_pending = sign_up(client, "dan@example.com", name="Dan",
                            project_id=beta["id"])
    denied = client.post(f"/api/v1/members/{other_pending['id']}/confirm",
                         headers=owner_headers)
    assert denied.status_code == 400
    assert denied.json()["detail"] == (
        "You can only confirm your own project members."
    )


def test_plain_user_cannot_manage_members(client):
    _, headers, project = bootstrap(client)
    bob = sign_up(client, "bob@example.com", name="Bob", project_id=project["id"])
    client.post(f"/api/v1/members/{bob['id']}/confirm", headers=headers)
    user_headers = auth_headers(client, "bob@example.com")
    pending = sign_up(client, "sara@example.com", name="Sara",
                      project_id=project["id"])

    denied = client.post(f"/api/v1/members/{pending['id']}/confirm",
                         headers=user_headers)
    assert denied.status_code == 400
    assert denied.json()["detail"] == (
        "Only a project owner or admin can do this."
    )


def test_role_change_is_admin_only_and_validated(client):
    _, headers, project = bootstrap(client)
    member = sign_up(client, "bob@example.com", name="Bob",
                     project_id=project["id"])
    client.post(f"/api/v1/members/{member['id']}/confirm", headers=headers)
    user_headers = auth_headers(client, "bob@example.com")

    denied = client.post(
        f"/api/v1/members/{member['id']}/role", json={"role": "admin"},
        headers=user_headers,
    )
    assert denied.status_code == 400
    assert denied.json()["detail"] == "Only an admin can do this."

    invalid = client.post(
        f"/api/v1/members/{member['id']}/role", json={"role": "wizard"},
        headers=headers,
    )
    assert invalid.status_code == 422
    assert "role" in invalid.json()["detail"]

    promoted = client.post(
        f"/api/v1/members/{member['id']}/role", json={"role": "project_owner"},
        headers=headers,
    )
    assert promoted.status_code == 200
    assert promoted.json()["role"] == "project_owner"


def test_member_list_scoping(client):
    _, headers, project = bootstrap(client)
    sign_up(client, "bob@example.com", name="Bob", project_id=project["id"])
    owner_headers = _owner_in_project(
        client, headers, project, "olive@example.com", "Olive"
    )
    # Admin-created account without a project.
    client.post(
        "/api/v1/members",
        json={"name": "Orphan", "email": "orphan@example.com", "password": "password123"},
        headers=headers,
    )

    admin_view = client.get("/api/v1/members", headers=headers)
    assert {a["email"] for a in admin_view.json()} >= {
        "root@example.com",
        "bob@example.com",
        "olive@example.com",
        "orphan@example.com",
    }

    owner_view = client.get("/api/v1/members", headers=owner_headers)
    # Admin (project_id null) and the orphan fall outside the owner's roster.
    assert {a["email"] for a in owner_view.json()} == {
        "bob@example.com",
        "olive@example.com",
    }

    orphan_headers = auth_headers(client, "orphan@example.com")
    denied = client.get("/api/v1/members", headers=orphan_headers)
    assert denied.status_code == 400
    assert denied.json()["detail"] == (
        "Account has not been assigned to a project."
    )
