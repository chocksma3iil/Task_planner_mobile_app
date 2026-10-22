# Task Planner API

FastAPI + MySQL backend for the Task Planner Flutter app. Serves
accounts/auth, projects, members (with join approval), and tasks, enforcing
the same business rules the mobile app shows (roles, one-project-per-person,
project-or-person assignment).

## Prerequisites

- Docker Desktop or Docker Engine with Compose v2 (recommended), or
- Python 3.11+ (tested on 3.13) and MySQL 8.x for a host-run backend.

The full-stack quickstart lives in [`../README.md`](../README.md).

## Run with Docker Compose (recommended)

From the repository root:

```powershell
# skip this copy if .env already exists
Copy-Item .env.example .env
# edit .env, then:
docker compose up --build -d
docker compose ps
```

The `api` container waits for MySQL to become healthy, runs
`alembic upgrade head`, and starts Uvicorn on `127.0.0.1:8000`. The `mysql`
service uses the internal hostname `mysql`; it is not published to the host.
phpMyAdmin is available at `http://127.0.0.1:8080`.

The Docker flow does not depend on `backend/.env`. Compose passes the database
URL and secret explicitly from the root `.env`, and those environment values
take precedence inside the container.

## Host-run alternative

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
# skip this copy if backend/.env already exists
Copy-Item .env.example .env
# edit backend/.env with your local MySQL connection
alembic upgrade head
uvicorn app.main:app --reload
```

- API docs (Swagger): http://127.0.0.1:8000/docs
- Health check: `GET /health` (unversioned)
- Feature routes: `http://127.0.0.1:8000/api/v1/...`

## Configuration

`backend/.env` is for host-run development. It is Git-ignored; copy
`.env.example` and fill in:

```
DATABASE_URL=mysql+pymysql://USER:PASSWORD@127.0.0.1:3306/task_planner
TEST_DATABASE_URL=mysql+pymysql://USER:PASSWORD@127.0.0.1:3306/task_planner_test
SECRET_KEY=change-me-to-a-long-random-string-at-least-32-bytes
TOKEN_TTL_DAYS=30
ENVIRONMENT=development
CORS_ORIGINS=*
CREATE_SCHEMA_ON_STARTUP=true
```

`SECRET_KEY` has a development fallback, but `ENVIRONMENT=production` refuses
to start with it. `CREATE_SCHEMA_ON_STARTUP` defaults to true outside
production; Compose sets it to false and uses Alembic instead.

For a shared database, set `DATABASE_URL` to the shared host and set
`CREATE_SCHEMA_ON_STARTUP=false`. Never point `TEST_DATABASE_URL` at a shared
database: the test suite truncates tables. Do not run migrations against
shared data without explicit authorization.

## Structure

```
app/
  main.py             # App factory-level setup: lifespan, CORS, error handlers,
                      # /health, and the versioned router.
  api/
    deps.py           # DbSession / CurrentUser dependencies (bearer token).
    router.py         # /api/v1 prefix + feature routers.
    routers/          # auth.py, projects.py, members.py, tasks.py (thin HTTP).
  core/
    config.py         # .env configuration (DB, secret, CORS, environment).
    database.py       # Engine, session factory, Base, get_db.
    errors.py         # ApiError hierarchy → HTTP detail contract.
    rules.py          # Roles, statuses, priorities, access/assignment rules.
    security.py       # bcrypt hashing, JWT create/decode.
    time.py           # Naive-UTC helper for model defaults and edits.
  models/             # SQLAlchemy tables: project, account (assignees), task.
  schemas/            # Pydantic request/response models + validation.
  services/           # Business logic; routers stay thin.
tests/                # pytest API tests against the MySQL test database.
Dockerfile            # API image used by the root Compose stack.
docker/mysql-init/    # creates task_planner_test on first volume initialization.
alembic/              # Migration scaffolding and 0001_initial.
```

Input validation (HTTP 422 with a readable single-line `detail`):

- emails are trimmed, lowercased, and must contain a local part and domain;
- passwords are 8–72 characters (bcrypt limit);
- names and titles are trimmed and cannot be empty;
- roles are `admin`, `project_owner`, or `user`;
- priorities are `low`, `medium`, or `high`.

Timestamps are serialized as UTC ISO-8601 (`+00:00`).

## Endpoint summary

All paths below are relative to `/api/v1` unless noted.

| Method | Path | Who | Notes |
|---|---|---|---|
| POST | `/auth/signup` | anyone | First account on a fresh DB becomes admin; everyone else joins a project as pending. |
| POST | `/auth/login` | active accounts | Returns `{access_token, account}`. Pending accounts are rejected. |
| GET | `/auth/me` | logged in | Current account row. |
| GET | `/projects` | anyone (needed for signup) | Full project list. |
| POST | `/projects` | admin | Create project. |
| POST | `/projects/{id}/assign-owner` | admin | Set the project owner (must be active). |
| GET | `/members` | logged in, role-scoped | Admin: all; owner/user: own project only. |
| POST | `/members` | admin, owner | Create active member (role restricted per caller). |
| POST | `/members/{id}/confirm` | owner of that project, admin | Approve a pending join. |
| POST | `/members/{id}/role` | admin | Change a member's role. |
| GET | `/tasks?project_id=` or `?assignee_id=` | logged in, scoped | Exactly one filter required. |
| POST | `/tasks` | project members | Assignment rule enforced server-side. |
| PATCH | `/tasks/{id}` | project members | Partial edit: title, description, priority, due date, assignee. |
| PATCH | `/tasks/{id}/complete` / `/reopen` | project members | Status transitions. |
| DELETE | `/tasks/{id}` | project members | |
| GET | `/health` | anyone | Unversioned health check. |

Error contract: plain-string `detail` for auth/permission/business/validation
errors; structured `detail: {code, message}` for assignment validation
(`invalid_assignment`) and a missing signup project (`project_required`).

## Tests

With Compose, the API image already contains the test dependencies and the
MySQL init script has created the test database:

```powershell
docker compose exec api python -m pytest tests -q
```

For a host-run backend, activate the virtual environment and run:

```powershell
.\.venv\Scripts\Activate.ps1
python -m pytest tests -q
```

Tests use `TEST_DATABASE_URL` and truncate tables between tests. Never point it
at a shared database. The suite covers auth/bootstrap, project and member
scoping, task rules, task editing, input validation, and the versioned routing
surface.

## Migrations

Compose runs `alembic upgrade head` before starting Uvicorn. For a host-run
backend:

```powershell
alembic upgrade head
```

`create_all` still runs on startup when `CREATE_SCHEMA_ON_STARTUP=true`, which
is the development default for a host-run backend. Go through Alembic for new
schema changes and for any environment where data must be preserved. Do not
run migrations against shared data without authorization.

## Database objects

Three tables (snake_case JSON): `projects`, `assignees`, `tasks`.
`projects.owner_id` and `assignees.approved_by` are plain integer columns (no
SQL foreign keys) — documented in `app/models/`. The Python model class is
still named `Assignee`, but the Flutter app presents the same rows as
`Account`.

## Related docs

- `../README.md` — full local development quickstart.
- `../docs/decisions/2026-10-22-local-development-onboarding.md` — Docker
  Compose, ports, and shared-database rules.
- `../docs/decisions/2026-10-21-fastapi-mysql-backend.md` — why this stack.
- `../docs/decisions/2026-10-21-structure-and-api-hardening.md` — package
  layout, `/api/v1`, validation, and task editing.
- `../task_planner/README.md` — Flutter app setup against this API.
