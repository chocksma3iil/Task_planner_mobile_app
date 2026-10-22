# Decision: FastAPI + MySQL backend replaces local-only persistence

## Context

Milestone 1 shipped an offline-first Flutter app with local SQLite (Drift)
persistence and local-only accounts. The user then requested a server-backed
backend so the app can be hosted and used by multiple people, and approved the
proposal to keep the Flutter screens/services intact while swapping the data
layer.

## Options considered

- **Keep local SQLite (Drift).** Simplest, keeps offline-first promise. No
  sharing between people; cannot meet the multi-user hosting goal.
- **FastAPI + MySQL backend (chosen).** Single REST API the Flutter app calls
  over HTTP; MySQL stores data; the server enforces roles, membership
  approval, and assignment rules. The app becomes online-only.
- **Node.js/Express + PostgreSQL.** Equally capable, but adds a second
  language toolchain to the repo without benefit over Python/FastAPI here.

## Decision

- New `backend/` FastAPI application with MySQL persistence; the Flutter app
  no longer stores tasks locally (Drift/SQLite removed).
- The server is the single enforcement point for access control, membership
  approval, and the task-assignment rule; Dart `core/rules.dart` stays as a
  UX-side check only.
- First registered account on a fresh database becomes admin (bootstrap).
- Local accounts and login/sign-up screens are kept (no cloud auth provider).

## Status

**APPROVED (2026-10-21)** by the user in conversation ("yes" to the written
proposal covering FastAPI + MySQL, online-only, server-enforced rules,
first-signup-admin bootstrap).

## Reverses

Partially reverses the Milestone 1 constraint "task management must not depend
on network availability" (docs/ARCHITECTURE_PROPOSAL.md §6). Offline support
would require a sync layer and is not in scope.

## Still open

- Hosting choice (user said: host later — PythonAnywhere, Render, or VPS).
- Password recovery without email delivery (still unanswered for server mode).
- Whether to add offline caching/sync later.
- Deployment hardening: HTTPS, CORS allow-list, secrets management, backups.

## Deviations from the proposal (reported to the user)

- JWT via `PyJWT` instead of `python-jose` (same role, fewer transitive deps).
- Added `python-dotenv` (`.env` loading) and `httpx` (FastAPI TestClient).
- `crypto` (Flutter) removed — bcrypt hashing now happens on the server.
