"""Typed P2D confirmation transaction contract.

The models in this module describe the smallest metadata-only plan that a
future durable repository must accept.  They deliberately do not contain a
candidate, raw input, Safety answer, or Event body.  The prototype repository
used by tests is not a persistence implementation and must never be exposed
through the public API.
"""

from __future__ import annotations

from datetime import datetime
from typing import Iterable, Literal
from uuid import UUID

from pydantic import Field, model_validator

from .approval_decision_application import ApprovalDecisionApplicationResult
from .confirmation import ApprovalIntent, ResourceRef
from .confirmation_application import ConfirmationIntentApplicationResult
from .types import StrictModel


TransactionOutcome = Literal["committed", "replayed", "rejected", "in_progress"]
TerminalStatus = Literal["executed", "denied", "invalidated", "failed"]
LifecycleStatus = Literal["completed", "approval_decided", "failed"]
LifecycleState = Literal["completed", "awaiting_confirmation", "failed"]
WriteSetEntry = Literal["session", "approval", "lifecycle_turn", "event", "episode", "audit_metadata"]


class ConfirmationTransactionSessionSnapshot(StrictModel):
    """Server-owned pre-commit Session metadata; never a client assertion."""

    session_id: UUID
    state: Literal["awaiting_approval", "completed", "awaiting_confirmation", "failed"]
    revision: int = Field(ge=1)
    latest_turn_id: UUID
    latest_sequence: int = Field(ge=1)

    @model_validator(mode="after")
    def validate_ids(self) -> "ConfirmationTransactionSessionSnapshot":
        if self.session_id.int == 0 or self.latest_turn_id.int == 0:
            raise ValueError("transaction Session IDs must be non-zero")
        return self


class ConfirmationTransactionApprovalSnapshot(StrictModel):
    """Server-owned Approval precondition with no candidate or raw content."""

    approval_id: UUID
    source_session_id: UUID
    source_turn_id: UUID
    status: Literal["pending", "executed", "denied", "invalidated", "failed"]
    revision: int = Field(ge=1)
    resource_revision: int = Field(ge=1)
    intent_digest: str = Field(pattern=r"^sha256:[a-f0-9]{64}$")

    @model_validator(mode="after")
    def validate_ids(self) -> "ConfirmationTransactionApprovalSnapshot":
        if self.approval_id.int == 0 or self.source_session_id.int == 0 or self.source_turn_id.int == 0:
            raise ValueError("transaction Approval IDs must be non-zero")
        return self


class ConfirmationTransactionPlan(StrictModel):
    """Canonical metadata-only write plan for one approval decision."""

    schema_version: Literal["1.0"] = "1.0"
    transaction_id: UUID
    session_id: UUID
    approval_id: UUID
    source_turn_id: UUID
    request_digest: str = Field(pattern=r"^sha256:[a-f0-9]{64}$")
    expected_session_revision: int = Field(ge=1)
    committed_session_revision: int = Field(ge=1)
    approval_revision: int = Field(ge=1)
    terminal_status: TerminalStatus
    lifecycle_status: LifecycleStatus
    lifecycle_state: LifecycleState
    lifecycle_turn_id: UUID
    write_set: list[WriteSetEntry] = Field(default_factory=list, max_length=6)
    result_refs: list[ResourceRef] = Field(default_factory=list, max_length=2)
    atomicity: Literal["all_or_nothing"] = "all_or_nothing"

    @model_validator(mode="after")
    def validate_plan(self) -> "ConfirmationTransactionPlan":
        if self.transaction_id.int == 0 or self.session_id.int == 0 or self.approval_id.int == 0:
            raise ValueError("transaction plan IDs must be non-zero")
        if self.source_turn_id.int == 0 or self.lifecycle_turn_id.int == 0:
            raise ValueError("transaction plan Turn IDs must be non-zero")
        if len(set(self.write_set)) != len(self.write_set):
            raise ValueError("transaction write set must be unique")
        if self.committed_session_revision != self.expected_session_revision + 1:
            raise ValueError("transaction must advance Session revision exactly once")
        if self.terminal_status == "executed":
            if self.lifecycle_status != "completed" or self.lifecycle_state != "completed":
                raise ValueError("executed transaction must complete")
            if len(self.result_refs) != 1 or self.result_refs[0].type != "event":
                raise ValueError("executed transaction requires one event result")
            if "event" not in self.write_set or "episode" not in self.write_set:
                raise ValueError("executed transaction must include Event and Episode write intents")
        elif self.terminal_status in {"denied", "invalidated"}:
            if self.lifecycle_status != "approval_decided" or self.lifecycle_state != "awaiting_confirmation":
                raise ValueError("denied/invalidated transaction must return to confirmation")
            if self.result_refs or "event" in self.write_set or "episode" in self.write_set:
                raise ValueError("denied/invalidated transaction cannot write Event/Episode")
        else:
            if self.lifecycle_status != "failed" or self.lifecycle_state != "failed":
                raise ValueError("failed transaction must remain failed")
            if self.result_refs or "event" in self.write_set or "episode" in self.write_set:
                raise ValueError("failed transaction cannot write Event/Episode")
        required = {"session", "lifecycle_turn", "audit_metadata"}
        if not required.issubset(self.write_set):
            raise ValueError("transaction write set is missing required metadata writes")
        return self


