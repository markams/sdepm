"""Migrate address fields to INSPIRE/STR-AP format.

Rename address columns from Dutch BAG-style names to INSPIRE/STR-AP names
and update field length constraints for EU interoperability.

Revision ID: 003
Revises: 002
Create Date: 2026-04-01

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

# Revision identifiers, used by Alembic.
revision: str = "003"
down_revision: Union[str, None] = "002"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Rename address columns to INSPIRE/STR-AP names and widen constraints."""
    # address_street → address_thoroughfare (String(64) → String(80))
    op.alter_column(
        "activity",
        "address_street",
        new_column_name="address_thoroughfare",
        type_=sa.String(80),
    )

    # address_number → address_locator_designator_number (Integer, no type change)
    op.alter_column(
        "activity",
        "address_number",
        new_column_name="address_locator_designator_number",
    )

    # address_letter → address_locator_designator_letter (String(1) → String(10))
    op.alter_column(
        "activity",
        "address_letter",
        new_column_name="address_locator_designator_letter",
        type_=sa.String(10),
    )

    # address_addition → address_locator_designator_addition (String(10) → String(128))
    op.alter_column(
        "activity",
        "address_addition",
        new_column_name="address_locator_designator_addition",
        type_=sa.String(128),
    )

    # address_postal_code → address_post_code (String(8) → String(10))
    op.alter_column(
        "activity",
        "address_postal_code",
        new_column_name="address_post_code",
        type_=sa.String(10),
    )

    # address_city → address_post_name (String(64) → String(80))
    op.alter_column(
        "activity",
        "address_city",
        new_column_name="address_post_name",
        type_=sa.String(80),
    )


def downgrade() -> None:
    """Revert to BAG-style address column names and original constraints."""
    op.alter_column(
        "activity",
        "address_post_name",
        new_column_name="address_city",
        type_=sa.String(64),
    )

    op.alter_column(
        "activity",
        "address_post_code",
        new_column_name="address_postal_code",
        type_=sa.String(8),
    )

    op.alter_column(
        "activity",
        "address_locator_designator_addition",
        new_column_name="address_addition",
        type_=sa.String(10),
    )

    op.alter_column(
        "activity",
        "address_locator_designator_letter",
        new_column_name="address_letter",
        type_=sa.String(1),
    )

    op.alter_column(
        "activity",
        "address_locator_designator_number",
        new_column_name="address_number",
    )

    op.alter_column(
        "activity",
        "address_thoroughfare",
        new_column_name="address_street",
        type_=sa.String(64),
    )
