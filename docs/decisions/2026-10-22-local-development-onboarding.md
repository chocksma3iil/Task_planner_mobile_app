# Decision: Local Docker development stack and onboarding

## Context

The app, API, and MySQL schema existed, but a new developer could not clone the
repository and start a working environment without installing MySQL and Python
separately, creating databases and users by hand, and configuring phpMyAdmin
outside the repository. There was no root README, no Compose file, and the
Android debug build had no local-HTTP allowance. The existing personal MySQL
database contains data and must not be reset or reused by the development
stack.

## Options considered

- **Keep host-installed MySQL/Python only.** Fewest files, but every developer
  repeats manual database and user setup, and onboarding stays error-prone.
- **Docker Compose for API, MySQL, and phpMyAdmin; local Flutter SDK (chosen).**
  One command starts the services; Flutter stays outside Docker so emulator,
  USB-device, and desktop debugging remain straightforward.
- **Full VS Code Dev Container including Flutter.** Adds Docker-in-Docker and
  device/USB complexity without removing the need for a local emulator. Not
  chosen.

## Decision

- Add a root `compose.yaml` using official `mysql:8.0`, `phpmyadmin:5`, and a
  `python:3.13-slim`-based backend image.
- Publish only the API (`127.0.0.1:8000`) and phpMyAdmin
  (`127.0.0.1:8080`) to the host. MySQL has no host port and is reachable only
  on the Compose network as `mysql`.
- Persist MySQL data in the named volume `mysql_data`. `docker compose down`
  keeps it; only `down -v` deletes it.
- Run `alembic upgrade head` in the API container before Uvicorn. The existing
  `0001_initial` migration is the schema source of truth; no schema change was
  made for this work.
- Use the root `.env` for local Compose secrets and ports. Keep
  `backend/.env` for a host-run backend and shared-database overrides. Both
  files are Git-ignored; `.env.example` files contain placeholders only.
- Create `task_planner_test` from a MySQL init script so backend tests work on a
  fresh volume. Tests still truncate only that disposable database.
- Add `pymysql[rsa]` so a fresh MySQL 8 `caching_sha2_password` connection can
  complete without relying on a cached fast-auth session.
- Keep phpMyAdmin local and loopback-only. Shared databases require credentials
  from the maintainer and must not be exposed through this Compose stack.
- Document the complete flow in the root README, keep Flutter setup in
  `task_planner/README.md`, and add recommended VS Code extensions. Do not add a
  full Dev Container.
- Add the Android `INTERNET` permission for the online-only app and allow
  cleartext HTTP only in the debug manifest for local development.

## Status

**APPROVED (2026-10-22)** by the user in conversation: "lets begin this and
build the staff i instaled docker make the modification then lets run together
and document all steps..."

## Reverses

No earlier decision. This extends the approved FastAPI + MySQL architecture
with a local development environment; application behavior and business rules
are unchanged.

## Verification

Executed on 2026-10-22 with Docker 29.9.2 and Compose v5.6.1:

- `docker compose config` succeeded.
- `docker compose up --build -d` created the network and named volume; MySQL
  and the API became healthy, phpMyAdmin started.
- The API log showed `alembic upgrade head` applying `0001_initial`.
- `GET http://127.0.0.1:8000/health` returned `200 {"status":"ok"}`;
  `/docs` returned 200.
- A SQLAlchemy `SELECT 1` from the API container returned `1`.
- MySQL contained `alembic_version`, `projects`, `assignees`, and `tasks` in
  `task_planner`; `task_planner_test` also existed.
- phpMyAdmin at `http://127.0.0.1:8080` loaded and accepted a login as
  `task_planner`; the logged-in page mentioned the `task_planner` database.
- Backend tests: **32 passed** (one Starlette/httpx deprecation warning).
- `flutter analyze`: **No issues found**.
- `flutter test`: **29 passed**.
- Windows debug build: compiled and launched; the run was terminated when the
  verification timeout ended.

Not verified: a shared development database (none exists in the repository),
Android emulator/physical-device UI interaction, and iOS local HTTP behavior.

## Still open

- Shared development MySQL/phpMyAdmin hosting, credentials, and access policy.
- The host-installed MySQL service was not modified; it still listens on
  `bind_address=*` and `require_secure_transport=OFF`. Review that separately
  if the machine is on an untrusted network.
- HTTPS and production deployment hardening.
- iOS ATS configuration for local HTTP development if iOS becomes a target.
