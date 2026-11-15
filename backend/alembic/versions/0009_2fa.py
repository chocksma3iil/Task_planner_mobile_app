"""2FA TOTP on accounts

Revision ID: 0009_2fa
Revises: 0008_ai_consent
Create Date: 2026-10-31
"""

from alembic import op
import sqlalchemy as sa

revision = "0009_2fa"
down_revision = "0008_ai_consent"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "assignees",
        sa.Column("totp_secret", sa.String(length=255), nullable=True),
    )
    op.add_column(
        "assignees",
        sa.Column("totp_enabled", sa.Integer(), server_default="0", nullable=False),
    )
    op.add_column(
        "assignees",
        sa.Column("totp_backup_codes", sa.JSON(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("assignees", "totp_backup_codes")
    op.drop_column("assignees", "totp_enabled")
    op.drop_column("assignees", "totp_secret")
