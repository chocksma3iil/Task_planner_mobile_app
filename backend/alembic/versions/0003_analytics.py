"""analytics_events table

Revision ID: 0003_analytics
Revises: 0002_notifications
Create Date: 2026-10-26
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql

revision = "0003_analytics"
down_revision = "0002_notifications"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "analytics_events",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("project_id", sa.Integer(), nullable=False),
        sa.Column("actor_id", sa.Integer(), nullable=False),
        sa.Column("event_type", sa.String(length=64), nullable=False),
        sa.Column("task_id", sa.Integer(), nullable=True),
        sa.Column("payload", sa.Text(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["project_id"], ["projects.id"]),
        sa.ForeignKeyConstraint(["actor_id"], ["assignees.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_analytics_events_project_id", "analytics_events", ["project_id"]
    )
    op.create_index("ix_analytics_events_actor_id", "analytics_events", ["actor_id"])


def downgrade() -> None:
    op.drop_index("ix_analytics_events_actor_id", table_name="analytics_events")
    op.drop_index("ix_analytics_events_project_id", table_name="analytics_events")
    op.drop_table("analytics_events")
