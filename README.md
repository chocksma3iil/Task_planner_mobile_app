# Task Planner

Flutter mobile client with a FastAPI + MySQL backend and a browser-based
phpMyAdmin instance for local development.

The app is online-only: it talks to the API and stores no task data locally.
The API owns authentication, roles, membership approval, and task rules.

## Repository layout

| Path | Purpose |
|---|---|
| `task_planner/` | Flutter app (Riverpod, go_router, HTTP). |
| `backend/` | FastAPI API, SQLAlchemy models, Alembic migrations, pytest suite. |
| `compose.yaml` | Local MySQL + API + phpMyAdmin stack. |
| `docs/` | Architecture, implementation plan, and decision records. |

## Quick start

On a fresh clone, after installing the prerequisites below:

```powershell
Copy-Item .env.example .env
# edit .env and replace the placeholders
docker compose up --build -d
docker compose ps
```

In a second terminal:

```powershell
cd task_planner
flutter pub get
flutter run
```

The API is at <http://127.0.0.1:8000>, Swagger at
<http://127.0.0.1:8000/docs>, and phpMyAdmin at <http://127.0.0.1:8080>.
The sections below explain each step and the Android/device variants.

## 1. Prerequisites

- Git.
- Docker Desktop (Windows/macOS) or Docker Engine with Compose v2.
- Flutter 3.47+ and Dart 3.13+.
- Android Studio, Android SDK, and an emulator for Android development.
- Optional: VS Code. Open the repository folder and accept the recommended
  Flutter, Dart, Python, and Docker extensions.
- Python 3.11+ only if you run the backend directly on the host instead of
  in Docker.

Flutter stays on the host rather than in a Dev Container so emulator, USB
device, and desktop debugging work normally. Only the API, MySQL, and
phpMyAdmin run in Docker.

Verify the tools from a new terminal:

```powershell
docker --version
docker compose version
flutter doctor
```

For Android, accept the SDK licenses and check for an emulator:

```powershell
flutter doctor --android-licenses
flutter emulators
adb devices
```

If `docker` is not found on Windows, make sure Docker Desktop is running and
open a new terminal. A per-user install may need Docker Desktop's
`resources\bin` directory on `PATH`.

## 2. Clone the repository

```powershell
git clone https://github.com/chocksma3iil/Task_planner_mobile_app.git
cd Task_planner_mobile_app
```

Use your fork instead of the upstream URL if you have one.

## 3. Configure environment variables

The Docker stack reads the root `.env`. It is Git-ignored. Skip this copy if
`.env` already exists.

```powershell
Copy-Item .env.example .env
```

Edit `.env` and replace the placeholder passwords and `SECRET_KEY`. Use
URL-safe characters in `MYSQL_PASSWORD` because it becomes part of the
database URL. The defaults for ports are:

- API: `8000`
- phpMyAdmin: `8080`
- MySQL: `3306` inside the Docker network only

The API and phpMyAdmin bind to `127.0.0.1` by default. MySQL has no host port,
so the stack does not conflict with a MySQL installation on your machine and
does not expose the database to the LAN.

`backend/.env` is only for running FastAPI directly on the host. It is not
needed for the Compose flow. Never commit either `.env` file or use development
credentials for shared or production systems.

## 4. Start Docker services

From the repository root:

```powershell
docker compose up --build -d
docker compose ps
```

Wait until `mysql` and `api` are healthy. First start pulls images and
initializes the database, so it can take a few minutes.

Useful commands:

```powershell
docker compose logs -f api
docker compose logs -f mysql
docker compose down
```

`docker compose down` keeps the named database volume. Do **not** use
`docker compose down -v` unless you intend to delete all local Docker database
data.

## 5. Initialize the database

The API container runs this before Uvicorn starts:

```text
alembic upgrade head
```

On a fresh volume this applies `backend/alembic/versions/0001_initial.py` and
creates `projects`, `assignees`, `tasks`, and `alembic_version`. The MySQL init
script also creates `task_planner_test` and grants the app user access, so the
pytest suite works without manual database setup.

Verify the tables:

```powershell
docker compose exec mysql mysql -utask_planner -p task_planner -e "SHOW TABLES;"
```

The final `task_planner` argument selects the database; without it, MySQL
returns `ERROR 1046 (3D000): No database selected`. Use the `MYSQL_PASSWORD`
value from `.env` when prompted. You can also inspect
`alembic_version` there. The Compose database is separate from any MySQL
installation already running on the host; it does not overwrite or reset it.

If you have an older database created by `create_all` rather than Alembic, do
not run migrations blindly. Back it up first; after verifying the schema
matches, `alembic stamp 0001_initial` can mark it as current. Never do this
against a shared database without authorization.

## 6. Run the Flutter application

From the repository root, in a second terminal:

```powershell
cd task_planner
flutter pub get
flutter run
```

