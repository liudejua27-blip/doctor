from __future__ import annotations

from dataclasses import replace
from datetime import timedelta
import json
from pathlib import Path
from uuid import uuid4

import pytest
from jsonschema import Draft202012Validator, FormatChecker

from body_companion.application.p2d_confirmation_transaction import (
    P2DConfirmationTransactionConflict,
    P2DConfirmationTransactionApplicationService,
    P2DConfirmationTransactionRequest,
    PrototypeConfirmationTransactionRepository,
)
from body_companion.domain.confirmation_transaction import (
    ConfirmationTransactionApprovalSnapshot,
    ConfirmationTransactionPlan,
    ConfirmationTransactionSessionSnapshot,
)

from test_p2c_approval_decision_application import _apply_for_owner, _pending


ROOT = Path(__file__).resolve().parents[2]


def _snapshots(p2b):
    session = ConfirmationTransactionSessionSnapshot(
        session_id=p2b.source_session_id,
        state="awaiting_approval",
        revision=p2b.proposed_session_revision,
        latest_turn_id=p2b.approval_projection.turn_id,
        latest_sequence=p2b.approval_projection.sequence,
    )
    approval = ConfirmationTransactionApprovalSnapshot(
        approval_id=p2b.approval.approval_id,
        source_session_id=p2b.source_session_id,
        source_turn_id=p2b.source_turn_id,
        status="pending",
        revision=p2b.approval.revision,
        resource_revision=p2b.approval.resource_revision,
        intent_digest=p2b.approval.intent_digest,
    )
    return session, approval


def _terminal_snapshots(p2b, p2c_result):
    session, approval = _snapshots(p2b)
    return (
        session.model_copy(
            update={
                "state": p2c_result.lifecycle.state,
                "revision": p2c_result.proposed_session_revision,
                "latest_turn_id": p2c_result.lifecycle.turn_id,
                "latest_sequence": p2c_result.lifecycle.sequence,
            }
        ),
        approval.model_copy(
            update={
                "status": p2c_result.decision.status,
                "revision": p2c_result.approval.revision,
            }
        ),
    )


def _apply(p2b, p2c_result, owner, *, repository=None, key="p2d-transaction-001", session=None, approval=None):
    default_session, default_approval = _snapshots(p2b)
    service = P2DConfirmationTransactionApplicationService(
        enabled=True,
        repository=repository or PrototypeConfirmationTransactionRepository(),
    )
    service.bind_session(owner_user_id=owner, session_id=p2b.source_session_id)
    return service, service.apply(
        P2DConfirmationTransactionRequest(
            owner_user_id=owner,
            p2b_result=p2b,
            p2c_result=p2c_result,
            session=session if session is not None else default_session,
            approval=approval if approval is not None else default_approval,
            idempotency_key=key,
        ),
    )


def _service_for(p2b, owner, repository):
    service = P2DConfirmationTransactionApplicationService(enabled=True, repository=repository)
    service.bind_session(owner_user_id=owner, session_id=p2b.source_session_id)
    return service


def test_executed_plan_commits_one_event_ref_and_bumps_session_once():
    _p2a, owner, p2b, p2c, _approvals = _pending()
    p2c_result = _apply_for_owner(p2b, p2c, owner).result
    repository = PrototypeConfirmationTransactionRepository()

    service, response = _apply(p2b, p2c_result, owner, repository=repository)

    assert service.committed_transaction_count == 1
    assert response.replayed is False
    receipt = response.receipt
    assert receipt.outcome == "committed"
    assert receipt.lifecycle_status == "completed"
    assert receipt.lifecycle_state == "completed"
    assert receipt.committed_session_revision == receipt.expected_session_revision + 1
    assert receipt.result_refs[0].type == "event"
    assert set(("session", "approval", "lifecycle_turn", "event", "episode", "audit_metadata")) == set(
        receipt.write_set
    )
    assert repository.prepare_calls == repository.commit_calls == repository.read_back_calls == 1


def test_denied_plan_has_no_event_or_episode_write_intent():
    _p2a, owner, p2b, p2c, _approvals = _pending()
    p2c_result = _apply_for_owner(p2b, p2c, owner, choice="deny").result

    _service, response = _apply(p2b, p2c_result, owner)

    assert response.receipt.lifecycle_status == "approval_decided"
    assert response.receipt.lifecycle_state == "awaiting_confirmation"
    assert response.receipt.result_refs == []
    assert "event" not in response.receipt.write_set
    assert "episode" not in response.receipt.write_set


