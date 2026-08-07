"""P2B confirmation-to-ApprovalIntent application boundary.

This service is an internal, feature-flagged prototype.  It accepts a
validated P2A draft projection plus server-owned safety/input dependencies,
then creates one pending in-memory ApprovalIntent.  It never approves the
intent and never writes Event/Episode resources.
"""

from __future__ import annotations

from dataclasses import dataclass, field, replace
from datetime import datetime
import hashlib
import json
import re
from threading import RLock
from typing import Any, Mapping
from uuid import UUID, uuid4

from pydantic import ValidationError

from ..domain.confirmation import (
    ApprovalIntent,
    ConfirmationConflict,
    ConfirmationRequest,
    PrototypeApprovalStore,
)
from ..domain.confirmation_application import (
    ApprovalRequiredProjection,
    ConfirmationIntentApplicationResult,
)
from ..domain.policy import digest_for
from ..domain.session_turn_projection import SessionTurnProjectionResult
from ..domain.types import DraftCandidate, SafetyEvaluation, UserTurnInput, utc_now


P2B_FEATURE_FLAG = "P2B_CONFIRMATION_INTENT_APPLICATION_PROTOTYPE"
_IDEMPOTENCY_KEY = re.compile(r"^[\x21-\x7e]{8,128}$")


class P2BConfirmationIntentApplicationConflict(ValueError):
    """Stable P2B error with no health-data content in its message."""

    def __init__(self, code: str, message: str):
        self.code = code
        super().__init__(message)


@dataclass(frozen=True)
class P2BConfirmationRequest:
    owner_user_id: UUID
    p2a_result: SessionTurnProjectionResult
    confirmation: ConfirmationRequest
    safety: SafetyEvaluation
    server_raw_input: UserTurnInput
    agent_versions: Mapping[str, Any] = field(default_factory=dict)
    idempotency_key: str = ""
    now: datetime | None = None


@dataclass(frozen=True)
class P2BConfirmationResponse:
    result: ConfirmationIntentApplicationResult
    replayed: bool = False


@dataclass(frozen=True)
class _P2BRecord:
    request_digest: str
    result: ConfirmationIntentApplicationResult


