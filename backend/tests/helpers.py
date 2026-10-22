"""Small request helpers shared by the API tests."""


def sign_up(
    client,
    email,
    name="Tester",
    password="password123",
    project_id=None,
    position=None,
):
    body = {"name": name, "email": email, "password": password}
    if position is not None:
        body["position"] = position
    if project_id is not None:
        body["project_id"] = project_id
    response = client.post("/api/v1/auth/signup", json=body)
    assert response.status_code == 201, response.text
    return response.json()


def login_token(client, email, password="password123"):
    response = client.post(
        "/api/v1/auth/login", json={"email": email, "password": password}
    )
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


def auth_headers(client, email, password="password123"):
    return {"Authorization": f"Bearer {login_token(client, email, password)}"}


def bootstrap(client, project_name="Alpha"):
    """First account (admin), one project, admin auth headers.

    Returns (admin_account, headers, project).
    """
    admin = sign_up(client, "root@example.com", name="Root Admin")
    headers = auth_headers(client, "root@example.com")
    response = client.post(
        "/api/v1/projects",
        json={"name": project_name},
        headers=headers,
    )
    assert response.status_code == 201, response.text
    return admin, headers, response.json()