def test_invalidated_and_failed_plans_are_non_event_terminal_shapes():
    _p2a, owner, p2b, p2c, _approvals = _pending()
    executed = _apply_for_owner(p2b, p2c, owner).result
    invalidated = executed.model_copy(
        update={
            "approval": executed.approval.model_copy(update={"status": "invalidated", "revision": 2}),
            "decision": executed.decision.model_copy(
                update={"status": "invalidated", "resolution_reason": "context_changed", "revision": 2, "result_refs": []}
            ),
            "lifecycle": executed.lifecycle.model_copy(
                update={
                    "status": "approval_decided",
                    "state": "awaiting_confirmation",
                    "approval_status": "invalidated",
                    "approval_revision": 2,
                    "result_refs": [],
                }
            ),
        }
    )
    failed = executed.model_copy(
        update={
            "approval": executed.approval.model_copy(update={"status": "failed", "revision": 3}),
            "decision": executed.decision.model_copy(
                update={"status": "failed", "resolution_reason": "execution_failed", "revision": 3, "result_refs": []}
            ),
            "lifecycle": executed.lifecycle.model_copy(
                update={
                    "status": "failed",
                    "state": "failed",
                    "approval_status": "failed",
                    "approval_revision": 3,
                    "result_refs": [],
                }
            ),
        }
    )

    _service, invalidated_response = _apply(p2b, invalidated, owner, key="p2d-invalidated-001")
    _service, failed_response = _apply(p2b, failed, owner, key="p2d-failed-001")
    for response in (invalidated_response, failed_response):
        assert response.receipt.result_refs == []
        assert "event" not in response.receipt.write_set
        assert "episode" not in response.receipt.write_set


def test_stale_session_snapshot_fails_before_repository_prepare():
    _p2a, owner, p2b, p2c, _approvals = _pending()
    p2c_result = _apply_for_owner(p2b, p2c, owner).result
    repository = PrototypeConfirmationTransactionRepository()
    stale = ConfirmationTransactionSessionSnapshot(
        session_id=p2b.source_session_id,
        state="awaiting_approval",
        revision=p2b.proposed_session_revision + 1,
        latest_turn_id=p2b.approval_projection.turn_id,
        latest_sequence=p2b.approval_projection.sequence,
    )
    service = _service_for(p2b, owner, repository)

    with pytest.raises(P2DConfirmationTransactionConflict) as exc_info:
        service.apply(
            P2DConfirmationTransactionRequest(
                owner_user_id=owner,
                p2b_result=p2b,
                p2c_result=p2c_result,
                session=stale,
                approval=_snapshots(p2b)[1],
                idempotency_key="p2d-stale-001",
            )
        )
    assert exc_info.value.code == "P2D_REVISION_MISMATCH"
    assert repository.prepare_calls == 0


def test_non_awaiting_session_state_fails_closed_before_prepare():
    _p2a, owner, p2b, p2c, _approvals = _pending()
    p2c_result = _apply_for_owner(p2b, p2c, owner).result
    repository = PrototypeConfirmationTransactionRepository()
    service = _service_for(p2b, owner, repository)
    session, approval = _snapshots(p2b)
    terminal_session = session.model_copy(update={"state": "completed"})

    with pytest.raises(P2DConfirmationTransactionConflict) as exc_info:
        service.apply(
            P2DConfirmationTransactionRequest(
                owner_user_id=owner,
                p2b_result=p2b,
                p2c_result=p2c_result,
                session=terminal_session,
                approval=approval,
                idempotency_key="p2d-state-001",
            )
        )
    assert exc_info.value.code == "P2D_REVISION_MISMATCH"
    assert repository.prepare_calls == 0