class P2BConfirmationIntentApplicationService:
    """Apply one typed draft review to a single pending ApprovalIntent."""

    def __init__(
        self,
        *,
        enabled: bool = False,
        approval_store: PrototypeApprovalStore | None = None,
    ) -> None:
        self.enabled = enabled
        self.approval_store = approval_store or PrototypeApprovalStore()
        self._lock = RLock()
        self._owners: dict[UUID, UUID] = {}
        self._by_key: dict[tuple[UUID, UUID, str], _P2BRecord] = {}
        self._by_source: dict[tuple[UUID, UUID, UUID], _P2BRecord] = {}

    def bind_session(self, *, owner_user_id: UUID, session_id: UUID) -> None:
        """Bind an already authorized P2A Session to this internal service."""

        with self._lock:
            existing = self._owners.get(session_id)
            if existing is not None and existing != owner_user_id:
                raise P2BConfirmationIntentApplicationConflict(
                    "P2B_SESSION_OWNER_MISMATCH", "Session owner mismatch"
                )
            self._owners[session_id] = owner_user_id

    def apply(self, request: P2BConfirmationRequest) -> P2BConfirmationResponse:
        self._ensure_enabled()
        _validate_idempotency_key(request.idempotency_key)
        timestamp = request.now or utc_now()
        if not isinstance(timestamp, datetime) or timestamp.tzinfo is None:
            raise P2BConfirmationIntentApplicationConflict(
                "P2B_INVALID_TIMESTAMP", "timezone-aware request timestamp required"
            )
        p2a = _validate_p2a_result(request.p2a_result)
        with self._lock:
            owner = self._owners.get(p2a.session.session_id)
            if owner != request.owner_user_id:
                raise P2BConfirmationIntentApplicationConflict(
                    "P2B_SESSION_OWNER_MISMATCH", "Session owner mismatch"
                )
            request = _revalidate_request_models(request)
            if timestamp >= p2a.session.expires_at:
                raise P2BConfirmationIntentApplicationConflict(
                    "P2B_SESSION_EXPIRED", "Session projection has expired"
                )
            source_key = (request.owner_user_id, p2a.session.session_id, p2a.turn.turn_id)
            request_digest = _request_digest(request=request, p2a=p2a)
            key = (request.owner_user_id, p2a.session.session_id, request.idempotency_key)
            existing = self._by_key.get(key)
            if existing is not None:
                if existing.request_digest != request_digest:
                    raise P2BConfirmationIntentApplicationConflict(
                        "P2B_IDEMPOTENCY_KEY_REUSED", "idempotency key was reused for another request"
                    )
                return P2BConfirmationResponse(existing.result, replayed=True)
            if source_key in self._by_source:
                raise P2BConfirmationIntentApplicationConflict(
                    "P2B_CONFIRMATION_ALREADY_CREATED", "confirmation intent already exists for this Turn"
                )

            candidate = _validate_confirmation_preconditions(request=request, p2a=p2a)
            try:
                intent = self.approval_store.create_intent(
                    owner_id=request.owner_user_id,
                    session_id=p2a.session.session_id,
                    current_revision=p2a.session.revision,
                    candidate=candidate,
                    source_turn_id=p2a.turn.turn_id,
                    confirmation=request.confirmation,
                    safety=request.safety,
                    raw_input=request.server_raw_input,
                    agent_versions=request.agent_versions,
                    now=timestamp,
                )
            except ConfirmationConflict as exc:
                raise P2BConfirmationIntentApplicationConflict(
                    _map_confirmation_code(exc.code), "confirmation intent validation failed"
                ) from exc
            except Exception as exc:  # noqa: BLE001 - do not leak persistence details
                raise P2BConfirmationIntentApplicationConflict(
                    "P2B_APPLICATION_FAILED", "confirmation intent application failed"
                ) from exc

            result = _build_result(
                intent=intent.approval,
                source_session_id=p2a.session.session_id,
                source_turn_id=p2a.turn.turn_id,
                source_sequence=p2a.turn.sequence,
                previous_session_revision=p2a.session.revision,
                now=timestamp,
            )
            record = _P2BRecord(request_digest=request_digest, result=result)
            self._by_key[key] = record
            self._by_source[source_key] = record
            return P2BConfirmationResponse(result)

    @property
    def pending_intent_count(self) -> int:
        with self._lock:
            return len(self._by_source)

    def clear(self) -> None:
        with self._lock:
            self._owners.clear()
            self._by_key.clear()
            self._by_source.clear()

    def _ensure_enabled(self) -> None:
        if not self.enabled:
            raise P2BConfirmationIntentApplicationConflict("P2B_DISABLED", "P2B confirmation application is disabled")


def _validate_idempotency_key(key: str) -> None:
    if not isinstance(key, str) or _IDEMPOTENCY_KEY.fullmatch(key) is None:
        raise P2BConfirmationIntentApplicationConflict(
            "P2B_INVALID_IDEMPOTENCY_KEY", "bounded idempotency key required"
        )


def _validate_p2a_result(value: SessionTurnProjectionResult) -> SessionTurnProjectionResult:
    try:
        result = SessionTurnProjectionResult.model_validate(
            value.model_dump(mode="python") if isinstance(value, SessionTurnProjectionResult) else value
        )
    except (ValidationError, TypeError, ValueError) as exc:
        raise P2BConfirmationIntentApplicationConflict(
            "P2B_P2A_RESULT_REJECTED", "P2A projection failed validation"
        ) from exc
    if result.session.state != "awaiting_confirmation" or result.turn.output_kind != "draft_ready":
        raise P2BConfirmationIntentApplicationConflict(
            "P2B_CONFIRMATION_NOT_ALLOWED", "the current Turn is not a confirmable draft"
        )
    return result


def _validate_confirmation_preconditions(
    *, request: P2BConfirmationRequest, p2a: SessionTurnProjectionResult
) -> DraftCandidate:
    if request.confirmation.turn_id != p2a.turn.turn_id:
        raise P2BConfirmationIntentApplicationConflict("P2B_TURN_MISMATCH", "confirmation targets another Turn")
    if request.confirmation.expected_revision != p2a.session.revision:
        raise P2BConfirmationIntentApplicationConflict(
            "P2B_REVISION_MISMATCH", "confirmation Session revision is stale"
        )
    if not isinstance(p2a.turn.candidate, DraftCandidate):
        raise P2BConfirmationIntentApplicationConflict(
            "P2B_CONFIRMATION_NOT_ALLOWED", "confirmable Turn has no draft candidate"
        )
    candidate = p2a.turn.candidate
    if request.confirmation.draft_digest != candidate.draft_digest:
        raise P2BConfirmationIntentApplicationConflict(
            "P2B_DRAFT_DIGEST_MISMATCH", "confirmation draft digest is stale"
        )
    typed_safety = request.safety
    if not (
        typed_safety.status == "complete"
        and typed_safety.tier in {"R2", "R3"}
        and typed_safety.scenario_support == "supported"
        and not typed_safety.unresolved_safety
    ):
        raise P2BConfirmationIntentApplicationConflict(
            "P2B_SAFETY_GATE_BLOCKED", "complete supported R2/R3 safety is required"
        )
    if digest_for(candidate.event_draft) != candidate.draft_digest:
        raise P2BConfirmationIntentApplicationConflict(
            "P2B_DRAFT_DIGEST_MISMATCH", "typed draft digest is stale"
        )
    return candidate


