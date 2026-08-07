"""Typed P2B result for the confirmation-to-ApprovalIntent boundary.

The result is deliberately a metadata-only projection.  The server-side
``PrototypeApprovalStore`` may retain the candidate, SafetyEvaluation and
server-captured input for the isolated prototype, but none of those health-data fields
are returned to the caller by this module.
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import Field, model_validator

from .confirmation import ApprovalIntent, ResourceRef
from .types import StrictModel


class ApprovalRequiredProjection(StrictModel):
    """Application-origin lifecycle projection; not a complete public AgentTurn."""

    turn_id: UUID
    session_id: UUID
    source_turn_id: UUID
    sequence: int = Field(ge=1)
    revision: int = Field(ge=2)
    status: Literal["approval_required"] = "approval_required"
    state: Literal["awaiting_approval"] = "awaiting_approval"
    output_origin: Literal["application"] = "application"
    approval_id: UUID
    approval_revision: int = Field(ge=1)
    resource_revision: int = Field(ge=1)
    action_type: str = Field(pattern=r"^confirm_body_signal_event$")
    target_ref: ResourceRef
    intent_digest: str = Field(pattern=r"^sha256:[a-f0-9]{64}$")
    display_summary: str = Field(min_length=1, max_length=2000)
    expires_at: datetime

    @model_validator(mode="after")
    def validate_projection(self) -> "ApprovalRequiredProjection":
        if self.target_ref.type != "session" or self.target_ref.id != self.session_id:
            raise ValueError("approval projection target must be the source Session")
        if self.approval_revision != 1:
            raise ValueError("first ApprovalIntent projection must use revision 1")
        if self.approval_id.int == 0 or self.turn_id.int == 0 or self.source_turn_id.int == 0:
            raise ValueError("approval projection IDs must be non-zero")
        return self


class ConfirmationIntentApplicationResult(StrictModel):
    """Stable, redacted P2B application result."""

    schema_version: Literal["1.0"] = "1.0"
    approval: ApprovalIntent
    source_session_id: UUID
    source_turn_id: UUID
    previous_session_revision: int = Field(ge=1)
    proposed_session_revision: int = Field(ge=2)
    approval_projection: ApprovalRequiredProjection
    created_at: datetime

    @model_validator(mode="after")
    def validate_relations(self) -> "ConfirmationIntentApplicationResult":
        if self.proposed_session_revision != self.previous_session_revision + 1:
            raise ValueError("confirmation projection must advance Session revision exactly once")
        if self.approval.source_session_id != self.source_session_id:
            raise ValueError("Approval source Session mismatch")
        if self.approval.target_ref.type != "session" or self.approval.target_ref.id != self.source_session_id:
            raise ValueError("Approval target must be source Session")
        if self.approval.resource_revision != self.previous_session_revision:
            raise ValueError("Approval resource revision must bind the reviewed Session revision")
        if self.approval.status != "pending" or self.approval.revision != 1:
            raise ValueError("P2B result must expose a first pending ApprovalIntent")
        projection = self.approval_projection
        if projection.session_id != self.source_session_id or projection.source_turn_id != self.source_turn_id:
            raise ValueError("approval projection source relation mismatch")
        if projection.revision != self.proposed_session_revision:
            raise ValueError("approval projection revision mismatch")
        if projection.approval_id != self.approval.approval_id:
            raise ValueError("approval projection ID mismatch")
        if projection.resource_revision != self.approval.resource_revision:
            raise ValueError("approval projection resource revision mismatch")
        if projection.intent_digest != self.approval.intent_digest:
            raise ValueError("approval projection digest mismatch")
        if projection.target_ref != self.approval.target_ref:
            raise ValueError("approval projection target mismatch")
        if projection.expires_at != self.approval.expires_at:
            raise ValueError("approval projection expiry mismatch")
        return self
