"""Create incidents table.

Revision ID: 001
Revises:
Create Date: 2026-03-21
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "incidents",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("alert_name", sa.VARCHAR(), nullable=False),
        sa.Column("severity", sa.VARCHAR(), nullable=False),
        sa.Column("service", sa.VARCHAR(), nullable=False),
        sa.Column("fired_at", sa.TIMESTAMP(), nullable=False),
        sa.Column("resolved_at", sa.TIMESTAMP(), nullable=True),
        sa.Column("raw_alert", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("logs_snapshot", sa.TEXT(), nullable=False),
        sa.Column("claude_analysis", sa.TEXT(), nullable=False),
        sa.Column("root_cause", sa.TEXT(), nullable=False),
        sa.Column("runbook", sa.TEXT(), nullable=False),
        sa.Column("github_issue_url", sa.VARCHAR(), nullable=True),
        sa.Column("remediation_action", sa.VARCHAR(), nullable=True),
        sa.Column("remediation_result", sa.VARCHAR(), nullable=True),
        sa.Column(
            "created_at",
            sa.TIMESTAMP(),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id"),
        checkfirst=True,
    )


def downgrade() -> None:
    op.drop_table("incidents")