def _revalidate_request_models(request: P2BConfirmationRequest) -> P2BConfirmationRequest:
    """Rebuild all caller-provided Pydantic objects before hashing or storing.

    The dataclass is an application transport, not a trust boundary: callers
    can pass ``model_construct`` instances or dictionaries in tests and future
    adapters.  Revalidation makes the eight reviewed fields, EpisodeSelection,
    safety invariants and server-input shape effective at this boundary.
    """

    try:
        confirmation = ConfirmationRequest.model_validate(
            request.confirmation.model_dump(mode="python")
            if isinstance(request.confirmation, ConfirmationRequest)
            else request.confirmation
        )
        safety = SafetyEvaluation.model_validate(
            request.safety.model_dump(mode="python") if isinstance(request.safety, SafetyEvaluation) else request.safety
        )
        server_raw_input = UserTurnInput.model_validate(
            request.server_raw_input.model_dump(mode="python")
            if isinstance(request.server_raw_input, UserTurnInput)
            else request.server_raw_input
        )
    except (ValidationError, TypeError, ValueError) as exc:
        raise P2BConfirmationIntentApplicationConflict(
            "P2B_CONFIRMATION_REQUEST_REJECTED", "confirmation or server safety input failed validation"
        ) from exc
    return replace(request, confirmation=confirmation, safety=safety, server_raw_input=server_raw_input)


def _build_result(
    *,
    intent: ApprovalIntent,
    source_session_id: UUID,
    source_turn_id: UUID,
    source_sequence: int,
    previous_session_revision: int,
    now: datetime,
) -> ConfirmationIntentApplicationResult:
    projection = ApprovalRequiredProjection(
        turn_id=uuid4(),
        session_id=source_session_id,
        source_turn_id=source_turn_id,
        sequence=source_sequence + 1,
        revision=previous_session_revision + 1,
        status="approval_required",
        state="awaiting_approval",
        output_origin="application",
        approval_id=intent.approval_id,
        approval_revision=intent.revision,
        resource_revision=intent.resource_revision,
        action_type=intent.action_type,
        target_ref=intent.target_ref,
        intent_digest=intent.intent_digest,
        display_summary=intent.display_summary or "已复核身体事实，等待第二次确认。",
        expires_at=intent.expires_at,
    )
    return ConfirmationIntentApplicationResult(
        schema_version="1.0",
        approval=intent,
        source_session_id=source_session_id,
        source_turn_id=source_turn_id,
        previous_session_revision=previous_session_revision,
        proposed_session_revision=previous_session_revision + 1,
        approval_projection=projection,
        created_at=now,
    )


def _request_digest(*, request: P2BConfirmationRequest, p2a: SessionTurnProjectionResult) -> str:
    payload = {
        "operation": "request_confirmation",
        "owner_user_id": str(request.owner_user_id),
        "p2a": p2a.model_dump(mode="json", exclude_none=True),
        "confirmation": request.confirmation.model_dump(mode="json", exclude_none=True),
        "safety": request.safety.model_dump(mode="json", exclude_none=True),
        "agent_versions": dict(request.agent_versions),
    }
    canonical = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return "sha256:" + hashlib.sha256(canonical).hexdigest()


def _map_confirmation_code(code: str) -> str:
    return {
        "REVISION_MISMATCH": "P2B_REVISION_MISMATCH",
        "TURN_MISMATCH": "P2B_TURN_MISMATCH",
        "DRAFT_DIGEST_MISMATCH": "P2B_DRAFT_DIGEST_MISMATCH",
        "SAFETY_GATE_BLOCKED": "P2B_SAFETY_GATE_BLOCKED",
    }.get(code, "P2B_APPLICATION_FAILED")
