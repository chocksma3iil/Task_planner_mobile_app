"""Demo seed data: idempotent, role-correct, and login-ready."""
from sqlalchemy import func, select

from app.core.database import SessionLocal
from app.core.rules import ACTIVE, ADMIN, PROJECT_OWNER, USER
from app.core.security import verify_password
from app.models import Assignee, Project, Task
from app.services.seed import DEMO_PASSWORD, seed_demo_data


def _count(db, model) -> int:
    return db.scalar(select(func.count()).select_from(model))


def test_seed_demo_data_is_idempotent_and_valid(client):
    with SessionLocal() as db:
        seed_demo_data(db)
        first = (_count(db, Assignee), _count(db, Project), _count(db, Task))
        seed_demo_data(db)
        second = (_count(db, Assignee), _count(db, Project), _count(db, Task))
    assert first == second == (5, 1, 6)

    with SessionLocal() as db:
        admin = db.scalar(select(Assignee).where(Assignee.email == "admin@demo.local"))
        manager = db.scalar(
            select(Assignee).where(Assignee.email == "manager@demo.local")
        )
        staff = list(db.scalars(select(Assignee).where(Assignee.role == USER)))
        project = db.scalar(select(Project).where(Project.name == "Demo Project"))
        tasks = list(db.scalars(select(Task)))

        assert admin.role == ADMIN and admin.status == ACTIVE
        assert admin.project_id is None
        assert manager.role == PROJECT_OWNER and manager.status == ACTIVE
        assert manager.project_id == project.id
        assert project.owner_id == manager.id
        assert len(staff) == 3
        assert all(person.project_id == project.id for person in staff)
        assert all(person.status == ACTIVE for person in staff)
        assert len(tasks) == 6
        member_ids = {manager.id, *(person.id for person in staff)}
        assert all(
            task.project_id == project.id
            and (task.assignee_id is None or task.assignee_id in member_ids)
            for task in tasks
        )
        assert verify_password(DEMO_PASSWORD, manager.password_hash)

    response = client.post(
        "/api/v1/auth/login",
        json={"email": "manager@demo.local", "password": DEMO_PASSWORD},
    )
    assert response.status_code == 200
    assert response.json()["account"]["role"] == PROJECT_OWNER


def test_seed_demo_data_does_not_overwrite_existing_rows(client):
    with SessionLocal() as db:
        seed_demo_data(db)
        admin = db.scalar(select(Assignee).where(Assignee.email == "admin@demo.local"))
        admin.name = "Renamed Admin"
        db.commit()

        seed_demo_data(db)
        db.refresh(admin)
        assert admin.name == "Renamed Admin"
