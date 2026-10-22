# Task Planner

Mobile task planner built with Flutter, backed by a FastAPI + MySQL server.
Three roles (admin, project owner, user), projects, members, and tasks that can
be created, edited, completed, reopened, and deleted.
The app is online-only: it talks to the API and stores no tasks locally.

For the complete local stack (Docker, MySQL, phpMyAdmin, API, and app), start
with the root [`../README.md`](../README.md).

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.47+ (Dart 3.13+)
- Android Studio, Android SDK, and an emulator for Android development
- A platform to run on: Android emulator, iOS simulator, Windows, or web
- The backend running (Compose is recommended; see `../README.md`)

Verify your setup:

```bash
flutter doctor
```

## Start the backend first

From the repository root, the recommended path is:

```powershell
docker compose up --build -d
```

The API listens on `http://127.0.0.1:8000`; feature routes live under `/api/v1`
and `GET /health` stays unversioned.

For a host-run backend instead:

```powershell
cd ../backend
.\.venv\Scripts\Activate.ps1
uvicorn app.main:app --reload
```

## Run the app

From the `task_planner/` directory:

```bash
flutter pub get
flutter run
```

The app calls `http://localhost:8000/api/v1` unless you override the full base
URL (the version prefix is part of it):

```bash
# Android emulator reaches the host machine at 10.0.2.2
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1

# Physical Android device over USB (requires the API on host port 8000)
adb reverse tcp:8000 tcp:8000
flutter run --dart-define=API_BASE_URL=http://localhost:8000/api/v1

# Physical device over LAN: bind the API to the LAN and use your machine's IP
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000/api/v1
```

For LAN access, set `API_BIND=0.0.0.0` in the root `.env`, then run
`docker compose up -d api` from the repository root so the port mapping is
recreated. Use this only on a trusted network. Android debug builds permit local
HTTP; release builds should use HTTPS. iOS blocks cleartext HTTP by default
and needs HTTPS or a reviewed ATS exception for device development.

On Windows you can run the desktop build directly:

```bash
flutter run -d windows
```

The first account you register becomes the admin (the server promotes the
first account on a fresh database). Everyone after that joins a project as a
pending member until the project owner or an admin confirms them. Passwords
must be at least 8 characters; emails are case-insensitive.

## Test and analyze

```bash
flutter analyze
flutter test
```

Widget tests run against an in-memory fake of the API (`FakeApiClient`), so
they need no backend or database. The backend suite is documented in
`../backend/README.md`.

## Architecture

**Layer-first modular monolith** — one Flutter app plus one FastAPI service:

| Layer | Where | Rule |
|---|---|---|
| Presentation | `screens/`, `widgets/` | Screens, tabs, dialogs, and shared widgets. No HTTP and no business rules. |
| Application / state | `providers/`, `services/` | Riverpod providers wire services to the UI; services call the API and return typed models. |
| Domain | `models/`, `core/rules.dart` | JSON models and pure UX rules (overdue/due-today, role tabs). |
| Data | `services/api_client.dart`, `services/data_sync.dart` | The only place the app performs HTTP (bearer token, JSON, error mapping). |
| Cross-cutting | `core/`, `widgets/shared/` | Theme, formatters, positions, and reusable UI helpers. |
| DI | `main.dart`, `providers/api_providers.dart` | `main` builds `HttpApiClient` from `API_BASE_URL` and overrides `apiClientProvider`. |
| Navigation | `app/app.dart`, `app/router.dart` | `MaterialApp.router`; redirects: logged out → `/login`, logged in → `/home`. |
| Server | `../backend/` | FastAPI + MySQL. The server enforces access control, membership approval, and assignment rules. |

Dependency flow is one-directional: `screens/widgets → providers → services →
ApiClient → HTTP → backend`. The UI never calls the API directly. Business
rules are enforced server-side; `core/rules.dart` only shapes the UI, and
`backend/app/core/rules.py` mirrors the checks for the server.

Refresh strategy: mutations ping `DataSync`, and data streams (`watchFromApi`)
re-fetch in place without a loading flicker.

Stack: Flutter + Dart, flutter_riverpod (state/DI), go_router (navigation),
http (API calls), shared_preferences (theme preference only).

## Project layout — file by file

