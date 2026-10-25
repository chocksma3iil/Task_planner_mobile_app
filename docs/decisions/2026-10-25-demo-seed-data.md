# Decision: Development demo seed data

## Context

Manual testing required an admin, a project owner ("project manager"), regular
staff, a project, and tasks to exist after every local database start. Creating
them by hand through the app was slow and easy to get wrong. The user asked for
hard-coded demo data to be sent to the database on each run.

## Options considered

- **Seed from the Flutter app on every launch.** Matches "per Flutter run"
  literally, but puts admin credentials in the mobile client, adds a dev-only
  API endpoint, and mutates the database on every launch. Rejected.
- **Manual CLI seeder only.** Safe, but requires an extra step and does not run
  automatically. Kept as the fallback behavior when seeding is disabled.
- **Backend startup seeder behind a flag (chosen).** Idempotent seed runs when
  `SEED_DEMO_DATA=true`; Compose enables it by default. No client changes, no
  credentials in Flutter, and production startup refuses the flag.

## Decision

- Add `backend/app/services/seed.py` with an idempotent `seed_demo_data`.
- Create `admin@demo.local` (admin, no project), `manager@demo.local` (project
  owner), and `staff1@demo.local`–`staff3@demo.local` (users), all active with
  password `12345678`.
- Create the `Demo Project`, owned by the manager, with six sample tasks
  assigned to the project, the manager, or staff.
- Existing accounts, projects, and tasks are left untouched; reruns do not
  duplicate rows.
- Run the seeder in the API lifespan only when `SEED_DEMO_DATA=true`.
  `ENVIRONMENT=production` refuses to start with the flag enabled.
- Compose passes `SEED_DEMO_DATA` (default `true`); `backend/.env.example`
  documents it for host-run development.

## Status

**APPROVED (2026-10-25)** by the user in conversation, choosing the backend
startup seed and the password `12345678` with additional staff accounts.

## Still open

- Whether to add more demo projects or per-project task sets.
- Whether the flag should remain enabled by default after onboarding.
