"""Test setup: point the app at the MySQL test database and clean between tests."""
import os
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent.parent / ".env")
if not os.environ.get("TEST_DATABASE_URL"):
    raise RuntimeError(
        "TEST_DATABASE_URL is missing â€” copy backend/.env.example to backend/.env."
    )
# Force the app (imported below) onto the test database.
os.environ["DATABASE_URL"] = os.environ["TEST_DATABASE_URL"]

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.core.database import Base, engine  # noqa: E402
from app.main import app  # noqa: E402


@pytest.fixture(scope="session")
def client():
    """App client against a freshly created test schema."""
    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture(autouse=True)
def clean_database(client):
    """Empty every table (resetting ids) before each test."""
    with engine.begin() as conn:
        conn.exec_driver_sql("SET FOREIGN_KEY_CHECKS = 0")
        for table in reversed(Base.metadata.sorted_tables):
            conn.exec_driver_sql(f"TRUNCATE TABLE {table.name}")
        conn.exec_driver_sql("SET FOREIGN_KEY_CHECKS = 1")
    yield