class ConfirmationTransactionReceipt(StrictModel):
    """Metadata-only outcome; not a public response or persistence proof."""

    schema_version: Literal["1.0"] = "1.0"
    outcome: TransactionOutcome
    transaction_id: UUID
    session_id: UUID
    approval_id: UUID
    request_digest: str = Field(pattern=r"^sha256:[a-f0-9]{64}$")
    expected_session_revision: int = Field(ge=1)
    committed_session_revision: int = Field(ge=1)
    approval_revision: int = Field(ge=1)
    lifecycle_status: LifecycleStatus
    lifecycle_state: LifecycleState
    write_set: list[WriteSetEntry] = Field(default_factory=list, max_length=6)
    result_refs: list[ResourceRef] = Field(default_factory=list, max_length=2)
    atomicity: Literal["all_or_nothing"] = "all_or_nothing"
    replayed: bool = False
    failure_code: str | None = Field(default=None, pattern=r"^[A-Z0-9._-]{1,120}$")
    created_at: datetime

    @model_validator(mode="after")
    def validate_receipt(self) -> "ConfirmationTransactionReceipt":
        if self.transaction_id.int == 0 or self.session_id.int == 0 or self.approval_id.int == 0:
            raise ValueError("transaction receipt IDs must be non-zero")
        if self.committed_session_revision != self.expected_session_revision + 1:
            raise ValueError("receipt must preserve one Session revision increment")
        if len(set(self.write_set)) != len(self.write_set):
            raise ValueError("receipt write set must be unique")
        if self.outcome in {"committed", "replayed"}:
            if not self.write_set:
                raise ValueError("committed receipt requires a write set")
            if self.failure_code is not None:
                raise ValueError("committed receipt cannot carry failure_code")
        elif self.outcome == "rejected":
            if self.write_set or self.result_refs or self.failure_code is None or self.replayed:
                raise ValueError("rejected receipt must be a zero-write failure")
        elif self.outcome == "in_progress":
            if self.write_set or self.result_refs or self.failure_code is None or self.replayed:
                raise ValueError("in-progress receipt cannot claim a write")
        if self.lifecycle_status == "completed":
            if self.lifecycle_state != "completed" or len(self.result_refs) != 1 or self.result_refs[0].type != "event":
                raise ValueError("completed receipt requires one Event ref")
            if "event" not in self.write_set or "episode" not in self.write_set:
                raise ValueError("completed receipt must include Event/Episode write intents")
        elif self.lifecycle_status in {"approval_decided", "failed"}:
            if self.lifecycle_state not in {"awaiting_confirmation", "failed"} or self.result_refs:
                raise ValueError("non-completed receipt cannot expose result refs")
            if "event" in self.write_set or "episode" in self.write_set:
                raise ValueError("non-completed receipt cannot include Event/Episode writes")
        return self


def write_set_for_status(status: TerminalStatus) -> list[WriteSetEntry]:
    """Return the only write-set shape P2D permits for a terminal result."""

    common: list[WriteSetEntry] = ["session", "lifecycle_turn", "audit_metadata"]
    if status in {"denied", "invalidated"}:
        return [*common[:2], "approval", common[2]]
    if status == "executed":
        return [*common[:2], "approval", "event", "episode", common[2]]
    return common


