# Task Planner

Offline-first mobile task planner built with Flutter. Local accounts, three
roles (admin, project owner, user), projects, members, and tasks — no backend
required.

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.47+ (Dart 3.13+)
- A platform to run on: Android emulator, iOS simulator, Windows, or web

Verify your setup:

```bash
flutter doctor
```

## Run the app

From the `task_planner/` directory:

```bash
flutter pub get
flutter run
```

`flutter run` lists available devices — pick an emulator, simulator, or
connected phone. On Windows you can also run the desktop build directly:

```bash
flutter run -d windows
```

## Seed demo data (optional)

The app starts empty except for the first account you create (which becomes
the admin). To load a demo project, users, and tasks into the local database,
run the app once (so the database file is created), then:

```bash
# Windows: make the sqlite native library visible to the Dart VM
$env:PATH = "$PWD\build\native_assets\windows;$env:PATH"
dart run tool/seed_users.dart
```

The seeder is idempotent (safe to re-run). It creates:

| Email | Password | Role |
|---|---|---|
| admin@local.dev | admin123 | admin |
| alice@local.dev | password123 | project owner |
| bob@local.dev | password123 | user |
| carol@local.dev | password123 | pending (cannot log in until confirmed) |

On other platforms the database lives at the app documents directory; pass
the sqlite file path as an argument if it is not in the default Windows
location:

```bash
dart run tool/seed_users.dart /path/to/task_planner.sqlite
```

## Test and analyze

```bash
flutter analyze
flutter test
```

## Project layout

```
lib/
  app/            # MaterialApp + router
  core/           # database, business rules, security, theme (shared)
  features/
    auth/         # login, sign-up, session
    tasks/        # projects, members, tasks (tabs + services)
tool/             # developer scripts (seeder)
test/             # unit tests (rules, security, services)
```

## Further reading

Docs live in the repository root (one level up from this directory):

- `../PROJECT_BRIEF.md` — product requirements
- `../docs/ARCHITECTURE_PROPOSAL.md` — approved architecture
- `../docs/IMPLEMENTATION_PLAN.md` — milestone status
- [Flutter docs](https://docs.flutter.dev/) — guides and API reference
