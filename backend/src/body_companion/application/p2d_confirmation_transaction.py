"""P2D metadata-only confirmation transaction contract prototype."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
import hashlib
import json
import re
from threading import RLock
from typing import Protocol
from uuid import UUID, uuid4

from pydantic import ValidationError

from ..domain.approval_decision_application import ApprovalDecisionApplicationResult
from ..domain.confirmation_application import ConfirmationIntentApplicationResult
from ..domain.confirmation_transaction import (
    ConfirmationTransactionApprovalSnapshot,
    ConfirmationTransactionPlan,
    ConfirmationTransactionReceipt,
    ConfirmationTransactionSessionSnapshot,
    validate_p2d_replay_identity,
    validate_p2d_relations,
    write_set_for_status,
)
from ..domain.types import utc_now


P2D_FEATURE_FLAG = "P2D_CONFIRMATION_TRANSACTION_CONTRACT_PROTOTYPE"
_IDEMPOTENCY_KEY = re.compile(r"^[\x21-\x7e]{8,128}$")


class P2DConfirmationTransactionConflict(ValueError):
    """Stable P2D error without health-data content."""

    def __init__(self, code: str, message: str):
        self.code = code
        super().__init__(message)


@dataclass(frozen=True)
class P2DConfirmationTransactionRequest:
    owner_user_id: UUID
    p2b_result: ConfirmationIntentApplicationResult
    p2c_result: ApprovalDecisionApplicationResult
    session: ConfirmationTransactionSessionSnapshot
    approval: ConfirmationTransactionApprovalSnapshot
    idempotency_key: str
    now: datetime | None = None


@dataclass(frozen=True)
class P2DConfirmationTransactionResponse:
    receipt: ConfirmationTransactionReceipt
    replayed: bool = False


class ConfirmationTransactionRepository(Protocol):
    """Internal port; a future durable repository must preserve these phases."""

    def prepare(self, plan: ConfirmationTransactionPlan) -> None: ...

    def commit(self, plan: ConfirmationTransactionPlan) -> None: ...

    def read_back(self, plan: ConfirmationTransactionPlan) -> ConfirmationTransactionPlan: ...

    def rollback(self, plan: ConfirmationTransactionPlan) -> None: ...


class PrototypeConfirmationTransactionRepository:
    """Fault-injectable metadata-only fake; it stores no health data."""

    def __init__(self) -> None:
        self.fail_prepare = False
        self.fail_commit = False
        self.fail_read_back = False
        self.mutate_read_back = False
        self._committed: dict[UUID, ConfirmationTransactionPlan] = {}
        self.prepare_calls = 0
        self.commit_calls = 0
        self.read_back_calls = 0
        self.rollback_calls = 0

    @property
    def committed_count(self) -> int:
        return len(self._committed)

    def prepare(self, plan: ConfirmationTransactionPlan) -> None:
        self.prepare_calls += 1
        if self.fail_prepare:
            raise RuntimeError("prototype prepare failure")

    def commit(self, plan: ConfirmationTransactionPlan) -> None:
        self.commit_calls += 1
        if self.fail_commit:
            raise RuntimeError("prototype commit failure")
        self._committed[plan.transaction_id] = plan.model_copy(deep=True)

    def read_back(self, plan: ConfirmationTransactionPlan) -> ConfirmationTransactionPlan:
        self.read_back_calls += 1
        if self.fail_read_back:
            raise RuntimeError("prototype read-back failure")
        committed = self._committed.get(plan.transaction_id)
        if committed is None:
            raise RuntimeError("prototype transaction not found")
        if self.mutate_read_back:
            return committed.model_copy(update={"committed_session_revision": committed.committed_session_revision + 1})
        return committed.model_copy(deep=True)

    def rollback(self, plan: ConfirmationTransactionPlan) -> None:
        self.rollback_calls += 1
        self._committed.pop(plan.transaction_id, None)


@dataclass(frozen=True)
class _P2DRecord:
    request_digest: str
    receipt: ConfirmationTransactionReceipt


class P2DConfirmationTransactionApplicationService:
    """Validate and execute only the metadata transaction contract."""

    def __init__(
        self,
        *,
        enabled: bool = False,
        repository: ConfirmationTransactionRepository | None = None,
    ) -> None:
        self.enabled = enabled
        self.repository = repository or PrototypeConfirmationTransactionRepository()
        self._lock = RLock()
        self._owners: dict[UUID, UUID] = {}
        self._by_key: dict[tuple[UUID, UUID, str], _P2DRecord] = {}
        self._by_approval: dict[tuple[UUID, UUID], _P2DRecord] = {}

    def bind_session(self, *, owner_user_id: UUID, session_id: UUID) -> None:
        with self._lock:
            existing = self._owners.get(session_id)
            if existing is not None and existing != owner_user_id:
                raise P2DConfirmationTransactionConflict("P2D_SESSION_OWNER_MISMATCH", "Session owner mismatch")
            self._owners[session_id] = owner_user_id

    def apply(self, request: P2DConfirmationTransactionRequest) -> P2DConfirmationTransactionResponse:
        self._ensure_enabled()
        _validate_key(request.idempotency_key)
        timestamp = request.now or utc_now()
        if not isinstance(timestamp, datetime) or timestamp.tzinfo is None:
            raise P2DConfirmationTransactionConflict("P2D_INVALID_TIMESTAMP", "timezone-aware timestamp required")
        p2b = _revalidate_p2b(request.p2b_result)
        p2c = _revalidate_p2c(request.p2c_result)
        session = _revalidate_session(request.session)
        approval = _revalidate_approval(request.approval)
        session_id = p2b.source_session_id
        approval_id = p2b.approval.approval_id
        with self._lock:
            if self._owners.get(session_id) != request.owner_user_id:
                raise P2DConfirmationTransactionConflict("P2D_RESOURCE_NOT_FOUND", "transaction resource not found")
            _validate_replay_identity_or_raise(p2b=p2b, p2c=p2c, session=session, approval=approval)
            request_digest = _request_digest(p2b=p2b, p2c=p2c)
            key = (request.owner_user_id, approval_id, request.idempotency_key)
            existing = self._by_key.get(key)
            if existing is not None:
                if existing.request_digest != request_digest:
                    raise P2DConfirmationTransactionConflict(
                        "P2D_IDEMPOTENCY_KEY_REUSED", "idempotency key was reused for another transaction"
                    )
                return P2DConfirmationTransactionResponse(existing.receipt, replayed=True)
            terminal_key = (request.owner_user_id, approval_id)
            terminal = self._by_approval.get(terminal_key)
            if terminal is not None:
                self._by_key[key] = _P2DRecord(request_digest=request_digest, receipt=terminal.receipt)
                return P2DConfirmationTransactionResponse(terminal.receipt, replayed=True)

            _validate_relations_or_raise(p2b=p2b, p2c=p2c, session=session, approval=approval)
            plan = _build_plan(p2b=p2b, p2c=p2c, request_digest=request_digest)
            try:
                self.repository.prepare(plan)
                self.repository.commit(plan)
                read_back = self.repository.read_back(plan)
                _validate_read_back(plan, read_back)
            except P2DConfirmationTransactionConflict:
                self.repository.rollback(plan)
                raise
            except Exception as exc:  # noqa: BLE001 - hide repository details
                self.repository.rollback(plan)
                raise P2DConfirmationTransactionConflict(
                    "P2D_TRANSACTION_FAILED", "confirmation transaction failed"
                ) from exc

            receipt = _receipt_from_plan(plan, now=timestamp)
            record = _P2DRecord(request_digest=request_digest, receipt=receipt)
            self._by_key[key] = record
            self._by_approval[terminal_key] = record
            return P2DConfirmationTransactionResponse(receipt)

    @property
    def committed_transaction_count(self) -> int:
        with self._lock:
            return len(self._by_approval)

    def clear(self) -> None:
        with self._lock:
            self._owners.clear()
            self._by_key.clear()
            self._by_approval.clear()

    def _ensure_enabled(self) -> None:
        if not self.enabled:
            raise P2DConfirmationTransactionConflict(
                "P2D_DISABLED", "confirmation transaction contract is disabled"
            )


def _validate_key(key: str) -> None:
    if not isinstance(key, str) or _IDEMPOTENCY_KEY.fullmatch(key) is None:
        raise P2DConfirmationTransactionConflict("P2D_INVALID_IDEMPOTENCY_KEY", "bounded idempotency key required")


def _revalidate_p2b(value: ConfirmationIntentApplicationResult) -> ConfirmationIntentApplicationResult:
    try:
        return ConfirmationIntentApplicationResult.model_validate(
            value.model_dump(mode="python") if isinstance(value, ConfirmationIntentApplicationResult) else value
        )
    except (ValidationError, TypeError, ValueError) as exc:
        raise P2DConfirmationTransactionConflict("P2D_P2B_RESULT_REJECTED", "P2B result failed validation") from exc


def _revalidate_p2c(value: ApprovalDecisionApplicationResult) -> ApprovalDecisionApplicationResult:
    try:
        return ApprovalDecisionApplicationResult.model_validate(
            value.model_dump(mode="python") if isinstance(value, ApprovalDecisionApplicationResult) else value
        )
    except (ValidationError, TypeError, ValueError) as exc:
        raise P2DConfirmationTransactionConflict("P2D_P2C_RESULT_REJECTED", "P2C result failed validation") from exc


def _revalidate_session(value: ConfirmationTransactionSessionSnapshot) -> ConfirmationTransactionSessionSnapshot:
    try:
        return ConfirmationTransactionSessionSnapshot.model_validate(
            value.model_dump(mode="python") if isinstance(value, ConfirmationTransactionSessionSnapshot) else value
        )
    except (ValidationError, TypeError, ValueError) as exc:
        raise P2DConfirmationTransactionConflict("P2D_SESSION_SNAPSHOT_REJECTED", "Session snapshot failed validation") from exc


def _revalidate_approval(value: ConfirmationTransactionApprovalSnapshot) -> ConfirmationTransactionApprovalSnapshot:
    try:
        return ConfirmationTransactionApprovalSnapshot.model_validate(
            value.model_dump(mode="python") if isinstance(value, ConfirmationTransactionApprovalSnapshot) else value
        )
    except (ValidationError, TypeError, ValueError) as exc:
        raise P2DConfirmationTransactionConflict("P2D_APPROVAL_SNAPSHOT_REJECTED", "Approval snapshot failed validation") from exc


def _validate_relations_or_raise(**kwargs: object) -> None:
    try:
        validate_p2d_relations(**kwargs)  # type: ignore[arg-type]
    except (ValidationError, TypeError, ValueError) as exc:
        message = str(exc)
        if "Session revision" in message or "awaiting approval" in message or "P2C committed" in message:
            code = "P2D_REVISION_MISMATCH"
        elif "Approval" in message or "digest" in message or "source" in message:
            code = "P2D_SOURCE_BINDING_MISMATCH"
        else:
            code = "P2D_RELATION_REJECTED"
        raise P2DConfirmationTransactionConflict(code, "transaction source or revision relation failed") from exc


def _validate_replay_identity_or_raise(**kwargs: object) -> None:
    try:
        validate_p2d_replay_identity(**kwargs)  # type: ignore[arg-type]
    except (ValidationError, TypeError, ValueError) as exc:
        message = str(exc)
        if "Approval" in message or "digest" in message or "source" in message or "lifecycle" in message:
            code = "P2D_SOURCE_BINDING_MISMATCH"
        else:
            code = "P2D_RELATION_REJECTED"
        raise P2DConfirmationTransactionConflict(code, "transaction replay source relation failed") from exc


def _request_digest(
    *,
    p2b: ConfirmationIntentApplicationResult,
    p2c: ApprovalDecisionApplicationResult,
) -> str:
    payload = {
        "operation": "p2d_confirmation_transaction",
        "write_set_version": "p2d-1.0",
        "p2b": p2b.model_dump(mode="json", exclude_none=True),
        "p2c": p2c.model_dump(mode="json", exclude_none=True),
        "expected_session_revision": p2b.proposed_session_revision,
        "expected_approval_revision": p2b.approval.revision,
    }
    canonical = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return "sha256:" + hashlib.sha256(canonical).hexdigest()


def _build_plan(
    *, p2b: ConfirmationIntentApplicationResult, p2c: ApprovalDecisionApplicationResult, request_digest: str
) -> ConfirmationTransactionPlan:
    status = p2c.decision.status
    lifecycle = p2c.lifecycle
    return ConfirmationTransactionPlan(
        transaction_id=uuid4(),
        session_id=p2b.source_session_id,
        approval_id=p2b.approval.approval_id,
        source_turn_id=p2b.source_turn_id,
        request_digest=request_digest,
        expected_session_revision=p2b.proposed_session_revision,
        committed_session_revision=p2c.proposed_session_revision,
        approval_revision=p2c.approval.revision,
        terminal_status=status,
        lifecycle_status=lifecycle.status,
        lifecycle_state=lifecycle.state,
        lifecycle_turn_id=lifecycle.turn_id,
        write_set=write_set_for_status(status),
        result_refs=list(p2c.decision.result_refs),
    )


def _validate_read_back(plan: ConfirmationTransactionPlan, read_back: ConfirmationTransactionPlan) -> None:
    if read_back != plan:
        raise P2DConfirmationTransactionConflict("P2D_READ_BACK_MISMATCH", "authoritative read-back did not match plan")


def _receipt_from_plan(plan: ConfirmationTransactionPlan, *, now: datetime) -> ConfirmationTransactionReceipt:
    return ConfirmationTransactionReceipt(
        outcome="committed",
        transaction_id=plan.transaction_id,
        session_id=plan.session_id,
        approval_id=plan.approval_id,
        request_digest=plan.request_digest,
        expected_session_revision=plan.expected_session_revision,
        committed_session_revision=plan.committed_session_revision,
        approval_revision=plan.approval_revision,
        lifecycle_status=plan.lifecycle_status,
        lifecycle_state=plan.lifecycle_state,
        write_set=list(plan.write_set),
        result_refs=list(plan.result_refs),
        replayed=False,
        created_at=now,
    )
