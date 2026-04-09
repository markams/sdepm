"""Common schema helpers."""

from __future__ import annotations

import re
from typing import Annotated

from pydantic import Field

FUNCTIONAL_ID_PATTERN = r"^[A-Za-z0-9-]+$"
_FUNCTIONAL_ID_RE = re.compile(FUNCTIONAL_ID_PATTERN)

FunctionalId = Annotated[
    str,
    Field(
        min_length=1,
        max_length=64,
        pattern=FUNCTIONAL_ID_PATTERN,
    ),
]

OptionalFunctionalId = Annotated[
    str | None,
    Field(
        min_length=1,
        max_length=64,
        pattern=FUNCTIONAL_ID_PATTERN,
    ),
]


def validate_functional_id(value: str, field_name: str) -> None:
    """Validate that a string conforms to the functional ID pattern.

    Used at the API layer to validate JWT claims (client_id) that are not
    covered by Pydantic schema validation (since they come from the token,
    not from the request body or form fields).

    Raises:
        ValueError: If the value does not match the functional ID pattern.
    """
    if not value or len(value) > 64 or not _FUNCTIONAL_ID_RE.match(value):
        raise ValueError(
            f"{field_name} must be 1-64 characters matching {FUNCTIONAL_ID_PATTERN}, got: '{value}'"
        )


__all__ = [
    "FUNCTIONAL_ID_PATTERN",
    "FunctionalId",
    "OptionalFunctionalId",
    "validate_functional_id",
]
