"""Typed Session/Turn projection boundary for the P2A prototype.

P2A is deliberately narrower than the public ``AssessmentSession`` model and
the P2 confirmation/Event store.  It accepts only a validated P1H result,
keeps owner identity in a server-side index, and stores the minimum
unconfirmed projection needed for a later application layer.  The ledger is
process-local and must not be treated as durable persistence.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta
import hashlib
import json
import re
from threading import RLock
from typing import Literal
from uuid import UUID, uuid4

from pydantic import Field, ValidationError, model_validator

from .agent_turn_application import AgentTurnApplicationResult
from .types import AgentCandidate, StrictModel, utc_now


SessionProjectionState = Literal[
    "created",
    "awaiting_user",
    "awaiting_confirmation",
    "safety_action_required",
    "offline_only",
    "failed",
]
TurnProjectionState = Literal[
    "awaiting_user",
    "awaiting_confirmation",
    "safety_action_required",
    "offline_only",
    "failed",
]
ProjectionOutputKind = Literal[
    "ask_question",
    "draft_ready",
    "safety_action_required",
    "offline_only",
    "failed",
]
ProjectionTransition = Literal["initial_turn", "continuation"]

_IDEMPOTENCY_KEY = re.compile(r"^[\x21-\x7e]{8,128}$")


class SessionTurnProjectionConflict(ValueError):
    """Stable domain error for the P2A CAS and ownership boundary."""

    def __init__(self, code: str, message: str):
        self.code = code
        super().__init__(message)


class SessionProjection(StrictModel):
    """Client-safe Session snapshot with no server-side owner field."""

    schema_version: Literal["1.0"] = "1.0"
    session_id: UUID
    purpose: Literal["body_signal_assessment"] = "body_signal_assessment"
    workflow: Literal["assessment"] = "assessment"
    state: SessionProjectionState
    revision: int = Field(ge=1)
    latest_turn_id: UUID | None = None
    latest_sequence: int = Field(ge=0)
    latest_draft_revision: int = Field(ge=0)
    created_at: datetime
    updated_at: datetime
    expires_at: datetime

    @model_validator(mode="after")
    def validate_lifecycle(self) -> "SessionProjection":
        if self.updated_at < self.created_at:
            raise ValueError("session updated_at cannot precede created_at")
        if self.expires_at <= self.created_at:
            raise ValueError("session expiry must be after creation")
        if self.state == "created":
            if self.latest_turn_id is not None or self.latest_sequence != 0 or self.latest_draft_revision != 0:
                raise ValueError("created session cannot have a latest Turn")
        elif self.latest_turn_id is None or self.latest_sequence < 1 or self.latest_draft_revision < 1:
            raise ValueError("active projection state requires a latest Turn")
        return self


class TurnProjection(StrictModel):
    """Minimal unconfirmed Turn projection used by the internal ledger."""

    schema_version: Literal["1.0"] = "1.0"
    turn_id: UUID
    session_id: UUID
    sequence: int = Field(ge=1)
    revision: int = Field(ge=2)
    in_reply_to_turn_id: UUID | None = None
    state: TurnProjectionState
    output_kind: ProjectionOutputKind
    handoff_status: Literal["ready_for_agent", "safety_action_required", "offline_only"]
    agent_result_status: Literal[
        "agent_completed",
        "agent_output_rejected",
        "agent_unavailable",
        "safety_action_required",
        "offline_only",
    ]
    candidate: AgentCandidate | None = None
    agent_source_ids: list[str] = Field(default_factory=list, max_length=100)
    agent_version: str | None = Field(default=None, min_length=1, max_length=64)
    prompt_version: str | None = Field(default=None, min_length=1, max_length=64)
    draft_revision: int = Field(ge=1)
    created_at: datetime

    @model_validator(mode="after")
    def validate_projection(self) -> "TurnProjection":
        if self.session_id.int == 0 or self.turn_id.int == 0:
            raise ValueError("projection IDs must be non-zero")
        if self.output_kind in {"ask_question", "draft_ready"}:
            if self.agent_result_status != "agent_completed" or self.handoff_status != "ready_for_agent":
                raise ValueError("Agent candidate projection requires completed ready status")
            if self.candidate is None or self.candidate.kind != self.output_kind:
                raise ValueError("candidate kind must match projection output_kind")
            if not self.agent_version or not self.prompt_version:
                raise ValueError("Agent candidate projection requires version metadata")
            if self.state != ("awaiting_user" if self.output_kind == "ask_question" else "awaiting_confirmation"):
                raise ValueError("candidate output kind and projection state disagree")
        elif self.candidate is not None or self.agent_version is not None or self.prompt_version is not None:
            raise ValueError("fallback projection cannot carry candidate or Agent metadata")
        if self.output_kind == "safety_action_required" and (
            self.state != "safety_action_required" or self.handoff_status != "safety_action_required"
        ):
            raise ValueError("safety projection must preserve the safety stop")
        if self.output_kind == "offline_only" and (
            self.state != "offline_only" or self.handoff_status != "offline_only"
        ):
            raise ValueError("offline projection must preserve the offline stop")
        if self.output_kind == "failed" and self.state != "failed":
            raise ValueError("failed projection must preserve the failure state")
        return self


class SessionTurnProjectionResult(StrictModel):
    """Stable result; transport replay metadata is intentionally external."""

    schema_version: Literal["1.0"] = "1.0"
    session: SessionProjection
    turn: TurnProjection
    transition: ProjectionTransition
    created_at: datetime

    @model_validator(mode="after")
    def validate_relation(self) -> "SessionTurnProjectionResult":
        if self.session.session_id != self.turn.session_id:
            raise ValueError("Session and Turn must belong to the same session")
        if self.session.latest_turn_id != self.turn.turn_id:
            raise ValueError("result Session must point to its latest Turn")
        if self.session.latest_sequence != self.turn.sequence:
            raise ValueError("result Session sequence must match its Turn")
        if self.session.revision != self.turn.revision:
            raise ValueError("result Session revision must match its Turn revision")
        if self.session.latest_draft_revision != self.turn.draft_revision:
            raise ValueError("result draft revision must match its Turn")
        return self


@dataclass(frozen=True)
class SessionTurnProjectionResponse:
    result: SessionTurnProjectionResult
    replayed: bool = False


@dataclass(frozen=True)
class SessionStartResponse:
    session: SessionProjection
    replayed: bool = False


@dataclass(frozen=True)
class _LedgerEntry:
    request_digest: str
    result: SessionTurnProjectionResult


@dataclass
class _SessionRecord:
    owner_user_id: UUID
    session: SessionProjection
    latest_turn: TurnProjection | None = None
    by_key: dict[str, _LedgerEntry] = field(default_factory=dict)
    by_turn_sequence: dict[tuple[UUID, int], _LedgerEntry] = field(default_factory=dict)


class P2ASessionTurnLedger:
    """Process-local typed Session/Turn ledger for P2A tests only."""

    def __init__(self, *, ttl: timedelta = timedelta(minutes=15)) -> None:
        self.ttl = ttl
        self._records: dict[UUID, _SessionRecord] = {}
        self._start_by_key: dict[tuple[UUID, str], tuple[str, SessionProjection]] = {}
        self._lock = RLock()

    def create_session(
        self,
        *,
        owner_user_id: UUID,
        idempotency_key: str,
        session_id: UUID | None = None,
        now: datetime | None = None,
    ) -> SessionStartResponse:
        _validate_idempotency_key(idempotency_key)
        timestamp = now or utc_now()
        session_id = session_id or uuid4()
        expires_at = timestamp + self.ttl
        digest = _start_digest(session_id=session_id)
        with self._lock:
            replay = self._start_by_key.get((owner_user_id, idempotency_key))
            if replay is not None:
                stored_digest, session = replay
                if stored_digest != digest:
                    raise SessionTurnProjectionConflict(
                        "P2A_IDEMPOTENCY_KEY_REUSED", "idempotency key was reused for another Session request"
                    )
                return SessionStartResponse(session=session.model_copy(deep=True), replayed=True)
            existing = self._records.get(session_id)
            if existing is not None:
                if existing.owner_user_id != owner_user_id:
                    raise SessionTurnProjectionConflict("P2A_SESSION_OWNER_MISMATCH", "Session owner mismatch")
                raise SessionTurnProjectionConflict("P2A_SESSION_ALREADY_EXISTS", "Session already exists")
            session = SessionProjection(
                session_id=session_id,
                state="created",
                revision=1,
                latest_sequence=0,
                latest_draft_revision=0,
                created_at=timestamp,
                updated_at=timestamp,
                expires_at=expires_at,
            )
            self._records[session_id] = _SessionRecord(owner_user_id=owner_user_id, session=session)
            self._start_by_key[(owner_user_id, idempotency_key)] = (digest, session)
            return SessionStartResponse(session=session.model_copy(deep=True))

    def get_session(self, *, owner_user_id: UUID, session_id: UUID) -> SessionProjection:
        with self._lock:
            record = self._owned_record(owner_user_id=owner_user_id, session_id=session_id)
            return record.session.model_copy(deep=True)

    def get_latest_turn(self, *, owner_user_id: UUID, session_id: UUID) -> TurnProjection:
        with self._lock:
            record = self._owned_record(owner_user_id=owner_user_id, session_id=session_id)
            if record.latest_turn is None:
                raise SessionTurnProjectionConflict("P2A_TURN_NOT_FOUND", "Session has no accepted Turn")
            return record.latest_turn.model_copy(deep=True)

    def apply(
        self,
        *,
        owner_user_id: UUID,
        result: AgentTurnApplicationResult,
        expected_revision: int,
        idempotency_key: str,
        now: datetime | None = None,
    ) -> SessionTurnProjectionResponse:
        _validate_idempotency_key(idempotency_key)
        timestamp = now or utc_now()
        try:
            validated = AgentTurnApplicationResult.model_validate(
                result.model_dump(mode="python") if isinstance(result, AgentTurnApplicationResult) else result
            )
        except (ValidationError, TypeError, ValueError) as exc:
            raise SessionTurnProjectionConflict(
                "P2A_P1H_RESULT_REJECTED", "P1H result failed validation and was not persisted"
            ) from exc
        if validated.status != "accepted":
            raise SessionTurnProjectionConflict("P2A_P1H_RESULT_REJECTED", "rejected P1H result cannot be projected")

        with self._lock:
            record = self._owned_record(owner_user_id=owner_user_id, session_id=validated.session_id)
            # A caller clock can be behind the Session clock (for example
            # after an offline retry).  Keep the projection monotonic instead
            # of manufacturing an updated_at earlier than created_at.
            timestamp = max(timestamp, record.session.updated_at)
            if timestamp >= record.session.expires_at:
                raise SessionTurnProjectionConflict("P2A_SESSION_EXPIRED", "Session projection has expired")
            request_digest = _apply_digest(
                result=validated, expected_revision=expected_revision, owner_user_id=owner_user_id
            )
            existing = record.by_key.get(idempotency_key)
            if existing is not None:
                if existing.request_digest != request_digest:
                    raise SessionTurnProjectionConflict(
                        "P2A_IDEMPOTENCY_KEY_REUSED", "idempotency key was reused for another Turn request"
                    )
                return SessionTurnProjectionResponse(existing.result, replayed=True)
            turn_key = (validated.turn_id, validated.sequence)
            if turn_key in record.by_turn_sequence:
                raise SessionTurnProjectionConflict("P2A_TURN_ALREADY_APPLIED", "Turn sequence was already applied")
            if expected_revision != record.session.revision:
                raise SessionTurnProjectionConflict("P2A_REVISION_MISMATCH", "Session revision changed")
            self._validate_order(record=record, result=validated)
            next_revision = record.session.revision + 1
            turn = _turn_projection(result=validated, revision=next_revision)
            next_session = record.session.model_copy(
                update={
                    "state": validated.state,
                    "revision": next_revision,
                    "latest_turn_id": turn.turn_id,
                    "latest_sequence": turn.sequence,
                    "latest_draft_revision": turn.draft_revision,
                    "updated_at": timestamp,
                },
                deep=True,
            )
            projection = SessionTurnProjectionResult(
                session=next_session,
                turn=turn,
                transition="initial_turn" if record.latest_turn is None else "continuation",
                created_at=timestamp,
            )
            entry = _LedgerEntry(request_digest=request_digest, result=projection)
            record.session = next_session
            record.latest_turn = turn
            record.by_key[idempotency_key] = entry
            record.by_turn_sequence[turn_key] = entry
            return SessionTurnProjectionResponse(projection)

    def clear(self) -> None:
        with self._lock:
            self._records.clear()
            self._start_by_key.clear()

    @property
    def ledger_entry_count(self) -> int:
        with self._lock:
            return sum(len(record.by_key) for record in self._records.values())

    def _owned_record(self, *, owner_user_id: UUID, session_id: UUID) -> _SessionRecord:
        record = self._records.get(session_id)
        if record is None:
            raise SessionTurnProjectionConflict("P2A_SESSION_NOT_FOUND", "Session not found")
        if record.owner_user_id != owner_user_id:
            raise SessionTurnProjectionConflict("P2A_SESSION_OWNER_MISMATCH", "Session owner mismatch")
        return record

    @staticmethod
    def _validate_order(*, record: _SessionRecord, result: AgentTurnApplicationResult) -> None:
        if record.latest_turn is None:
            if result.sequence != 1 or result.in_reply_to_turn_id is not None:
                raise SessionTurnProjectionConflict("P2A_PREDECESSOR_MISMATCH", "first Turn must not have a predecessor")
            return
        if record.session.state != "awaiting_user":
            raise SessionTurnProjectionConflict(
                "P2A_CONTINUATION_NOT_ALLOWED", "current Session state cannot accept another Agent Turn"
            )
        if result.in_reply_to_turn_id != record.latest_turn.turn_id:
            raise SessionTurnProjectionConflict("P2A_PREDECESSOR_MISMATCH", "Turn is not the direct predecessor")
        if result.sequence != record.latest_turn.sequence + 1:
            raise SessionTurnProjectionConflict("P2A_SEQUENCE_MISMATCH", "Turn sequence is not monotonic")
        if result.draft_revision <= record.latest_turn.draft_revision:
            raise SessionTurnProjectionConflict("P2A_REVISION_MISMATCH", "draft revision must increase")


def _validate_idempotency_key(key: str) -> None:
    if not isinstance(key, str) or _IDEMPOTENCY_KEY.fullmatch(key) is None:
        raise SessionTurnProjectionConflict("P2A_INVALID_IDEMPOTENCY_KEY", "bounded idempotency key required")


def _start_digest(*, session_id: UUID) -> str:
    return _digest(
        {
            "operation": "start_session",
            "session_id": str(session_id),
        }
    )


def _apply_digest(*, result: AgentTurnApplicationResult, expected_revision: int, owner_user_id: UUID) -> str:
    return _digest(
        {
            "operation": "apply_turn",
            "owner_user_id": str(owner_user_id),
            "expected_revision": expected_revision,
            "result": result.model_dump(mode="json", exclude_none=True),
        }
    )


def _digest(value: dict[str, object]) -> str:
    canonical = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return "sha256:" + hashlib.sha256(canonical).hexdigest()


def _turn_projection(*, result: AgentTurnApplicationResult, revision: int) -> TurnProjection:
    if result.candidate is not None:
        output_kind: ProjectionOutputKind = result.candidate.kind
    elif result.agent_result_status == "safety_action_required":
        output_kind = "safety_action_required"
    elif result.agent_result_status == "offline_only":
        output_kind = "offline_only"
    else:
        output_kind = "failed"
    return TurnProjection(
        turn_id=result.turn_id,
        session_id=result.session_id,
        sequence=result.sequence,
        revision=revision,
        in_reply_to_turn_id=result.in_reply_to_turn_id,
        state=result.state,  # type: ignore[arg-type]
        output_kind=output_kind,
        handoff_status=result.handoff_status,  # type: ignore[arg-type]
        agent_result_status=result.agent_result_status,  # type: ignore[arg-type]
        candidate=result.candidate,
        agent_source_ids=list(result.agent_source_ids),
        agent_version=result.agent_version,
        prompt_version=result.prompt_version,
        draft_revision=result.draft_revision,
        created_at=result.created_at,
    )