def test_source_binding_mismatch_is_rejected_without_write():
    _p2a, owner, p2b, p2c, _approvals = _pending()
    p2c_result = _apply_for_owner(p2b, p2c, owner).result
    repository = PrototypeConfirmationTransactionRepository()
    service = P2DConfirmationTransactionApplicationService(enabled=True, repository=repository)
    service.bind_session(owner_user_id=owner, session_id=p2b.source_session_id)
    session, approval = _snapshots(p2b)
    forged = approval.model_copy(update={"intent_digest": "sha256:" + "f" * 64})

    with pytest.raises(P2DConfirmationTransactionConflict) as exc_info:
        service.apply(
            P2DConfirmationTransactionRequest(
                owner_user_id=owner,
                p2b_result=p2b,
                p2c_result=p2c_result,
                session=session,
                approval=forged,
                idempotency_key="p2d-binding-001",
            )
        )
    assert exc_info.value.code == "P2D_SOURCE_BINDING_MISMATCH"
    assert repository.prepare_calls == repository.commit_calls == 0


def test_pending_approval_revision_mismatch_is_rejected_before_prepare():
    _p2a, owner, p2b, p2c, _approvals = _pending()
    p2c_result = _apply_for_owner(p2b, p2c, owner).result
    repository = PrototypeConfirmationTransactionRepository()
    service = _service_for(p2b, owner, repository)
    session, approval = _snapshots(p2b)
    stale_approval = approval.model_copy(update={"revision": approval.revision + 1})

    with pytest.raises(P2DConfirmationTransactionConflict) as exc_info:
        service.apply(
            P2DConfirmationTransactionRequest(
                owner_user_id=owner,
                p2b_result=p2b,
                p2c_result=p2c_result,
                session=session,
                approval=stale_approval,
                idempotency_key="p2d-approval-revision-001",
            )
        )
    assert exc_info.value.code == "P2D_SOURCE_BINDING_MISMATCH"
    assert repository.prepare_calls == 0


def test_same_key_and_terminal_snapshot_replay_cannot_commit_again():
    _p2a, owner, p2b, p2c, _approvals = _pending()
    p2c_result = _apply_for_owner(p2b, p2c, owner).result
    repository = PrototypeConfirmationTransactionRepository()
    service, first = _apply(p2b, p2c_result, owner, repository=repository, key="p2d-replay-001")
    session, approval = _terminal_snapshots(p2b, p2c_result)
    second = service.apply(
        P2DConfirmationTransactionRequest(
            owner_user_id=owner,
            p2b_result=p2b,
            p2c_result=p2c_result,
            session=session,
            approval=approval,
            idempotency_key="p2d-replay-001",
        )
    )
    third = service.apply(
        P2DConfirmationTransactionRequest(
            owner_user_id=owner,
            p2b_result=p2b,
            p2c_result=p2c_result,
            session=session,
            approval=approval,
            idempotency_key="p2d-replay-002",
        )
    )
    assert second.replayed is True and third.replayed is True
    assert first.receipt.model_dump(mode="json") == second.receipt.model_dump(mode="json")
    assert first.receipt.model_dump(mode="json") == third.receipt.model_dump(mode="json")
    assert repository.commit_calls == 1
    assert repository.committed_count == 1


def test_same_key_different_digest_is_rejected():
    _p2a, owner, p2b, p2c, _approvals = _pending()
    p2c_result = _apply_for_owner(p2b, p2c, owner).result
    repository = PrototypeConfirmationTransactionRepository()
    service, _first = _apply(p2b, p2c_result, owner, repository=repository, key="p2d-digest-001")
    session, approval = _snapshots(p2b)
    changed = p2c_result.model_copy(update={"source_turn_id": uuid4()})
    # A forged P2C cannot pass source relation, so use a valid different snapshot
    # to exercise the key conflict without exposing any health content.
    changed = p2c_result.model_copy(update={"created_at": p2c_result.created_at + timedelta(seconds=1)})
    with pytest.raises(P2DConfirmationTransactionConflict) as exc_info:
        service.apply(
            P2DConfirmationTransactionRequest(
                owner_user_id=owner,
                p2b_result=p2b,
                p2c_result=changed,
                session=session,
                approval=approval,
                idempotency_key="p2d-digest-001",
            )
        )
    assert exc_info.value.code == "P2D_IDEMPOTENCY_KEY_REUSED"
    assert repository.commit_calls == 1


