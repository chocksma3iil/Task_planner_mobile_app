# Task Planner — Architecture Proposal

This document describes the direction to evaluate, not a final approved design.

> **Amended 2026-10-21:** the approved build now uses a FastAPI + MySQL
> backend instead of local SQLite/Drift, and the app is online-only. See
> `docs/decisions/2026-10-21-fastapi-mysql-backend.md`. Sections below are
> updated where they changed.

## 1. Business Direction

Build a mobile task planner with server-backed accounts and online task data
(offline support is deferred; see the amendment note above).

The first release should focus on task management and daily planning.

AI planning, cloud synchronization, and external collaboration are not assumed to be part of the first release.

The brief also adds two requirements to evaluate for the first release: projects as a grouping concept, and task assignees (a person with a name and a position, where each assignee belongs to a project).

The first release also requires accounts with login and sign-up screens and three cumulative roles (admin, project owner, user). Admins create projects and assign their owners; the server stores accounts and no longer assumes a single-device database. The first registered account on a fresh database becomes the admin (bootstrap).

## 2. Proposed Architecture Style

A modular monolithic Flutter application organized by layer (models, screens, services, widgets, providers), plus one small FastAPI service. The layer-first layout was approved on 2026-10-21 after the initial feature-first build.

Avoid microservices and unnecessary backend infrastructure.

## 3. Proposed Technology Candidates

- Flutter and Dart for the mobile application.
- Riverpod for state management and dependency injection.
- FastAPI (Python) for the backend REST API.
- MySQL for server-side persistence (SQLAlchemy + PyMySQL; Alembic for migrations).
- go_router for navigation.
- Flutter testing tools for unit, widget, and integration tests; pytest for the backend.

These are proposals requiring review, not approved dependencies. The approved
build (2026-10-21) follows this list; SQLite/Drift was replaced by the backend.

## 4. Proposed Component Boundaries

**Presentation**
Displays screens, forms, navigation, and UI state.

**Application and Business Logic**
Coordinates task operations and applies business rules.

**Domain**
Defines task concepts and rules independently of UI and database details.

**Data**
Calls the HTTP API through a single client (`lib/services/api_client.dart`):
bearer token, JSON models, and error mapping. The client is the only place the
app talks to the network. Feature routes live under `/api/v1`.

**Integrations**
Contains optional platform integrations, such as local notifications.

**Auth**
Verifies login credentials against the backend, holds the session token, and relies on server-enforced role checks (admin, project owner, user). Logging out clears the token.

**Notifications**
Sends email notifications for key events (proposed: new sign-up, approval or rejection, task assignment) through the device's email app. Proposed, not approved; needs connectivity when sending.

**Future AI Integration**
If approved later, AI may propose task plans through controlled application operations. It must not bypass business rules or modify stored tasks without appropriate user authorization.

## 5. Proposed Project Organization

- `lib/app/` — application entry, `MaterialApp.router`, and the GoRouter.
- `lib/core/` — theme, formatters, positions, and pure UX rules.
- `lib/models/` — JSON models (`Account`, `Project`, `Task`).
- `lib/providers/` — Riverpod services, sessions, streams, theme preference.
- `lib/screens/` — login, sign-up, home shell, and role tabs.
- `lib/services/` — API client, data-sync signal, and domain services.
- `lib/widgets/` — shared, task, member, project, and settings widgets.
- `backend/app/` — FastAPI packages: `api/`, `core/`, `models/`, `schemas/`,
  `services/`; `backend/tests/` and `backend/alembic/`.
- `test/` — Flutter unit and widget tests.
- `docs/` — requirements, architecture, decisions, and development plans.

Create only the folders needed for approved features.

## 6. Constraints

- Task data requires reaching the API (online-only since 2026-10-21; offline support would need a sync layer, deferred).
- UI code must not access the network or database directly; it goes through application services.
- Business rules must be testable independently of the UI.
- Keep dependencies and abstractions to a minimum.
- Accounts and credentials are stored server-side; passwords are bcrypt hashes, never plain text. The server enforces roles, approval, and assignment rules. No cloud auth provider without approval.
- Email notifications go through the device's email app and need connectivity when sending; automatic sending without user action would need an email service (deferred).

## 7. Open Decisions

