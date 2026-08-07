"""P2C typed second-approval application boundary.

This is an internal, feature-flagged prototype.  It consumes a P2B pending
result, revalidates server-owned bindings, and delegates the actual prototype
side effect to ``PrototypeApprovalStore``.  It does not mutate P2A and does not
expose a public API or durable repository.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
import hashlib
import json
import re
from threading import RLock
from typing import Any
from uuid import UUID, uuid4

from pydantic import ValidationError

from ..domain.approval_decision_application import (
    ApprovalDecisionApplicationResult,
    ApprovalDecisionLifecycleProjection,
    ApprovalDecisionMetadata,
)
from ..domain.confirmation import (
    ApprovalDecisionRequest,
    ConfirmationConflict,
    PrototypeApprovalStore,
)
from ..domain.confirmation_application import ConfirmationIntentApplicationResult
from ..domain.types import utc_now


P2C_FEATURE_FLAG = "P2C_APPROVAL_DECISION_APPLICATION_PROTOTYPE"
_IDEMPOTENCY_KEY = re.compile(r"^[\x21-\x7e]{8,128}$")


class P2CApprovalDecisionApplicationConflict(ValueError):
    """Stable P2C error with no health-data content in its message."""

    def __init__(self, code: str, message: str):
        self.code = code
        super().__init__(message)


@dataclass(frozen=True)
class P2CApprovalDecisionRequest:
    owner_user_id: UUID
    p2b_result: ConfirmationIntentApplicationResult
    decision: ApprovalDecisionRequest
    current_session_revision: int
    idempotency_key: str
    now: datetime | None = None


@dataclass(frozen=True)
class P2CApprovalDecisionResponse:
    result: ApprovalDecisionApplicationResult
    replayed: bool = False


@dataclass(frozen=True)
class _P2CRecord:
    request_digest: str
    result: ApprovalDecisionApplicationResult


class P2CApprovalDecisionApplicationService:
    """Apply one typed approve/deny decision to one P2B pending intent."""

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
        self._by_key: dict[tuple[UUID, UUID, str], _P2CRecord] = {}
        self._by_approval: dict[tuple[UUID, UUID], _P2CRecord] = {}

    def bind_session(self, *, owner_user_id: UUID, session_id: UUID) -> None:
        with self._lock:
            existing = self._owners.get(session_id)
            if existing is not None and existing != owner_user_id:
                raise P2CApprovalDecisionApplicationConflict(
                    "P2C_SESSION_OWNER_MISMATCH", "Session owner mismatch"
                )
            self._owners[session_id] = owner_user_id

    def apply(self, request: P2CApprovalDecisionRequest) -> P2CApprovalDecisionResponse:
        self._ensure_enabled()
        _validate_idempotency_key(request.idempotency_key)
        timestamp = request.now or utc_now()
        if not isinstance(timestamp, datetime) or timestamp.tzinfo is None:
            raise P2CApprovalDecisionApplicationConflict(
                "P2C_INVALID_TIMESTAMP", "timezone-aware request timestamp required"
            )
        p2b = _validate_p2b_result(request.p2b_result)
        decision = _validate_decision(request.decision)
        if not isinstance(request.current_session_revision, int) or request.current_session_revision < 1:
            raise P2CApprovalDecisionApplicationConflict(
                "P2C_INVALID_SESSION_REVISION", "current Session revision must be positive"
            )

        session_id = p2b.source_session_id
        approval_id = p2b.approval.approval_id
        request_digest = _request_digest(
            owner_user_id=request.owner_user_id,
            p2b=p2b,
            decision=decision,
            current_session_revision=request.current_session_revision,
        )
        key = (request.owner_user_id, approval_id, request.idempotency_key)
        approval_key = (request.owner_user_id, approval_id)

        with self._lock:
            owner = self._owners.get(session_id)
            if owner != request.owner_user_id:
                raise P2CApprovalDecisionApplicationConflict(
                    "P2C_RESOURCE_NOT_FOUND", "approval not found"
                )
            try:
                stored_intent = self.approval_store.get(owner_id=request.owner_user_id, approval_id=approval_id)
            except ConfirmationConflict as exc:
                raise P2CApprovalDecisionApplicationConflict(
                    "P2C_RESOURCE_NOT_FOUND", "approval not found"
                ) from exc
            _validate_source_binding(stored_intent, p2b)

            existing = self._by_key.get(key)
            if existing is not None:
                if existing.request_digest != request_digest:
                    raise P2CApprovalDecisionApplicationConflict(
                        "P2C_IDEMPOTENCY_KEY_REUSED", "idempotency key was reused for another decision"
                    )
                return P2CApprovalDecisionResponse(existing.result, replayed=True)

            terminal = self.approval_store.get_result(owner_id=request.owner_user_id, approval_id=approval_id)
            terminal_record = self._by_approval.get(approval_key)
            if terminal is not None:
                if terminal_record is None:
                    result = _build_result(p2b=p2b, terminal=terminal, intent=stored_intent.approval)
                    terminal_record = _P2CRecord(request_digest=request_digest, result=result)
                    self._by_approval[approval_key] = terminal_record
                self._by_key[key] = _P2CRecord(request_digest=request_digest, result=terminal_record.result)
                return P2CApprovalDecisionResponse(terminal_record.result, replayed=True)

            if decision.expected_revision != p2b.approval.revision:
                raise P2CApprovalDecisionApplicationConflict(
                    "P2C_APPROVAL_REVISION_MISMATCH", "approval revision changed"
                )
            if timestamp >= stored_intent.approval.expires_at:
                raise P2CApprovalDecisionApplicationConflict(
                    "P2C_APPROVAL_EXPIRED", "approval has expired"
                )
            if request.current_session_revision != p2b.previous_session_revision:
                raise P2CApprovalDecisionApplicationConflict(
                    "P2C_SESSION_REVISION_MISMATCH", "Session revision changed"
                )

            try:
                terminal = self.approval_store.decide(
                    owner_id=request.owner_user_id,
                    approval_id=approval_id,
                    request=decision,
                    idempotency_key=request.idempotency_key,
                    current_session_revision=request.current_session_revision,
                    session_snapshot=_safe_session_snapshot(p2b),
                    latest_turn=_safe_latest_turn_snapshot(p2b),
                    now=timestamp,
                )
                updated_intent = self.approval_store.get(owner_id=request.owner_user_id, approval_id=approval_id)
            except ConfirmationConflict as exc:
                raise P2CApprovalDecisionApplicationConflict(
                    _map_confirmation_code(exc.code), "approval decision failed"
                ) from exc
            except Exception as exc:  # noqa: BLE001 - hide storage details
                raise P2CApprovalDecisionApplicationConflict(
                    "P2C_APPLICATION_FAILED", "approval decision application failed"
                ) from exc

            result = _build_result(p2b=p2b, terminal=terminal, intent=updated_intent.approval)
            record = _P2CRecord(request_digest=request_digest, result=result)
            self._by_key[key] = record
            self._by_approval[approval_key] = record
            return P2CApprovalDecisionResponse(result)

    def clear(self) -> None:
        with self._lock:
            self._owners.clear()
            self._by_key.clear()
            self._by_approval.clear()

    @property
    def decision_count(self) -> int:
        with self._lock:
            return len(self._by_approval)

    def _ensure_enabled(self) -> None:
        if not self.enabled:
            raise P2CApprovalDecisionApplicationConflict(
                "P2C_DISABLED", "P2C approval decision application is disabled"
            )


def _validate_idempotency_key(key: str) -> None:
    if not isinstance(key, str) or _IDEMPOTENCY_KEY.fullmatch(key) is None:
        raise P2CApprovalDecisionApplicationConflict(
            "P2C_INVALID_IDEMPOTENCY_KEY", "bounded idempotency key required"
        )


def _validate_p2b_result(value: ConfirmationIntentApplicationResult) -> ConfirmationIntentApplicationResult:
    try:
        return ConfirmationIntentApplicationResult.model_validate(
            value.model_dump(mode="python") if isinstance(value, ConfirmationIntentApplicationResult) else value
        )
    except (ValidationError, TypeError, ValueError) as exc:
        raise P2CApprovalDecisionApplicationConflict(
            "P2C_P2B_RESULT_REJECTED", "P2B result failed validation"
        ) from exc


def _validate_decision(value: ApprovalDecisionRequest) -> ApprovalDecisionRequest:
    try:
        return ApprovalDecisionRequest.model_validate(
            value.model_dump(mode="python") if isinstance(value, ApprovalDecisionRequest) else value
        )
    except (ValidationError, TypeError, ValueError) as exc:
        raise P2CApprovalDecisionApplicationConflict(
            "P2C_DECISION_REJECTED", "approval decision failed validation"
        ) from exc


def _validate_source_binding(stored: Any, p2b: ConfirmationIntentApplicationResult) -> None:
    approval = stored.approval
    expected = p2b.approval
    immutable_pairs = (
        (approval.approval_id, expected.approval_id),
        (approval.source_session_id, expected.source_session_id),
        (approval.target_ref, expected.target_ref),
        (approval.action_type, expected.action_type),
        (approval.intent_digest, expected.intent_digest),
        (approval.resource_revision, expected.resource_revision),
        (approval.created_at, expected.created_at),
        (approval.expires_at, expected.expires_at),
        (stored.source_turn_id, p2b.source_turn_id),
    )
    if any(left != right for left, right in immutable_pairs):
        raise P2CApprovalDecisionApplicationConflict(
            "P2C_SOURCE_BINDING_MISMATCH", "approval source binding changed"
        )
    if expected.resource_revision != p2b.previous_session_revision:
        raise P2CApprovalDecisionApplicationConflict(
            "P2C_SOURCE_BINDING_MISMATCH", "approval resource binding is invalid"
        )


def _safe_session_snapshot(p2b: ConfirmationIntentApplicationResult) -> dict[str, Any]:
    return {
        "session_id": str(p2b.source_session_id),
        "revision": p2b.proposed_session_revision,
        "state": "awaiting_approval",
    }


def _safe_latest_turn_snapshot(p2b: ConfirmationIntentApplicationResult) -> dict[str, Any]:
    projection = p2b.approval_projection
    return {
        "turn_id": str(projection.turn_id),
        "session_id": str(projection.session_id),
        "source_turn_id": str(projection.source_turn_id),
        "sequence": projection.sequence,
        "revision": projection.revision,
        "status": projection.status,
        "state": projection.state,
        "output_origin": projection.output_origin,
    }


def _build_result(*, p2b: ConfirmationIntentApplicationResult, terminal: Any, intent: Any) -> ApprovalDecisionApplicationResult:
    decision = ApprovalDecisionMetadata(
        approval_id=terminal.approval_id,
        action_type=terminal.action_type,
        target_ref=terminal.target_ref,
        source_session_id=terminal.source_session_id,
        status=terminal.status,
        resolution_reason=terminal.resolution_reason,
        revision=terminal.revision,
        result_refs=list(terminal.result_refs),
        decided_at=terminal.decided_at,
    )
    proposed_revision = p2b.proposed_session_revision + 1
    lifecycle = ApprovalDecisionLifecycleProjection(
        turn_id=uuid4(),
        session_id=p2b.source_session_id,
        source_turn_id=p2b.source_turn_id,
        sequence=p2b.approval_projection.sequence + 1,
        revision=proposed_revision,
        status=("completed" if terminal.status == "executed" else "failed" if terminal.status == "failed" else "approval_decided"),
        state=("completed" if terminal.status == "executed" else "failed" if terminal.status == "failed" else "awaiting_confirmation"),
        approval_id=terminal.approval_id,
        approval_revision=intent.revision,
        resource_revision=p2b.proposed_session_revision,
        action_type=terminal.action_type,
        target_ref=terminal.target_ref,
        intent_digest=intent.intent_digest,
        approval_status=terminal.status,
        result_refs=list(terminal.result_refs),
    )
    return ApprovalDecisionApplicationResult(
        approval=intent,
        decision=decision,
        source_session_id=p2b.source_session_id,
        source_turn_id=p2b.source_turn_id,
        previous_session_revision=p2b.previous_session_revision,
        proposed_session_revision=proposed_revision,
        lifecycle=lifecycle,
        created_at=terminal.decided_at,
    )


def _request_digest(
    *,
    owner_user_id: UUID,
    p2b: ConfirmationIntentApplicationResult,
    decision: ApprovalDecisionRequest,
    current_session_revision: int,
) -> str:
    payload = {
        "operation": "p2c_approval_decision",
        "owner_user_id": str(owner_user_id),
        "p2b": p2b.model_dump(mode="json", exclude_none=True),
        "decision": decision.model_dump(mode="json", exclude_none=True),
        "current_session_revision": current_session_revision,
    }
    canonical = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return "sha256:" + hashlib.sha256(canonical).hexdigest()


def _map_confirmation_code(code: str) -> str:
    return {
        "IDEMPOTENCY_KEY_REQUIRED": "P2C_INVALID_IDEMPOTENCY_KEY",
        "IDEMPOTENCY_CONFLICT": "P2C_IDEMPOTENCY_KEY_REUSED",
        "RESOURCE_NOT_FOUND": "P2C_RESOURCE_NOT_FOUND",
        "INTENT_DIGEST_MISMATCH": "P2C_INTENT_DIGEST_MISMATCH",
        "APPROVAL_REVISION_MISMATCH": "P2C_APPROVAL_REVISION_MISMATCH",
        "APPROVAL_NOT_PENDING": "P2C_APPROVAL_NOT_PENDING",
        "EVENT_WRITE_FAILED": "P2C_EVENT_WRITE_FAILED",
        "EVENT_VALIDATION_FAILED": "P2C_EVENT_WRITE_FAILED",
        "DRAFT_DIGEST_MISMATCH": "P2C_SOURCE_BINDING_MISMATCH",
    }.get(code, "P2C_APPLICATION_FAILED")
