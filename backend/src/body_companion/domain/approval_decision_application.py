"""Typed P2C terminal approval-decision projection.

The models in this module deliberately expose only metadata.  The prototype
Approval/Event stores retain the reviewed candidate and server-owned safety
inputs in process memory, but those health-data fields must never cross the
P2C result boundary.
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import Field, model_validator

from .confirmation import ApprovalIntent, ResourceRef
from .types import StrictModel


TerminalApprovalStatus = Literal["executed", "denied", "invalidated", "failed"]


class ApprovalDecisionMetadata(StrictModel):
    approval_id: UUID
    action_type: Literal["confirm_body_signal_event"]
    target_ref: ResourceRef
    source_session_id: UUID
    status: TerminalApprovalStatus
    resolution_reason: Literal[
        "action_executed",
        "user_denied",
        "context_changed",
        "user_discarded",
        "session_expired",
        "consent_revoked",
        "execution_failed",
    ]
    revision: int = Field(ge=1)
    result_refs: list[ResourceRef] = Field(default_factory=list, max_length=20)
    decided_at: datetime

    @model_validator(mode="after")
    def validate_result_refs(self) -> "ApprovalDecisionMetadata":
        if self.target_ref.type != "session" or self.target_ref.id != self.source_session_id:
            raise ValueError("body-event decision must target its source Session")
        if self.status == "executed":
            if self.resolution_reason != "action_executed" or len(self.result_refs) != 1:
                raise ValueError("executed decision requires exactly one result")
            if self.result_refs[0].type != "event":
                raise ValueError("body-event approval result must be an event")
        else:
            if self.status == "denied" and self.resolution_reason != "user_denied":
                raise ValueError("denied decision requires user_denied")
            if self.status == "failed" and self.resolution_reason != "execution_failed":
                raise ValueError("failed decision requires execution_failed")
            if self.status == "invalidated" and self.resolution_reason not in {
                "context_changed",
                "user_discarded",
                "session_expired",
                "consent_revoked",
            }:
                raise ValueError("invalidated decision has an invalid reason")
            if self.result_refs:
                raise ValueError("non-executed decision cannot expose result resources")
        return self


class ApprovalDecisionLifecycleProjection(StrictModel):
    """Prospective application lifecycle, not a persisted Session/Turn."""

    turn_id: UUID
    session_id: UUID
    source_turn_id: UUID
    sequence: int = Field(ge=1)
    revision: int = Field(ge=3)
    status: Literal["completed", "approval_decided", "failed"]
    state: Literal["completed", "awaiting_confirmation", "failed"]
    output_origin: Literal["application"] = "application"
    approval_id: UUID
    approval_revision: int = Field(ge=1)
    resource_revision: int = Field(ge=1)
    action_type: Literal["confirm_body_signal_event"]
    target_ref: ResourceRef
    intent_digest: str = Field(pattern=r"^sha256:[a-f0-9]{64}$")
    approval_status: TerminalApprovalStatus
    result_refs: list[ResourceRef] = Field(default_factory=list, max_length=20)

    @model_validator(mode="after")
    def validate_projection(self) -> "ApprovalDecisionLifecycleProjection":
        if self.session_id.int == 0 or self.turn_id.int == 0 or self.source_turn_id.int == 0:
            raise ValueError("lifecycle projection IDs must be non-zero")
        if self.target_ref.type != "session" or self.target_ref.id != self.session_id:
            raise ValueError("lifecycle target must be the source Session")
        if self.approval_status == "executed":
            if self.status != "completed" or self.state != "completed":
                raise ValueError("executed lifecycle must be completed")
            if len(self.result_refs) != 1 or self.result_refs[0].type != "event":
                raise ValueError("executed lifecycle requires one event result")
        elif self.approval_status in {"denied", "invalidated"}:
            if self.status != "approval_decided" or self.state != "awaiting_confirmation" or self.result_refs:
                raise ValueError("denied/invalidated lifecycle must return to confirmation without refs")
        elif self.status != "failed" or self.state != "failed" or self.result_refs:
            raise ValueError("failed lifecycle must remain failed without refs")
        return self


class ApprovalDecisionApplicationResult(StrictModel):
    """Stable, redacted P2C result; not a public API response."""

    schema_version: Literal["1.0"] = "1.0"
    approval: ApprovalIntent
    decision: ApprovalDecisionMetadata
    source_session_id: UUID
    source_turn_id: UUID
    previous_session_revision: int = Field(ge=1)
    proposed_session_revision: int = Field(ge=3)
    lifecycle: ApprovalDecisionLifecycleProjection
    created_at: datetime

    @model_validator(mode="after")
    def validate_relations(self) -> "ApprovalDecisionApplicationResult":
        if self.proposed_session_revision != self.previous_session_revision + 2:
            raise ValueError("P2C prospective terminal projection must advance two application revisions")
        if self.approval.status != self.decision.status:
            raise ValueError("Approval status and decision status must match")
        if self.approval.approval_id != self.decision.approval_id:
            raise ValueError("Approval and decision ID mismatch")
        if self.approval.source_session_id != self.source_session_id:
            raise ValueError("Approval source Session mismatch")
        if self.approval.target_ref.type != "session" or self.approval.target_ref.id != self.source_session_id:
            raise ValueError("Approval target must be source Session")
        if self.approval.resource_revision != self.previous_session_revision:
            raise ValueError("Approval resource revision must bind the P2B pre-approval revision")
        if self.decision.target_ref != self.approval.target_ref:
            raise ValueError("decision target mismatch")
        if self.decision.source_session_id != self.source_session_id:
            raise ValueError("decision source Session mismatch")
        if self.decision.result_refs != self.lifecycle.result_refs:
            raise ValueError("decision and lifecycle result refs must match")
        projection = self.lifecycle
        if projection.session_id != self.source_session_id or projection.source_turn_id != self.source_turn_id:
            raise ValueError("lifecycle source relation mismatch")
        if projection.approval_id != self.approval.approval_id:
            raise ValueError("lifecycle approval ID mismatch")
        if projection.approval_revision != self.approval.revision:
            raise ValueError("lifecycle approval revision mismatch")
        if projection.resource_revision != self.previous_session_revision + 1:
            raise ValueError("lifecycle resource revision must point at the prospective P2B state")
        if projection.intent_digest != self.approval.intent_digest:
            raise ValueError("lifecycle digest mismatch")
        if projection.revision != self.proposed_session_revision:
            raise ValueError("lifecycle revision mismatch")
        return self
