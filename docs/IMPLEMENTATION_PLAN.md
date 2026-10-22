# Implementation Plan

**Status: Milestones 1–4 built. Next work is unapproved (see the end of this file).**

## Milestone 1 — Foundation + auth (done)

- Scaffold `task_planner/` (Flutter 3.47, Dart 3.13).
- Dependencies: flutter_riverpod, drift (+ drift_dev, build_runner), sqlite3_flutter_libs, go_router, crypto, path_provider.
- Drift tables `projects` / `assignees` / `tasks`; services enforce assignment, same-project, pending-blocked, and role rules.
- UI order: login → sign-up → role tabs (Projects for admin; Members and Tasks scoped per role).
- Verify: `flutter analyze` clean, `flutter test` 20/20.
- Layout: `task_planner/lib/{app,core,features/auth,features/tasks}`, `test/`.

## Milestone 2 — Planner views (done 2026-10-12)

- All / Today / Upcoming / Overdue filter chips in the Tasks tab (no new tab, no schema change).
- Pure classifiers `isOverdue` / `isDueToday` / `isUpcoming` in `lib/core/rules.dart`; completed tasks show under All only.
- `flutter analyze` clean, `flutter test` green (25 tests).

## Milestone 3 — FastAPI + MySQL backend (done 2026-10-21)

Approved: `docs/decisions/2026-10-21-fastapi-mysql-backend.md`.

- `backend/`: FastAPI app (auth, projects, members, tasks, health), MySQL via
  SQLAlchemy + PyMySQL, bcrypt password hashes, JWT sessions
  (`PyJWT`), Alembic migration scaffolding, 22 pytest tests against a real
  MySQL test database.
- Server enforces roles, membership approval, and the project-or-person task
  assignment rule. First account on a fresh database becomes admin.
- Flutter app is now online-only: Drift/SQLite, `crypto`, `path_provider`,
  `drift_dev`, and `build_runner` removed; added `http` and
  `shared_preferences`. Services keep their public signatures but call the API;
  theme preference moved to `shared_preferences`.
- New `core/api_client.dart` (bearer token, `StateError`/`ArgumentError`
  mapping, offline message), `core/models.dart`, `core/data_sync.dart`
  (mutation ping + in-place stream refresh).
- Verify: `flutter analyze` clean, `flutter test` 28/28; backend
  `pytest` 22/22; live smoke test against MySQL (signup/admin, login, create
  project/task, list tasks) passed.
- Removed: `core/database.dart`, `database.g.dart`, `core/security.dart`,
  `tool/seed_users.dart`, and the Drift-based tests.

> The `core/` and `features/` paths above are historical; Milestone 4 moved
> them into the layer-first tree under `lib/`.

## Milestone 4 — Cleanup, layer-first layout, API hardening, edit task (done 2026-10-21)

Approved in conversation ("approved all") after a repository review. No new
runtime dependencies.

- Repository cleanup: removed 27 generic skill folders (kept the six project
  skills), deleted IDE/build/cache artifacts, expanded `.gitignore`, corrected
  stale setup docs (backend driver and credential placeholders, brief
  amendment).
- Flutter restructured into layers:
  `lib/{app,core,models,providers,screens,services,widgets}`. `Assignee` was
  renamed to `Account` (JSON unchanged); the router moved to `lib/app/router.dart`;
  shared/task/member/project widgets were split out of the old feature tree.
- Backend restructured into `app/{api,core,models,schemas,services}` packages
  with a versioned `/api/v1` router (`/health` stays unversioned). Routers are
  thin HTTP adapters; services hold the rules.
- Hardening: email normalization, password 8–72 characters, non-empty
  names/titles, role/priority enums, UTC timestamp serialization,
  environment-driven CORS/secret, and dev-only `create_all` in the lifespan.
- Edit task (required MVP feature): `PATCH /api/v1/tasks/{id}` supports partial
  fields and re-validates assignees; Flutter gained `updateTask` and a
  tap-to-edit dialog in the shared task list.
- Verify: backend `pytest` 32/32; Flutter `flutter analyze` clean and
  `flutter test` 29/29.

## Developer onboarding (done 2026-10-22)

Approved in conversation ("lets begin this...") after an inspection proposal.
No application behavior, API contract, or schema changed.

- Added `compose.yaml` for MySQL 8, the FastAPI API, and phpMyAdmin; MySQL has
  no host port, API/phpMyAdmin bind to loopback, and data persists in a named
  volume.
- Added the backend Dockerfile, a `.dockerignore`, and a MySQL init script that
  creates `task_planner_test`.
- Compose runs `alembic upgrade head`; root `.env.example` holds placeholder
  local credentials and ports. `pymysql[rsa]` was added for MySQL 8 auth.
- Added the root README, `.vscode/extensions.json`, Android `INTERNET` and
  debug-cleartext configuration, and the
  `2026-10-22-local-development-onboarding.md` decision record.
- Verify: `docker compose config`; MySQL/API healthy; API `/health` 200;
  Alembic at `0001_initial`; phpMyAdmin login; backend pytest 32 passed;
  `flutter analyze` clean; `flutter test` 29 passed; Windows debug build
  launched.

## Next (not approved)

- Notifications, backup/restore.
- Deployment: hosting choice, HTTPS, CORS allow-list, backups.
- Shared development MySQL/phpMyAdmin provisioning and access policy.
