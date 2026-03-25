"""Pydantic schemas for Bulk Activity API requests and responses."""

from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field

__all__ = [
    "BulkActivityRequest",
    "BulkActivityResponse",
    "BulkActivityResultItem",
]


class BulkActivityRequest(BaseModel):
    """Bulk activity request schema.

    Accepts a list of raw dicts (not pre-validated ActivityRequest models)
    to enable per-item Pydantic validation in the service layer.
    This way, one invalid item does not block the other items in the batch.

    Validation flow Step 1: each item is validated individually via
    TypeAdapter(ActivityRequest).validate_python() in the service layer.
    Failed items are marked NOK; valid items continue to Step 2.
    """

    model_config = ConfigDict(
        title="activity.BulkActivityRequest",
    )

    activities: list[dict[str, Any]] = Field(
        ...,
        min_length=1,
        max_length=1000,
        description="List of activity dicts to process (1-1000 items per batch). Each item is validated individually against the ActivityRequest schema.",
    )


class BulkActivityResultItem(BaseModel):
    """Result for a single item in a bulk activity response."""

    model_config = ConfigDict(
        title="activity.BulkActivityResultItem",
        populate_by_name=True,
    )

    activity_index: int = Field(
        ...,
        alias="activityIndex",
        ge=0,
        description="Zero-based index of this item in the original request list",
        examples=[0],
    )

    activity_id: str | None = Field(
        None,
        alias="activityId",
        description="Activity functional ID (present for OK items and items that had a valid activityId before failing)",
        examples=["550e8400-e29b-41d4-a716-446655440000"],
    )

    status: Literal["OK", "NOK"] = Field(
        ...,
        description="Processing result: OK (created successfully) or NOK (failed validation or processing)",
        examples=["OK"],
    )

    error_message: str | None = Field(
        None,
        alias="errorMessage",
        description="Error description when status is NOK; null when status is OK",
        examples=[None],
    )


class BulkActivityResponse(BaseModel):
    """Bulk activity response schema.

    Returns per-item OK/NOK feedback with summary counts.
    Validation flow Step 4: the original list enriched with status and error_message.
    """

    model_config = ConfigDict(
        title="activity.BulkActivityResponse",
        populate_by_name=True,
    )

    total_received: int = Field(
        ...,
        alias="totalReceived",
        ge=0,
        description="Total number of items received in the request",
        examples=[2],
    )

    succeeded: int = Field(
        ...,
        ge=0,
        description="Number of items successfully created (status OK)",
        examples=[2],
    )

    failed: int = Field(
        ...,
        ge=0,
        description="Number of items that failed validation or processing (status NOK)",
        examples=[0],
    )

    results: list[BulkActivityResultItem] = Field(
        ...,
        description="Per-item results preserving the original request order",
        json_schema_extra={
            "example": [
                {
                    "activityIndex": 0,
                    "activityId": "550e8400-e29b-41d4-a716-446655440000",
                    "status": "OK",
                    "errorMessage": None,
                },
                {
                    "activityIndex": 1,
                    "activityId": "660f9511-f30c-52e5-b827-557766551111",
                    "status": "OK",
                    "errorMessage": None,
                },
            ]
        },
    )
