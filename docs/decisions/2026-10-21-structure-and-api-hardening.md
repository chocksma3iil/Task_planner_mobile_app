# Decision: Layer-first layout, versioned API, and input hardening

## Context

After Milestones 1–3 the repository had two overlapping structures: the
Flutter app was feature-first (`lib/features/...`), while the README described
a layer-first layout; the backend kept routers, models, schemas, and rules in
flat top-level modules. A repository review also found stale generic skills,
build/IDE artifacts, outdated setup docs, and missing MVP functionality (there
was no way to edit a task after creation). The user asked for a clean,
well-known architecture, approved the refactor plan ("approved all"), and
chose:

- **Layer-first** Flutter layout (`models/screens/services/widgets`) over the
  feature-first proposal;
- keep only the six project skills (delete 27 generic ones);
- version feature routes under `/api/v1` (`/health` unversioned);
- implement **edit task** as the first feature after the restructure;
- no new runtime dependencies.

## Options considered

- **Keep feature-first folders.** Familiar for large apps, but mixed
  responsibilities had grown inside `features/tasks/presentation`, and the
  approved docs already leaned layer-first.
- **Layer-first folders (chosen).** Smaller number of concepts for this app
  size; clear import direction (`screens/widgets → providers → services →
  api_client`), easier to review and test.
- **Flat backend modules (status quo).** Works, but business logic mixed with
  HTTP in routers and a single `models.py`/`schemas.py`; hard to extend.
- **Packages by responsibility (chosen).** `api/` (thin routers + deps),
  `core/` (config, DB, errors, rules, security), `models/`, `schemas/`,
  `services/` (business logic), with `/api/v1` assembled in `api/router.py`.

## Decision

- Flutter layout: `lib/app`, `lib/core`, `lib/models`, `lib/providers`,
  `lib/screens`, `lib/services`, `lib/widgets`; `Assignee` → `Account` in Dart
  (JSON unchanged); router extracted to `lib/app/router.dart`.
- Backend layout as above; feature routes at `/api/v1/...`; health stays at
  `/health`. Routers translate HTTP; services enforce rules and raise the
  `ApiError` hierarchy, mapped by one exception handler.
- Validation: normalized (trimmed/lowercased) emails, 8–72 character
  passwords, non-empty trimmed names/titles, `Literal` roles and priorities.
  Validation failures return 422 with a single readable string `detail`.
- Timestamps are serialized as UTC ISO-8601 (`+00:00`).
- CORS origins, environment name, schema bootstrap, and secret come from
  `.env`; `create_all` runs only when `CREATE_SCHEMA_ON_STARTUP` is true
  (default outside production). Production uses Alembic.
- Edit task: `PATCH /api/v1/tasks/{id}` with partial fields (title,
  description, priority, due date, assignee); re-validates assignee
  membership/activity and keeps the project fixed. Flutter adds
  `TaskService.updateTask` and tap-to-edit on task rows.
- Repository cleanup: remove 27 unused generic skills (`skills-lock.json`
  included), IDE/build/cache artifacts, and stale docs; add `.gitignore`
  entries for caches, coverage, logs, and `.env`.
- No runtime dependencies were added to either app.

## Status

**APPROVED (2026-10-21)** in conversation after the repository review. User
selected the layer-first layout and said "approved all" for the plan.

## Reverses

Partly reverses the feature-first organization in
`docs/ARCHITECTURE_PROPOSAL.md` §2/§5 and the flat backend layout from
Milestone 3 (paths only; behavior stays server-enforced). It also supersedes
the "draft/not approved" label on the data-model section.

## Still open

- Hosting/deployment (HTTPS, CORS allow-list, backups).
- Password recovery.
- Notifications, categories, offline caching.
- Whether to expose an endpoint to archive projects or transfer members.

## Verification (executed 2026-10-21)

- `backend\.venv\Scripts\python.exe -m pytest tests -q` → **32 passed**.
- `flutter analyze` → **No issues found**.
- `flutter test` → **29 passed**.
- Live behavior was not re-smoked against MySQL in this milestone; the
  existing API contract is covered by the pytest suite and the Flutter fake
  client.