```
lib/
  main.dart                    # Entry point: builds HttpApiClient from
                               # API_BASE_URL (default .../api/v1), overrides
                               # apiClientProvider, starts ProviderScope.
  app/
    app.dart                   # MaterialApp.router, light/dark theme selection.
    router.dart                # GoRouter routes + session redirects.
  core/
    formatters.dart            # initialsOf, formatDate.
    positions.dart             # Predefined job titles.
    rules.dart                 # Pure UX rules: canLogIn, isAdmin,
                               # visibleTabs, isOverdue/isDueToday/isUpcoming.
    theme.dart                 # buildTheme(Brightness) Material theme factory.
  models/
    account.dart               # Account (JSON key compatible with the old
                               # Assignee model; table remains `assignees`).
    project.dart               # Project.
    task.dart                  # Task.
    models.dart                # Barrel export.
  providers/
    api_providers.dart         # apiClientProvider (overridden in main).
    data_providers.dart        # Service providers + stream providers
                               # (projectsProvider, projectTasksProvider,
                               # myTasksProvider, visibleMembersProvider).
    session_providers.dart     # sessionUserIdProvider, currentUserProvider,
                               # logIn/logOut.
    theme_mode_provider.dart   # Persists light/dark/system in
                               # shared_preferences (device-level choice).
  services/
    api_client.dart            # ApiClient + HttpApiClient (bearer token, JSON,
                               # StateError/ArgumentError mapping, timeout).
    auth_service.dart          # Sign-up, login, token handling.
    data_sync.dart             # Global "data changed" signal + watchFromApi.
    member_service.dart        # Visible members, create, confirm, role change.
    project_service.dart       # Create/list projects, assign owner.
    task_service.dart          # Create/edit/complete/reopen/delete tasks.
  screens/
    login_screen.dart          # Email/password form → logIn().
    signup_screen.dart         # Self-registration (creates pending account).
    home_screen.dart           # Scaffold hosting the role-filtered tabs.
    projects_tab.dart          # Admin-only: create/manage projects + owners.
    members_tab.dart           # Members list scoped to the logged-in role.
    tasks_tab.dart             # Project-scoped task list (admin picks project).
    my_tasks_tab.dart          # Tasks assigned to the logged-in person.
  widgets/
    members/
      add_member_dialog.dart   # Collects the new active member.
      member_card.dart         # Roster row with status/role/confirm action.
    projects/
      create_project_dialog.dart
      project_card.dart        # Project summary + admin owner menu.
    settings/
      theme_picker.dart        # System / Light / Dark dialog.
    shared/
      app_snackbar.dart        # showAppSnackBar + userMessage helper.
      empty_state.dart         # Empty/no-match state (optionally scrollable).
      error_state.dart         # Error message with retry.
      position_field.dart      # Dropdown + custom job-title input.
      search_field.dart        # DebouncedSearchField.
      section_header.dart      # SectionHeader.
    tasks/
      priority_chip.dart
      swipe_background.dart
      task_filters.dart        # All/Today/Upcoming/Overdue chips.
      task_form_dialog.dart    # Create/edit dialog (returns TaskDraft).
      task_list.dart           # Reusable task list: search, stats, grouping,
                               # swipe/undo, tap-to-edit, pull-to-refresh.
      task_stats.dart
      task_tile.dart
test/
  rules_test.dart              # Unit tests for core/rules.dart.
  api_client_test.dart         # Error/token mapping of HttpApiClient.
  home_screen_test.dart        # Widget tests for the home screen and edit
                               # flow, driven by FakeApiClient.
```

Other files and where they come from:

| Path | Origin |
|---|---|
| `pubspec.yaml` | Hand-written; declares dependencies. |
| `pubspec.lock`, `.dart_tool/`, `.flutter-plugins-dependencies` | Created by `flutter pub get`. |
| `analysis_options.yaml` | `flutter create` (flutter_lints defaults). |
| `android/`, `ios/`, `macos/`, `windows/`, `linux/`, `web/` | `flutter create` platform scaffolding. Android emulators need the `10.0.2.2` base URL; iOS simulators and desktop can use `localhost`. |
| `GeneratedPluginRegistrant.*`, `generated_plugins.cmake` | Flutter tool, from declared plugins. |

Rule of thumb: anything under a platform folder, `build/`, or `.dart_tool/` is
generated; everything else under `lib/` is hand-written.

## Further reading

Docs live in the repository root (one level up from this directory):

- `../README.md` — full local development quickstart
- `../PROJECT_BRIEF.md` — product requirements
- `../docs/ARCHITECTURE_PROPOSAL.md` — approved architecture
- `../docs/IMPLEMENTATION_PLAN.md` — milestone status
- `../docs/decisions/2026-10-22-local-development-onboarding.md` — Docker and
  onboarding decision
- `../docs/decisions/2026-10-21-fastapi-mysql-backend.md` — backend decision
- `../docs/decisions/2026-10-21-structure-and-api-hardening.md` — layer-first
  layout, `/api/v1`, validation, and task editing
- `../backend/README.md` — API setup and endpoint summary
- [Flutter docs](https://docs.flutter.dev/) — guides and API reference