def test_p2c_result_revision_arithmetic_is_revalidated():
    _p2a, owner, p2b, p2c, _approvals = _pending()
    p2c_result = _apply_for_owner(p2b, p2c, owner).result
    repository = PrototypeConfirmationTransactionRepository()
    service = _service_for(p2b, owner, repository)
    session, approval = _snapshots(p2b)
    forged = p2c_result.model_copy(update={"proposed_session_revision": p2c_result.proposed_session_revision + 1})

    with pytest.raises(P2DConfirmationTransactionConflict) as exc_info:
        service.apply(
            P2DConfirmationTransactionRequest(
                owner_user_id=owner,
                p2b_result=p2b,
                p2c_result=forged,
                session=session,
                approval=approval,
                idempotency_key="p2d-p2c-revision-001",
            )
        )
    assert exc_info.value.code == "P2D_P2C_RESULT_REJECTED"
    assert repository.prepare_calls == 0


@pytest.mark.parametrize("fault", ["prepare", "commit", "read_back"])
def test_repository_fault_rolls_back_and_never_returns_committed(fault):
    _p2a, owner, p2b, p2c, _approvals = _pending()
    p2c_result = _apply_for_owner(p2b, p2c, owner).result
    repository = PrototypeConfirmationTransactionRepository()
    setattr(repository, f"fail_{fault}", True)
    service = _service_for(p2b, owner, repository)
    session, approval = _snapshots(p2b)

    with pytest.raises(P2DConfirmationTransactionConflict) as exc_info:
        service.apply(
            P2DConfirmationTransactionRequest(
                owner_user_id=owner,
                p2b_result=p2b,
                p2c_result=p2c_result,
                session=session,
                approval=approval,
                idempotency_key=f"p2d-fault-{fault}-002",
            )
        )
    assert exc_info.value.code == "P2D_TRANSACTION_FAILED"
    assert service.committed_transaction_count == 0
    assert repository.committed_count == 0
    assert repository.rollback_calls == 1


def test_read_back_mismatch_is_rejected_and_rolled_back():
    _p2a, owner, p2b, p2c, _approvals = _pending()
    p2c_result = _apply_for_owner(p2b, p2c, owner).result
    repository = PrototypeConfirmationTransactionRepository()
    repository.mutate_read_back = True
    service = _service_for(p2b, owner, repository)
    session, approval = _snapshots(p2b)

    with pytest.raises(P2DConfirmationTransactionConflict) as exc_info:
        service.apply(
            P2DConfirmationTransactionRequest(
                owner_user_id=owner,
                p2b_result=p2b,
                p2c_result=p2c_result,
                session=session,
                approval=approval,
                idempotency_key="p2d-readback-002",
            )
        )
    assert exc_info.value.code == "P2D_READ_BACK_MISMATCH"
    assert repository.rollback_calls == 1
    assert repository.committed_count == 0


def test_invalid_timestamp_is_rejected_without_repository_calls():
    _p2a, owner, p2b, p2c, _approvals = _pending()
    p2c_result = _apply_for_owner(p2b, p2c, owner).result
    repository = PrototypeConfirmationTransactionRepository()
    service = _service_for(p2b, owner, repository)
    session, approval = _snapshots(p2b)
    with pytest.raises(P2DConfirmationTransactionConflict) as exc_info:
        service.apply(
            P2DConfirmationTransactionRequest(
                owner_user_id=owner,
                p2b_result=p2b,
                p2c_result=p2c_result,
                session=session,
                approval=approval,
                idempotency_key="p2d-time-001",
                now=__import__("datetime").datetime(2026, 8, 6),
            )
        )
    assert exc_info.value.code == "P2D_INVALID_TIMESTAMP"
    assert repository.prepare_calls == 0


def test_cross_owner_and_disabled_or_invalid_key_fail_closed():
    _p2a, owner, p2b, p2c, _approvals = _pending()
    p2c_result = _apply_for_owner(p2b, p2c, owner).result
    repository = PrototypeConfirmationTransactionRepository()
    service = P2DConfirmationTransactionApplicationService(enabled=False, repository=repository)
    session, approval = _snapshots(p2b)
    with pytest.raises(P2DConfirmationTransactionConflict) as disabled:
        service.apply(
            P2DConfirmationTransactionRequest(
                owner_user_id=owner,
                p2b_result=p2b,
                p2c_result=p2c_result,
                session=session,
                approval=approval,
                idempotency_key="p2d-disabled-001",
            )
        )
    assert disabled.value.code == "P2D_DISABLED"
    service.enabled = True
    service.bind_session(owner_user_id=owner, session_id=p2b.source_session_id)
    session, approval = _snapshots(p2b)
    with pytest.raises(P2DConfirmationTransactionConflict) as bad_key:
        service.apply(
            P2DConfirmationTransactionRequest(
                owner_user_id=uuid4(),
                p2b_result=p2b,
                p2c_result=p2c_result,
                session=session,
                approval=approval,
                idempotency_key="bad",
            )
        )
    assert bad_key.value.code == "P2D_INVALID_IDEMPOTENCY_KEY"


