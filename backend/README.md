# Task Planner API

FastAPI + MySQL backend for the Task Planner Flutter app. Serves
accounts/auth, projects, members (with join approval), tasks, comments,
subtasks, notifications, analytics/audit data, reports, and opt-in AI
proposals, enforcing the same business rules the mobile app shows (roles,
one-project-per-person, project-or-person assignment).

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
SEED_DEMO_DATA=true
GROK_API_KEY=
GROK_API_BASE=https://api.groq.com/openai/v1
GROK_MODEL=openai/gpt-oss-120b
```

`SECRET_KEY` has a development fallback, but `ENVIRONMENT=production` refuses
to start with it. `CREATE_SCHEMA_ON_STARTUP` defaults to true outside
production; Compose sets it to false and uses Alembic instead.
`SEED_DEMO_DATA` defaults to false; Compose sets it to true for local
development, and production refuses to start with it enabled.

The `/ai/*` endpoints call Groq's OpenAI-compatible chat completions API with
`GROK_API_KEY` / `GROK_API_BASE` / `GROK_MODEL`. The feature is named "Grok",
but the provided key is a Groq key (`gsk_...`), so the base URL points at
Groq; xAI's own API needs an `xai-...` key and `https://api.x.ai/v1`. When
the key is missing or the API is unreachable, the endpoints fall back to
deterministic local proposals, so `/ai/*` never fails hard.

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
    routers/          # auth, projects, members, tasks, comments, notifications,
                      # analytics, audit, ai (thin HTTP).
  core/
    config.py         # .env configuration (DB, secret, CORS, environment).
    database.py       # Engine, session factory, Base, get_db.
    errors.py         # ApiError hierarchy → HTTP detail contract.
    rules.py          # Roles, statuses, priorities, access/assignment rules.
    security.py       # bcrypt hashing, JWT create/decode (token versioning).
    time.py           # Naive-UTC helper for model defaults and edits.
  models/             # Projects, accounts (assignees), tasks, comments,
                      # subtasks, notifications, analytics/audit events,
                      # password resets.
  schemas/            # Pydantic request/response models + validation.
  services/           # Business logic; routers stay thin. seed.py holds the
                      # idempotent development demo data.
tests/                # pytest API tests against the MySQL test database.
Dockerfile            # API image used by the root Compose stack.
docker/mysql-init/    # creates task_planner_test on first volume initialization.
alembic/              # Migrations: 0001_initial, 0002_v2_collaboration.
```

Input validation (HTTP 422 with a readable single-line `detail`):

- emails are trimmed, lowercased, and must contain a local part and domain;
- passwords are 8–72 characters (bcrypt limit);
- names and titles are trimmed and cannot be empty;
- roles are `admin`, `project_owner`, `team_lead`, `user`, or `viewer`
  (`viewer` is read-only on the server; team leads confirm and add plain users
  in their own project);
- priorities are `low`, `medium`, or `high`.

Timestamps are serialized as UTC ISO-8601 (`+00:00`).

## Endpoint summary

All paths below are relative to `/api/v1` unless noted.

| Method | Path | Who | Notes |
|---|---|---|---|
| POST | `/auth/signup` | anyone | First account on a fresh DB becomes admin; everyone else joins a project as pending. A pending sign-up notifies the project owner in-app. |
| POST | `/auth/login` | active accounts | Returns `{access_token, account}`. Pending accounts are rejected. |
| POST | `/auth/forgot-password` | anyone | Requests a single-use reset code (no email delivery yet; `dev_code` is returned outside production). |
| POST | `/auth/reset-password` | anyone | Consumes the code, updates the password, and revokes older JWTs. |
| GET | `/auth/me` | logged in | Current account row. |
| GET | `/projects?limit&offset&include_archived` | anyone (needed for signup) | Paginated `{items, total, limit, offset}`; archived rows hidden unless `include_archived=true`. |
| POST | `/projects` | admin | Create project. |
| POST | `/projects/{id}/assign-owner` | admin | Set the project owner (must be active). |
| PATCH | `/projects/{id}/archive` \| `/restore` | admin | Archive/restore a project; archived rows are hidden by default. |
| PATCH | `/projects/{id}/ai-opt-in` | admin, owner | Enable/disable AI proposals for the project. |
| GET | `/projects/{id}/export?format=csv\|pdf` | admin, project members | Raw CSV/PDF report of the project's tasks (no added dependencies). |
| GET | `/members?limit&offset` | logged in, role-scoped | Paginated envelope; admin: all, owner/team lead/user/viewer: own project only. |
| POST | `/members` | admin, owner, team lead | Create active member (non-admins may only add plain users to their project). |
| POST | `/members/{id}/confirm` | owner/team lead of that project, admin | Approve a pending join. |
| POST | `/members/{id}/role` | admin | Change a member's role. |
| GET | `/tasks?project_id=` or `?assignee_id=` (+`limit&offset`) | logged in, scoped | Exactly one filter required; paginated envelope, newest first. |
| POST | `/tasks` | project members (not viewers) | Assignment rule enforced server-side. |
| PATCH | `/tasks/{id}` | project members (not viewers) | Partial edit: title, description, priority, due date, assignee. |
| PATCH | `/tasks/{id}/complete` / `/reopen` | project members (not viewers) | Status transitions. |
| DELETE | `/tasks/{id}` | project members (not viewers) | Also removes the task's comments and subtasks. |
| POST | `/tasks/bulk/complete` \| `/reassign` \| `/delete` | project members (not viewers) | Body `{task_ids}` (+ `assignee_id`); per-task partial success. |
| GET | `/tasks/{id}/comments` | project members | `{items,total}`; soft-deleted comments are returned with `deleted_at`. |
| POST | `/tasks/{id}/comments` | project members (not viewers) | Body `{body, parent_id?}`; notifies the task assignee. |
| PATCH | `/comments/{id}` | comment author | Edit the body (`edited_at` is set). |
| DELETE | `/comments/{id}` | comment author | Soft delete. |
| GET | `/tasks/{id}/subtasks` | project members | `{items,total}` sorted by `sort_order`. |
| POST | `/tasks/{id}/subtasks` | project members (not viewers) | Create a checklist item. |
| PATCH | `/tasks/subtasks/{id}` | project members (not viewers) | Partial update: title, completed, sort_order. |
| DELETE | `/tasks/subtasks/{id}` | project members (not viewers) | Hard delete. |
| GET | `/notifications?limit&offset&unread_only` | logged in | Own inbox `{items,total,unread,limit,offset}`. |
| PATCH | `/notifications/read` | logged in | Body `{notification_ids}`; returns `{updated}` and skips foreign ids. |
| GET | `/analytics/dashboard?project_id` | project members | Counts, rates, priority mix, velocity, recent events. |
| GET | `/audit-logs?limit&offset&project_id` | admin | Paginated audit trail (project/member actions). |
| POST | `/ai/weekly-plan?project_id` \| `/briefing?project_id` | project members (not viewers) | Groq-backed proposals (deterministic local fallback if the API is unavailable); requires `ai_opt_in`. |
| POST | `/ai/decompose?task_id` | project members (not viewers) | Proposed subtasks; requires the task project's `ai_opt_in`. |
| POST | `/ai/capture` | project members (not viewers) | Body `{project_id, text}`; proposes one task. |
| GET | `/health` | anyone | Unversioned health check. |

Error contract: plain-string `detail` for auth/permission/business/validation
errors; structured `detail: {code, message}` for assignment validation
(`invalid_assignment`) and a missing signup project (`project_required`).

## Demo data (development only)

With `SEED_DEMO_DATA=true`, the API lifespan creates the demo admin, manager,
staff, project, and tasks if they are missing. Reruns never modify or duplicate
existing rows. All demo accounts use password `12345678`.

| Email | Role | Project |
|---|---|---|
| `admin@demo.local` | admin | none |
| `manager@demo.local` | project owner | Demo Project |
| `staff1@demo.local`–`staff3@demo.local` | user | Demo Project |

**Demo Project** is owned by the manager and has six tasks assigned to the
project, the manager, or staff. The seeded project has AI proposals enabled
(`ai_opt_in`) so the app's AI action works out of the box. The seeded admin
means the normal first-signup-admin bootstrap does not apply while seeding is
enabled.

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
scoping, task rules, task editing, input validation, the versioned routing
surface, the idempotent demo seed, and the v2 collaboration/insights features
(comments, subtasks, notifications, bulk actions, analytics, audit, exports,
extended roles, password reset, AI gating) plus a full app-flow E2E.

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

Nine tables (snake_case JSON): `projects`, `assignees`, `tasks`, `comments`,
`subtasks`, `notifications`, `analytics_events`, `audit_events`, and
`password_resets`. `projects.owner_id` and `assignees.approved_by` are plain
integer columns (no SQL foreign keys) — documented in `app/models/`. The
Python model class is still named `Assignee`, but the Flutter app presents the
same rows as `Account`. Migration `0002_v2_collaboration` adds the v2 tables
plus `projects.ai_opt_in` and `assignees.token_version`.

## Related docs

- `../README.md` — full local development quickstart.
- `../docs/decisions/2026-10-22-local-development-onboarding.md` — Docker
  Compose, ports, and shared-database rules.
- `../docs/decisions/2026-10-21-fastapi-mysql-backend.md` — why this stack.
- `../docs/decisions/2026-10-21-structure-and-api-hardening.md` — package
  layout, `/api/v1`, validation, and task editing.
- `../task_planner/README.md` — Flutter app setup against this API.
