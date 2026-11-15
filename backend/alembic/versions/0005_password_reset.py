"""account token version and password reset codes

Revision ID: 0005_password_reset
Revises: 0004_subtasks
Create Date: 2026-10-30
"""
from alembic import op
import sqlalchemy as sa

revision = "0005_password_reset"
down_revision = "0004_subtasks"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "assignees",
        sa.Column("token_version", sa.Integer(), server_default="0", nullable=False),
    )
    op.create_table(
        "password_reset_tokens",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("account_id", sa.Integer(), nullable=False),
        sa.Column("token_hash", sa.String(length=64), nullable=False),
        sa.Column("expires_at", sa.DateTime(), nullable=False),
        sa.Column("used_at", sa.DateTime(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(),
            server_default=sa.text("CURRENT_TIMESTAMP"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["account_id"], ["assignees.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("token_hash"),
    )
    op.create_index(
        "ix_password_reset_tokens_account_id",
        "password_reset_tokens",
        ["account_id"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_password_reset_tokens_account_id", table_name="password_reset_tokens"
    )
    op.drop_table("password_reset_tokens")
    op.drop_column("assignees", "token_version")
