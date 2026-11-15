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

# Analytics events older than this are pruned by the maintenance command.
ANALYTICS_RETENTION_DAYS = int(os.getenv("ANALYTICS_RETENTION_DAYS", "365"))

# Failed-login throttle, counted per client address + email.
LOGIN_MAX_ATTEMPTS = int(os.getenv("LOGIN_MAX_ATTEMPTS", "10"))
LOGIN_WINDOW_SECONDS = int(os.getenv("LOGIN_WINDOW_SECONDS", "300"))

# Password-reset codes are single-use and short-lived.
PASSWORD_RESET_TTL_MINUTES = int(os.getenv("PASSWORD_RESET_TTL_MINUTES", "30"))

# Comma-separated origins; "*" is fine for local development.
CORS_ORIGINS = [
    origin.strip()
    for origin in os.getenv("CORS_ORIGINS", "*").split(",")
    if origin.strip()
]

# AI layer (v2.0): Ollama local + mock provider for tests.
AI_PROVIDER = os.getenv("AI_PROVIDER", "ollama").strip().lower()
AI_MODEL = os.getenv("AI_MODEL", "qwen2.5:7b").strip()
AI_BASE_URL = os.getenv("AI_BASE_URL", "http://localhost:11434").strip()
# Generation is slow on CPU; the client waits longer than the normal 15 s.
AI_TIMEOUT_SECONDS = int(os.getenv("AI_TIMEOUT_SECONDS", "180"))

# SMTP settings for email notifications (deferred until SMTP is configured).
SMTP_HOST = os.getenv("SMTP_HOST")
SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
SMTP_USER = os.getenv("SMTP_USER")
SMTP_PASS = os.getenv("SMTP_PASS")
SMTP_FROM = os.getenv("SMTP_FROM", SMTP_USER)
SMTP_TLS = os.getenv("SMTP_TLS", "true").strip().lower() in {"1", "true", "yes", "on"}

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

if ENVIRONMENT == "production" and "*" in CORS_ORIGINS:
    raise RuntimeError(
        "Set CORS_ORIGINS to the trusted origins before running in production."
    )