The app uses `http://localhost:8000/api/v1` by default, which works for Windows
desktop, web, and the iOS simulator. For other targets, pass the full base URL,
including `/api/v1`.

| Target | Command |
|---|---|
| Windows desktop | `flutter run -d windows` |
| Android emulator | `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1` |
| Android physical device over USB | `adb reverse tcp:8000 tcp:8000` then `flutter run --dart-define=API_BASE_URL=http://localhost:8000/api/v1` |
| Physical device over LAN | Set `API_BIND=0.0.0.0` in `.env`, run `docker compose up -d api`, then use `--dart-define=API_BASE_URL=http://YOUR_LAN_IP:8000/api/v1` |

LAN binding exposes the API on your network. Use it only on a trusted network
and allow port `8000` through the host firewall if needed. The development API
uses HTTP; release builds should use HTTPS. Android debug builds allow local
HTTP. iOS blocks cleartext HTTP by default, so iOS device development needs
HTTPS or a reviewed ATS exception.

The first account registered on a fresh database becomes the admin. Later
sign-ups join a project as pending members until the project owner or an admin
confirms them. Passwords must be at least 8 characters.

## 7. Access phpMyAdmin

Open <http://127.0.0.1:8080>. The login page is already configured for the
local `mysql` container. These are the MySQL credentials, not the app account
you create in Flutter.

- Username: `task_planner`
- Password: `MYSQL_PASSWORD` from the root `.env`

phpMyAdmin is bound to loopback only. Do not expose it publicly.

## 8. Run tests and checks

Backend tests run inside the API container against `task_planner_test`:

```powershell
docker compose exec api python -m pytest tests -q
```

Flutter checks do not need the backend:

```powershell
cd task_planner
flutter analyze
flutter test
```

The Flutter widget tests use an in-memory fake API client. The backend test
suite truncates its test tables between tests, so `TEST_DATABASE_URL` must
always point at a disposable local database.

## 9. Troubleshooting

| Symptom | Check |
|---|---|
| `docker: command not found` | Start Docker Desktop and open a new terminal; verify `PATH`. |
| `docker-credential-desktop` not found | Open a new terminal after installing Docker Desktop, or add its `resources\bin` directory to `PATH`. |
| Port `8000` or `8080` already in use | Stop the local service or change `API_PORT` / `PHPMYADMIN_PORT` in `.env`, then restart Compose. |
| API container is unhealthy | Run `docker compose logs api`; confirm `mysql` is healthy and the API uses hostname `mysql`, not `localhost`. |
| phpMyAdmin cannot log in | Use user `task_planner` and the password from `.env`; leave the default server. Check `docker compose logs mysql`. |
| `ERROR 1046 (3D000): No database selected` | Add the database name to the MySQL command: `docker compose exec mysql mysql -utask_planner -p task_planner -e "SHOW TABLES;"`. |
| `Access denied` after changing MySQL passwords | MySQL applies `MYSQL_*` values only when the volume is first initialized. Use the original credentials or change the database user explicitly; do not delete the volume without a backup. |
| Alembic says a table already exists | The database was not created by Alembic. Use a fresh volume, or back up and stamp only after verifying the schema. |
| Android app cannot reach the API | Use `10.0.2.2` for the emulator, or `adb reverse tcp:8000 tcp:8000` for USB. Debug builds allow local HTTP; release builds do not. |
| `TEST_DATABASE_URL` is missing | Use the Compose test command above, or create `backend/.env` for a host-run backend. |

## 10. Shared development database (optional)

This repository does not create or expose a shared database. If your team
provides one, the maintainer supplies the host, port, database name, username,
password, and phpMyAdmin URL separately. Do not put those credentials in the
root `.env` used by the local Compose stack and never commit them.

For a shared database, run only the API and the Flutter app locally:

```powershell
$env:DATABASE_URL = "mysql+pymysql://USER:PASSWORD@SHARED_HOST:3306/task_planner?charset=utf8mb4"
$env:CREATE_SCHEMA_ON_STARTUP = "false"

cd backend
.\.venv\Scripts\Activate.ps1
uvicorn app.main:app --reload
```

- If you run the test suite, set `TEST_DATABASE_URL` to a separate disposable
  local database. The test suite truncates tables; never point it at shared
  data.
- Do not run `alembic upgrade head` or any write operation against shared data
  without explicit authorization.
- If a shared phpMyAdmin instance is provided, use its URL. The local
  phpMyAdmin service is configured for the local `mysql` container only.

## Further reading

- `backend/README.md` — API setup, configuration, endpoints, and migrations.
- `task_planner/README.md` — Flutter setup, architecture, and file layout.
- `docs/decisions/2026-10-22-local-development-onboarding.md` — decision record
  for this setup.
- `docs/decisions/2026-10-21-fastapi-mysql-backend.md` — backend architecture.