def test_forged_p2b_and_non_event_plan_are_rejected():
    _p2a, owner, p2b, p2c, _approvals = _pending()
    p2c_result = _apply_for_owner(p2b, p2c, owner).result
    repository = PrototypeConfirmationTransactionRepository()
    service = P2DConfirmationTransactionApplicationService(enabled=True, repository=repository)
    service.bind_session(owner_user_id=owner, session_id=p2b.source_session_id)
    session, approval = _snapshots(p2b)
    forged = p2b.model_copy(update={"proposed_session_revision": p2b.proposed_session_revision + 1})
    with pytest.raises(P2DConfirmationTransactionConflict) as exc_info:
        service.apply(
            P2DConfirmationTransactionRequest(
                owner_user_id=owner,
                p2b_result=forged,
                p2c_result=p2c_result,
                session=session,
                approval=approval,
                idempotency_key="p2d-forged-001",
            )
        )
    assert exc_info.value.code == "P2D_P2B_RESULT_REJECTED"
    with pytest.raises(ValueError):
        ConfirmationTransactionPlan(
            transaction_id=uuid4(),
            session_id=p2b.source_session_id,
            approval_id=p2b.approval.approval_id,
            source_turn_id=p2b.source_turn_id,
            request_digest="sha256:" + "a" * 64,
            expected_session_revision=3,
            committed_session_revision=4,
            approval_revision=2,
            terminal_status="executed",
            lifecycle_status="completed",
            lifecycle_state="completed",
            lifecycle_turn_id=uuid4(),
            write_set=["session", "lifecycle_turn", "audit_metadata"],
            result_refs=[],
        )


def test_non_executed_plan_cannot_carry_an_event_ref():
    _p2a, owner, p2b, _p2c, _approvals = _pending()
    with pytest.raises(ValueError):
        ConfirmationTransactionPlan(
            transaction_id=uuid4(),
            session_id=p2b.source_session_id,
            approval_id=p2b.approval.approval_id,
            source_turn_id=p2b.source_turn_id,
            request_digest="sha256:" + "b" * 64,
            expected_session_revision=3,
            committed_session_revision=4,
            approval_revision=2,
            terminal_status="denied",
            lifecycle_status="approval_decided",
            lifecycle_state="awaiting_confirmation",
            lifecycle_turn_id=uuid4(),
            write_set=["session", "lifecycle_turn", "approval", "event", "audit_metadata"],
            result_refs=[{"type": "event", "id": uuid4()}],
        )


def test_receipt_schema_and_privacy_surface_are_valid():
    _p2a, owner, p2b, p2c, _approvals = _pending()
    p2c_result = _apply_for_owner(p2b, p2c, owner).result
    _service, response = _apply(p2b, p2c_result, owner)
    payload = response.receipt.model_dump(mode="json", exclude_none=True)
    schema = json.loads((ROOT / "docs/contracts/confirmation-transaction-receipt.schema.json").read_text())
    Draft202012Validator(schema, format_checker=FormatChecker()).validate(payload)
    serialized = json.dumps(payload, ensure_ascii=False)
    for forbidden in ("candidate", "raw_input", "SafetyEvaluation", "prompt", str(owner)):
        assert forbidden.lower() not in serialized.lower()


def test_success_does_not_mutate_p2b_p2c_or_server_snapshots():
    _p2a, owner, p2b, p2c, _approvals = _pending()
    p2c_result = _apply_for_owner(p2b, p2c, owner).result
    session, approval = _snapshots(p2b)
    before = (
        p2b.model_dump(mode="json"),
        p2c_result.model_dump(mode="json"),
        session.model_dump(mode="json"),
        approval.model_dump(mode="json"),
    )

    _service, _response = _apply(p2b, p2c_result, owner)

    after = (
        p2b.model_dump(mode="json"),
        p2c_result.model_dump(mode="json"),
        session.model_dump(mode="json"),
        approval.model_dump(mode="json"),
    )
    assert after == before
