"""Environment-driven configuration.

Reads `backend/.env` (copy `.env.example` first). DATABASE_URL is required so
no real credentials ever live in the repository.
"""
import os
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parents[2] / ".env")

DATABASE_URL = os.getenv("DATABASE_URL")
TEST_DATABASE_URL = os.getenv("TEST_DATABASE_URL")

# "production" requires an explicit SECRET_KEY (see the guard below).
ENVIRONMENT = os.getenv("ENVIRONMENT", "development").strip().lower()

_DEV_SECRET = "dev-secret-change-me-before-deploying"
SECRET_KEY = os.getenv("SECRET_KEY", _DEV_SECRET)
TOKEN_TTL_DAYS = int(os.getenv("TOKEN_TTL_DAYS", "30"))

# Comma-separated origins; "*" is fine for local development.
CORS_ORIGINS = [
    origin.strip()
    for origin in os.getenv("CORS_ORIGINS", "*").split(",")
    if origin.strip()
]

# Development convenience; production should run `alembic upgrade head`.
CREATE_SCHEMA_ON_STARTUP = os.getenv(
    "CREATE_SCHEMA_ON_STARTUP",
    "false" if ENVIRONMENT == "production" else "true",
).strip().lower() in {"1", "true", "yes", "on"}

if not DATABASE_URL:
    raise RuntimeError(
        "DATABASE_URL is not set. Copy backend/.env.example to backend/.env "
        "and fill in your MySQL connection."
    )

if ENVIRONMENT == "production" and SECRET_KEY == _DEV_SECRET:
    raise RuntimeError("Set a real SECRET_KEY before running in production.")