def validate_p2d_relations(
    *,
    p2b: ConfirmationIntentApplicationResult,
    p2c: ApprovalDecisionApplicationResult,
    session: ConfirmationTransactionSessionSnapshot,
    approval: ConfirmationTransactionApprovalSnapshot,
) -> None:
    """Validate source/revision/status relations before a repository call."""

    if session.session_id != p2b.source_session_id or session.session_id != p2c.source_session_id:
        raise ValueError("transaction Session source binding mismatch")
    if session.state != "awaiting_approval":
        raise ValueError("transaction Session is not awaiting approval")
    if session.revision != p2b.proposed_session_revision:
        raise ValueError("transaction Session revision is stale")
    if p2c.previous_session_revision != p2b.previous_session_revision:
        raise ValueError("P2C previous Session revision mismatch")
    if p2c.proposed_session_revision != session.revision + 1:
        raise ValueError("P2C committed Session revision must advance once")
    if approval.approval_id != p2b.approval.approval_id or approval.approval_id != p2c.approval.approval_id:
        raise ValueError("transaction Approval binding mismatch")
    if approval.source_session_id != session.session_id or approval.source_turn_id != p2b.source_turn_id:
        raise ValueError("transaction Approval source mismatch")
    if approval.status != "pending" or approval.revision != p2b.approval.revision:
        raise ValueError("transaction Approval is not the pending P2B revision")
    if approval.resource_revision != p2b.previous_session_revision:
        raise ValueError("transaction Approval resource revision mismatch")
    if approval.intent_digest != p2b.approval.intent_digest or approval.intent_digest != p2c.approval.intent_digest:
        raise ValueError("transaction intent digest mismatch")
    if p2c.source_turn_id != p2b.source_turn_id:
        raise ValueError("transaction source Turn mismatch")
    lifecycle = p2c.lifecycle
    if lifecycle.session_id != session.session_id or lifecycle.source_turn_id != p2b.source_turn_id:
        raise ValueError("transaction lifecycle source mismatch")
    if lifecycle.revision != p2c.proposed_session_revision or lifecycle.approval_id != approval.approval_id:
        raise ValueError("transaction lifecycle revision or Approval mismatch")
    if lifecycle.intent_digest != approval.intent_digest or lifecycle.result_refs != p2c.decision.result_refs:
        raise ValueError("transaction lifecycle result mismatch")


def validate_p2d_replay_identity(
    *,
    p2b: ConfirmationIntentApplicationResult,
    p2c: ApprovalDecisionApplicationResult,
    session: ConfirmationTransactionSessionSnapshot,
    approval: ConfirmationTransactionApprovalSnapshot,
) -> None:
    """Validate immutable source identity before an idempotent replay lookup.

    A retry may observe the Session/Approval after the first transaction has
    reached a terminal state.  Replay lookup therefore cannot require the
    original ``awaiting_approval`` state, but it must still bind every source
    and digest relation before returning a stored receipt.
    """

    if session.session_id != p2b.source_session_id or session.session_id != p2c.source_session_id:
        raise ValueError("transaction Session source binding mismatch")
    if approval.approval_id != p2b.approval.approval_id or approval.approval_id != p2c.approval.approval_id:
        raise ValueError("transaction Approval binding mismatch")
    if approval.source_session_id != session.session_id or approval.source_turn_id != p2b.source_turn_id:
        raise ValueError("transaction Approval source mismatch")
    if approval.intent_digest != p2b.approval.intent_digest or approval.intent_digest != p2c.approval.intent_digest:
        raise ValueError("transaction intent digest mismatch")
    if p2c.source_turn_id != p2b.source_turn_id:
        raise ValueError("transaction source Turn mismatch")
    lifecycle = p2c.lifecycle
    if lifecycle.session_id != session.session_id or lifecycle.source_turn_id != p2b.source_turn_id:
        raise ValueError("transaction lifecycle source mismatch")
    if lifecycle.approval_id != approval.approval_id:
        raise ValueError("transaction lifecycle Approval mismatch")
    if lifecycle.intent_digest != approval.intent_digest or lifecycle.result_refs != p2c.decision.result_refs:
        raise ValueError("transaction lifecycle result mismatch")
