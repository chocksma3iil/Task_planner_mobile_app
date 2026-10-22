---
name: flutter-ui
description: Use when building or changing screens, widgets, navigation, theming, or UI state (Flutter and Dart, Riverpod, go_router). Keeps business rules out of UI code and keeps the UI off the database.
---

# Flutter UI

Approved stack: Flutter/Dart, Riverpod for state and DI, go_router for navigation. Approved layer-first layout: `lib/app/`, `lib/core/`, `lib/models/`, `lib/providers/`, `lib/screens/`, `lib/services/`, `lib/widgets/`. Create only folders needed for approved features.

## Rules

- Screens and widgets display state and forward user actions to the application layer. No business rules in UI code.
- UI code must never call the API, the database, or `HttpApiClient` directly; it goes through providers and services (see `database-design` for the model).
- Reuse `lib/core/` theme and shared utilities plus `lib/widgets/shared/`; do not duplicate styling per screen.
- Navigation changes go through `lib/app/router.dart`; do not hard-code route strings in widgets.
- New screens or navigation structure are application-behavior changes: propose and wait for approval (see `interactive-development`).

## UX direction (from the brief)

On open, the user must quickly see what is due today, what is overdue, what is most important, and what is completed. Avoid unnecessary screens and complicated workflows.

The app opens on a login page with a link to the sign-up page. Auth screens collect credentials only; all role and membership checks happen in the application layer, never in widgets.

## Screen order

1. **Login page** — the app's start screen, always shown first; links to sign-up.
2. **Sign-up page** — reachable only from login (name, email, password, project choice).
3. **Role tabs, only after successful login** — Projects (admin only — create, list, assign owners), Members (all roles, scoped roster; pending-requests section for owner/admin), Tasks (all roles, scoped), Mine (owner and user — tasks assigned to the logged-in person; not admin).

No route may render before authentication completes: deep links and restarts land on the login page first.

The definitive per-role mapping lives in the `access-control` skill; keep this list in sync with it.

Which tabs each role sees and how data is scoped per role is defined in the `access-control` skill — implement that mapping here without redefining it.
