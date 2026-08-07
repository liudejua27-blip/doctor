"""Prototype confirmation and approval boundary.

The AssessmentAgent is deliberately unable to call anything in this module.
Application code must first receive the user's reviewed draft, bind it to a
session revision and digest, and only then create an ``ApprovalIntent``.  A
second explicit decision is required before the prototype records an event
receipt.  This is an in-memory proof of the state and idempotency rules from
API-01; it is not a production repository or a clinical event store.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta
import hashlib
import json
from typing import Any, Iterable, Literal, Mapping
from uuid import UUID, uuid4

from pydantic import Field, model_validator

from .policy import digest_for
from .types import (
    AssessmentDraft,
    DraftCandidate,
    EpisodeSelection,
    SafetyEvaluation,
    StrictModel,
    UserTurnInput,
    utc_now,
)


CONFIRMABLE_FIELDS: tuple[str, ...] = (
    "locations",
    "sensations",
    "temporal",
    "trend",
    "aggravating_factors",
    "relieving_factors",
    "functional_impacts",
    "background_facts",
)

ApprovalStatus = Literal[
    "pending",
    "approved",
    "executing",
    "executed",
    "denied",
    "expired",
    "invalidated",
    "failed",
]


class ResourceRef(StrictModel):
    type: Literal["event", "episode", "report", "report_share", "reminder", "approval", "session"]
    id: UUID


class ApprovalIntent(StrictModel):
    approval_id: UUID
    source_session_id: UUID
    target_ref: ResourceRef
    action_type: Literal["confirm_body_signal_event"] = "confirm_body_signal_event"
    redacted: bool = False
    display_summary: str | None = Field(default=None, min_length=1, max_length=2000)
    tombstone_reason: Literal[
        "user_discarded",
        "session_expired",
        "consent_revoked",
        "retention_expired",
        "execution_failed",
    ] | None = None
    intent_digest: str = Field(pattern=r"^sha256:[a-f0-9]{64}$")
    resource_revision: int = Field(ge=1)
    revision: int = Field(ge=1)
    status: ApprovalStatus
    created_at: datetime
    expires_at: datetime

    @model_validator(mode="after")
    def validate_projection(self) -> "ApprovalIntent":
        if self.target_ref.type != "session" or self.target_ref.id != self.source_session_id:
            raise ValueError("body-event approval must target its source session")
        if self.redacted:
            if self.display_summary is not None or self.tombstone_reason is None:
                raise ValueError("redacted approval must be a summary-free tombstone")
        elif self.display_summary is None or self.tombstone_reason is not None:
            raise ValueError("visible approval needs a display summary and no tombstone reason")
        if self.status in {"pending", "approved", "executing"} and self.redacted:
            raise ValueError("active approval cannot be redacted")
        if self.status == "expired" and not self.redacted:
            raise ValueError("expired approval must be redacted")
        if self.expires_at <= self.created_at:
            raise ValueError("approval expiry must be after creation")
        return self


class ConfirmationRequest(StrictModel):
    turn_id: UUID
    expected_revision: int = Field(ge=1)
    decision: Literal["confirm_facts"] = "confirm_facts"
    reviewed_fields: list[Literal[
        "locations",
        "sensations",
        "temporal",
        "trend",
        "aggravating_factors",
        "relieving_factors",
        "functional_impacts",
        "background_facts",
    ]] = Field(min_length=8, max_length=8)
    draft_digest: str = Field(pattern=r"^sha256:[a-f0-9]{64}$")
    episode_selection: EpisodeSelection

    @model_validator(mode="after")
    def validate_reviewed_fields(self) -> "ConfirmationRequest":
        if set(self.reviewed_fields) != set(CONFIRMABLE_FIELDS):
            raise ValueError("all eight fact groups must be reviewed exactly once")
        return self


class ApprovalDecisionRequest(StrictModel):
    decision: Literal["approve", "deny"]
    intent_digest: str = Field(pattern=r"^sha256:[a-f0-9]{64}$")
    expected_revision: int = Field(ge=1)


class PrototypeEventReceipt(StrictModel):
    """Non-production receipt proving where a formal event write would occur."""

    event_id: UUID
    source_session_id: UUID
    source_turn_id: UUID
    draft_digest: str = Field(pattern=r"^sha256:[a-f0-9]{64}$")
    lifecycle: Literal["confirmed"] = "confirmed"
    created_at: datetime


class ApprovalDecisionResult(StrictModel):
    approval_id: UUID
    action_type: Literal["confirm_body_signal_event"]
    target_ref: ResourceRef
    source_session_id: UUID
    status: Literal["executed", "denied", "invalidated", "failed"]
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
    session_snapshot: dict[str, Any] | None = None
    latest_turn: dict[str, Any] | None = None
    decided_at: datetime

    @model_validator(mode="after")
    def validate_result(self) -> "ApprovalDecisionResult":
        if self.status == "executed":
            if self.resolution_reason != "action_executed" or not self.result_refs:
                raise ValueError("executed approval needs an action result reference")
            if self.session_snapshot is None or self.latest_turn is None:
                raise ValueError("executed session approval needs recovery snapshots")
        elif self.status == "denied" and self.resolution_reason != "user_denied":
            raise ValueError("denied approval needs user_denied reason")
        elif self.status == "failed" and self.resolution_reason != "execution_failed":
            raise ValueError("failed approval needs execution_failed reason")
        elif self.status == "invalidated" and self.resolution_reason not in {
            "context_changed",
            "user_discarded",
            "session_expired",
            "consent_revoked",
        }:
            raise ValueError("invalidated approval has an invalid reason")
        if self.status != "executed" and self.result_refs:
            raise ValueError("non-executed approval cannot expose result resources")
        return self


class ConfirmationConflict(ValueError):
    """A stale, unauthorized or otherwise invalid confirmation operation."""

    def __init__(self, code: str, message: str):
        self.code = code
        super().__init__(message)


@dataclass(frozen=True)
class ConfirmationIntent:
    approval: ApprovalIntent
    candidate: DraftCandidate
    owner_id: UUID
    source_turn_id: UUID
    episode_selection: EpisodeSelection
    reviewed_fields: tuple[str, ...]
    raw_input: UserTurnInput | None = None
    agent_versions: dict[str, Any] = field(default_factory=dict)


@dataclass
class _ApprovalRecord:
    intent: ConfirmationIntent
    safety: SafetyEvaluation
    event_receipt: PrototypeEventReceipt | None = None
    terminal_result: ApprovalDecisionResult | None = None
    replay_results: dict[str, tuple[str, ApprovalDecisionResult]] = field(default_factory=dict)


def intent_digest_for(
    *,
    session_id: UUID,
    turn_id: UUID,
    resource_revision: int,
    draft_digest: str,
    reviewed_fields: Iterable[str],
    episode_selection: EpisodeSelection | None = None,
) -> str:
    payload = {
        "action_type": "confirm_body_signal_event",
        "session_id": str(session_id),
        "turn_id": str(turn_id),
        "resource_revision": resource_revision,
        "draft_digest": draft_digest,
        "reviewed_fields": sorted(reviewed_fields),
        "episode_selection": episode_selection.model_dump(mode="json", exclude_none=True)
        if episode_selection is not None
        else None,
    }
    canonical = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return "sha256:" + hashlib.sha256(canonical).hexdigest()


class PrototypeApprovalStore:
    """In-memory two-stage confirmation state machine for isolated tests."""

    def __init__(self, *, ttl: timedelta = timedelta(minutes=15), event_writer: Any | None = None) -> None:
        self.ttl = ttl
        self.event_writer = event_writer
        self._records: dict[UUID, _ApprovalRecord] = {}

    def create_intent(
        self,
        *,
        owner_id: UUID,
        session_id: UUID,
        current_revision: int,
        candidate: DraftCandidate,
        source_turn_id: UUID,
        confirmation: ConfirmationRequest,
        safety: SafetyEvaluation,
        raw_input: UserTurnInput | None = None,
        agent_versions: Mapping[str, Any] | None = None,
        now: datetime | None = None,
    ) -> ConfirmationIntent:
        if confirmation.expected_revision != current_revision:
            raise ConfirmationConflict("REVISION_MISMATCH", "session revision changed; review the draft again")
        if confirmation.turn_id != source_turn_id:
            raise ConfirmationConflict("TURN_MISMATCH", "confirmation must target the current draft turn")
        if candidate.draft_digest != confirmation.draft_digest:
            raise ConfirmationConflict("DRAFT_DIGEST_MISMATCH", "draft changed; review it again")
        if not self._eligible_for_confirmation(safety):
            raise ConfirmationConflict("SAFETY_GATE_BLOCKED", "the current safety gate does not allow confirmation")
        expected_candidate_digest = digest_for(candidate.event_draft)
        if expected_candidate_digest != candidate.draft_digest:
            raise ConfirmationConflict("DRAFT_DIGEST_MISMATCH", "typed draft digest is stale")

        timestamp = now or utc_now()
        approval_id = uuid4()
        digest = intent_digest_for(
            session_id=session_id,
            turn_id=source_turn_id,
            resource_revision=current_revision,
            draft_digest=confirmation.draft_digest,
            reviewed_fields=confirmation.reviewed_fields,
            episode_selection=confirmation.episode_selection,
        )
        approval = ApprovalIntent(
            approval_id=approval_id,
            source_session_id=session_id,
            target_ref=ResourceRef(type="session", id=session_id),
            redacted=False,
            display_summary="已复核八组身体事实，等待第二次确认保存。",
            intent_digest=digest,
            resource_revision=current_revision,
            revision=1,
            status="pending",
            created_at=timestamp,
            expires_at=timestamp + self.ttl,
        )
        intent = ConfirmationIntent(
            approval=approval,
            candidate=candidate,
            owner_id=owner_id,
            source_turn_id=source_turn_id,
            episode_selection=confirmation.episode_selection,
            reviewed_fields=tuple(confirmation.reviewed_fields),
            raw_input=raw_input,
            agent_versions=dict(agent_versions or {}),
        )
        self._records[approval_id] = _ApprovalRecord(intent=intent, safety=safety)
        return intent

    def get(self, *, owner_id: UUID, approval_id: UUID) -> ConfirmationIntent:
        record = self._records.get(approval_id)
        if record is None or record.intent.owner_id != owner_id:
            raise ConfirmationConflict("RESOURCE_NOT_FOUND", "approval not found")
        return record.intent

    def get_result(self, *, owner_id: UUID, approval_id: UUID) -> ApprovalDecisionResult | None:
        record = self._records.get(approval_id)
        if record is None or record.intent.owner_id != owner_id:
            raise ConfirmationConflict("RESOURCE_NOT_FOUND", "approval not found")
        return record.terminal_result

    def update_terminal_projection(
        self,
        *,
        owner_id: UUID,
        approval_id: UUID,
        session_snapshot: dict[str, Any],
        latest_turn: dict[str, Any],
    ) -> ApprovalDecisionResult:
        """Attach the final application projection after a decision commits.

        The event receipt is created inside :meth:`decide`, while the caller
        owns the session aggregate and its lifecycle turn. Updating the
        stored terminal result in the same application transaction keeps GET
        recovery and idempotent replay consistent without letting the Agent
        touch either side.
        """

        record = self._records.get(approval_id)
        if record is None or record.intent.owner_id != owner_id or record.terminal_result is None:
            raise ConfirmationConflict("RESULT_NOT_READY", "approval has no terminal result")
        result = record.terminal_result.model_copy(
            update={"session_snapshot": session_snapshot, "latest_turn": latest_turn}
        )
        record.terminal_result = result
        record.replay_results = {
            key: (request_hash, result) for key, (request_hash, _old_result) in record.replay_results.items()
        }
        return result

    def decide(
        self,
        *,
        owner_id: UUID,
        approval_id: UUID,
        request: ApprovalDecisionRequest,
        idempotency_key: str,
        current_session_revision: int,
        session_snapshot: dict[str, Any],
        latest_turn: dict[str, Any],
        now: datetime | None = None,
    ) -> ApprovalDecisionResult:
        if not idempotency_key.strip() or len(idempotency_key) > 200:
            raise ConfirmationConflict("IDEMPOTENCY_KEY_REQUIRED", "a bounded idempotency key is required")
        record = self._records.get(approval_id)
        if record is None or record.intent.owner_id != owner_id:
            raise ConfirmationConflict("RESOURCE_NOT_FOUND", "approval not found")

        request_hash = _request_digest(request)
        replay = record.replay_results.get(idempotency_key)
        if replay is not None:
            stored_hash, result = replay
            if stored_hash != request_hash:
                raise ConfirmationConflict("IDEMPOTENCY_CONFLICT", "idempotency key was reused for another request")
            return result

        intent = record.intent.approval
        if request.intent_digest != intent.intent_digest:
            raise ConfirmationConflict("INTENT_DIGEST_MISMATCH", "approval intent changed; refresh before deciding")

        if record.terminal_result is not None:
            # A terminal approval is safely replayable even when the caller uses
            # a new network key; it must never create a second event.
            record.replay_results[idempotency_key] = (request_hash, record.terminal_result)
            return record.terminal_result

        if intent.status != "pending":
            raise ConfirmationConflict("APPROVAL_NOT_PENDING", "approval is no longer pending")
        if request.expected_revision != intent.revision:
            raise ConfirmationConflict("APPROVAL_REVISION_MISMATCH", "approval revision changed")
        if current_session_revision != intent.resource_revision:
            result = self._invalidate(record, "context_changed", session_snapshot, latest_turn, now=now)
            record.replay_results[idempotency_key] = (request_hash, result)
            return result

        if request.decision == "deny":
            result = self._finish(
                record,
                status="denied",
                reason="user_denied",
                revision=intent.revision + 1,
                result_refs=[],
                session_snapshot=session_snapshot,
                latest_turn=latest_turn,
                now=now,
            )
        else:
            # The persisted state chain is pending(1) -> approved(2) ->
            # executing(3) -> executed(4). Only the final projection is
            # returned, but the revision arithmetic remains observable.
            if self.event_writer is None:
                event_id = uuid4()
            else:
                if record.intent.raw_input is None:
                    raise ConfirmationConflict(
                        "EVENT_WRITE_FAILED",
                        "the confirmed-event projection is missing the server-stored raw input",
                    )
                try:
                    event_id = self.event_writer.commit_confirmed(
                        owner_id=owner_id,
                        approval_id=intent.approval_id,
                        event_id=uuid4(),
                        session_id=intent.source_session_id,
                        source_turn_id=record.intent.source_turn_id,
                        candidate=record.intent.candidate,
                        safety=record.safety,
                        raw_input=record.intent.raw_input,
                        episode_selection=record.intent.episode_selection,
                        intent_digest=intent.intent_digest,
                        reviewed_fields=record.intent.reviewed_fields,
                        agent_versions=record.intent.agent_versions,
                        now=now or utc_now(),
                    )
                except ConfirmationConflict:
                    raise
                except Exception as exc:  # noqa: BLE001 - hide persistence details
                    raise ConfirmationConflict("EVENT_WRITE_FAILED", "confirmed event transaction failed") from exc
            event = PrototypeEventReceipt(
                event_id=event_id,
                source_session_id=intent.source_session_id,
                source_turn_id=record.intent.source_turn_id,
                draft_digest=record.intent.candidate.draft_digest,
                created_at=now or utc_now(),
            )
            record.event_receipt = event
            result = self._finish(
                record,
                status="executed",
                reason="action_executed",
                revision=intent.revision + 3,
                result_refs=[ResourceRef(type="event", id=event.event_id)],
                session_snapshot=session_snapshot,
                latest_turn=latest_turn,
                now=now,
            )
        record.replay_results[idempotency_key] = (request_hash, result)
        return result

    @staticmethod
    def _eligible_for_confirmation(safety: SafetyEvaluation) -> bool:
        return (
            safety.status == "complete"
            and safety.tier in {"R2", "R3"}
            and safety.scenario_support == "supported"
            and not safety.unresolved_safety
        )

    def _invalidate(
        self,
        record: _ApprovalRecord,
        reason: Literal["context_changed", "user_discarded", "session_expired", "consent_revoked"],
        session_snapshot: dict[str, Any],
        latest_turn: dict[str, Any],
        *,
        now: datetime | None,
    ) -> ApprovalDecisionResult:
        return self._finish(
            record,
            status="invalidated",
            reason=reason,
            revision=record.intent.approval.revision + 1,
            result_refs=[],
            session_snapshot=session_snapshot,
            latest_turn=latest_turn,
            now=now,
        )

    def _finish(
        self,
        record: _ApprovalRecord,
        *,
        status: Literal["executed", "denied", "invalidated", "failed"],
        reason: Literal[
            "action_executed",
            "user_denied",
            "context_changed",
            "user_discarded",
            "session_expired",
            "consent_revoked",
            "execution_failed",
        ],
        revision: int,
        result_refs: list[ResourceRef],
        session_snapshot: dict[str, Any],
        latest_turn: dict[str, Any],
        now: datetime | None,
    ) -> ApprovalDecisionResult:
        old = record.intent.approval
        # An invalidated approval still has a recoverable, non-health summary
        # until the separate retention/consent cleanup path tombstones it.
        # Do not conflate lifecycle invalidation with redaction; production
        # cleanup will create a later redacted revision when authorized.
        redacted = False
        record.intent = ConfirmationIntent(
            approval=old.model_copy(
                update={
                    "status": status,
                    "revision": revision,
                    "redacted": redacted,
                    "display_summary": old.display_summary,
                    "tombstone_reason": None,
                }
            ),
            candidate=record.intent.candidate,
            owner_id=record.intent.owner_id,
            source_turn_id=record.intent.source_turn_id,
            episode_selection=record.intent.episode_selection,
            reviewed_fields=record.intent.reviewed_fields,
            raw_input=record.intent.raw_input,
            agent_versions=record.intent.agent_versions,
        )
        result = ApprovalDecisionResult(
            approval_id=old.approval_id,
            action_type=old.action_type,
            target_ref=old.target_ref,
            source_session_id=old.source_session_id,
            status=status,
            resolution_reason=reason,
            revision=revision,
            result_refs=result_refs,
            session_snapshot=session_snapshot,
            latest_turn=latest_turn,
            decided_at=now or utc_now(),
        )
        record.terminal_result = result
        return result


def _request_digest(request: ApprovalDecisionRequest) -> str:
    payload = request.model_dump(mode="json")
    canonical = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()
