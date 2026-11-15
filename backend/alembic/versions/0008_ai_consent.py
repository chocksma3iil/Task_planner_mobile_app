"""ai consent flag on projects

Revision ID: 0008_ai_consent
Revises: 0007_comments
Create Date: 2026-10-31
"""

from alembic import op
import sqlalchemy as sa

revision = "0008_ai_consent"
down_revision = "0007_comments"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "projects",
        sa.Column(
            "ai_opt_in",
            sa.Integer(),
            server_default="0",
            nullable=False,
        ),
    )


def downgrade() -> None:
    op.drop_column("projects", "ai_opt_in")
