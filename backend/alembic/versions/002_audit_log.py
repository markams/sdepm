"""Audit log table.

Revision ID: 002
Revises: 001
Create Date: 2026-03-17

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

# Revision identifiers, used by Alembic.
revision: str = "002"
down_revision: Union[str, None] = "001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade database schema."""
    # Create audit_log table
    op.create_table(
        "audit_log",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("timestamp", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("request_id", sa.String(length=64), nullable=False),
        sa.Column("client_id", sa.String(length=64), nullable=True),
        sa.Column("client_name", sa.String(length=64), nullable=True),
        sa.Column("roles", sa.String(length=256), nullable=True),
        sa.Column("action", sa.String(length=64), nullable=False),
        sa.Column("resource_type", sa.String(length=32), nullable=True),
        sa.Column("resource_id", sa.String(length=64), nullable=True),
        sa.Column("http_method", sa.String(length=10), nullable=False),
        sa.Column("path", sa.String(length=512), nullable=False),
        sa.Column("query_params", sa.String(length=512), nullable=True),
        sa.Column("status_code", sa.Integer(), nullable=False),
        sa.Column("success", sa.Boolean(), nullable=False),
        sa.Column("client_ip", sa.String(length=45), nullable=True),
        sa.Column("user_agent", sa.String(length=256), nullable=True),
        sa.Column("duration_ms", sa.Integer(), nullable=True),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_audit_log")),
    )
    op.create_index(op.f("ix_audit_log_timestamp"), "audit_log", ["timestamp"], unique=False)
    op.create_index(op.f("ix_audit_log_request_id"), "audit_log", ["request_id"], unique=False)
    op.create_index(op.f("ix_audit_log_client_id"), "audit_log", ["client_id"], unique=False)


def downgrade() -> None:
    """Downgrade database schema."""
    op.drop_index(op.f("ix_audit_log_client_id"), table_name="audit_log")
    op.drop_index(op.f("ix_audit_log_request_id"), table_name="audit_log")
    op.drop_index(op.f("ix_audit_log_timestamp"), table_name="audit_log")
    op.drop_table("audit_log")
