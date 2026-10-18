# Implementation Plan

**Status: Milestone 1 approved and built (2026-10-11).**

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

## Next (not approved)

- Notifications, backup/restore.