- Final first-release features. Built: task create/edit/delete/complete/reopen, projects, members, assignment, server accounts. Still open: notification scope, backup/restore, daily vs weekly views.
- Task statuses, priorities, and due-date behavior — **resolved 2026-10-21:** `todo`/`completed`, `low`/`medium`/`high`, optional due date.
- Categories versus projects — projects are now implemented as a concrete entity; adding categories remains open.
- Whether the assignee is optional or required on a task — **resolved:** optional (whole-project assignment when no person is set).
- How the very first admin account is created on a fresh install — **resolved 2026-10-21:** the first registered account becomes admin.
- Password recovery or reset without a backend.
- Hosting and deployment (HTTPS, CORS allow-list, backups) — deferred by the user.
- Automatic email sending without user action (needs a backend; deferred).
- Exact tab structure per role (proposed in the access-control skill).
- Assigning a task to a project other than the task's own project is not supported in this draft; revisit only if cross-team assignment is needed.
- What happens to tasks assigned to a removed member.
- Local notifications.
- Export and restore.
- Exact dependency choices — **resolved 2026-10-21** (approved stack; see the decision records).
- Code organization — **resolved 2026-10-21:** layer-first Flutter layout and the backend package split described in §5.

## 8. Approved Data Model (Implemented)

Three tables, reflecting the brief's assignment requirements. A task has at most one assignee: either its project as a whole or one person from that project — never both.

**1. projects**

| Column | Purpose |
|---|---|
| id | Primary key |
| name | Project name |
| description | Optional description |
| status | Active or archived |
| owner_id | Project owner, assigned by an admin |
| created_at | Creation timestamp |

**2. assignees**

| Column | Purpose |
|---|---|
| id | Primary key |
| name | Person's name |
| position | Job title, e.g. Developer (display only; unrelated to the access `role`) |
| project_id | Project this person belongs to (admins act across all projects regardless) |
| email | Unique login identifier |
| password_hash | Salted password hash |
| role | admin, project_owner, or user (cumulative; unrelated to `position`) |
| status | pending (self-registered, awaiting owner confirmation) or active |
| approved_by | Owner who confirmed the account (null until confirmed) |
| created_at | Creation timestamp |

**3. tasks**

| Column | Purpose |
|---|---|
| id | Primary key |
| title | Required task title |
| description | Optional details |
| status | To do or completed |
| priority | Low, medium, or high |
| due_date | Optional deadline |
| project_id | Project the task belongs to (whole-project assignment when no person is set) |
| assignee_id | Optional assigned person; when set, must belong to the task's project |
| created_at | Creation timestamp |
| updated_at | Last modification timestamp |
| completed_at | Completion timestamp |

**Relationships**

```
Project: Mobile App
├── Assignees: Ahmed · Developer, Sara · Tester
└── Tasks: Fix login, Test release
```

**Confirmed rules**

- A task has at most one assignee target: the project or a person, never both (person assigned ⇔ `assignee_id` is set).
- A person assignee must belong to the same project as the task (`assignees.project_id` equals `tasks.project_id`). Enforced by the server; mirrored in the app for UX.
- Each person belongs to exactly one project (Option A).

**Access rules**

- Only an admin creates projects and assigns project owners; only an admin creates owner/admin accounts or changes roles.
- Admins and project owners create active users directly. Self-registered users start as pending and cannot log in until the relevant project owner (or an admin) confirms them; confirmation records the owner's id in `approved_by`.
- Admins act across all projects; project owners and users act within their own project.

## 9. Approval Status

**APPROVED FOR IMPLEMENTATION (2026-10-11).** Milestone 1 built in `task_planner/` per `IMPLEMENTATION_PLAN.md`.

**AMENDED (2026-10-21):** the approved build replaces local SQLite/Drift with a FastAPI + MySQL backend (online-only); see `docs/decisions/2026-10-21-fastapi-mysql-backend.md`.

**AMENDED AGAIN (2026-10-21):** layer-first Flutter layout, versioned
`/api/v1` routes, input validation, UTC timestamps, and task editing; see
`docs/decisions/2026-10-21-structure-and-api-hardening.md`. Milestones 1–4 are
built.

New changes still follow Inspect → Propose → Approve → Implement → Verify.
