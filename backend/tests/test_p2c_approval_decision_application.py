from __future__ import annotations

from dataclasses import replace
from datetime import timedelta
import json
from pathlib import Path
from uuid import uuid4

import pytest
from jsonschema import Draft202012Validator, FormatChecker

from body_companion.application.p2c_approval_decision_application import (
    P2CApprovalDecisionApplicationConflict,
    P2CApprovalDecisionApplicationService,
    P2CApprovalDecisionRequest,
)
from body_companion.domain.confirmation import (
    ApprovalDecisionRequest,
    PrototypeApprovalStore,
)
from body_companion.domain.events import PrototypeEventStore

from test_p2b_confirmation_intent_application import (
    NOW,
    _p2a_draft,
    _request,
    _safety,
    _service,
)


ROOT = Path(__file__).resolve().parents[2]


def _pending(*, event_writer=None, p2b_now=None):
    p2a, owner, _session_id, p2a_result = _p2a_draft()
    approval_store = PrototypeApprovalStore(event_writer=event_writer)
    p2b_service = _service(p2a_result, owner, approval_store=approval_store)
    request = _request(p2a_result, owner)
    if p2b_now is not None:
        request = replace(request, now=p2b_now)
    p2b = p2b_service.apply(request).result
    p2c = P2CApprovalDecisionApplicationService(enabled=True, approval_store=approval_store)
    p2c.bind_session(owner_user_id=owner, session_id=p2b.source_session_id)
    return p2a, owner, p2b, p2c, approval_store


def _decision(p2b, *, choice: str = "approve", expected_revision: int = 1):
    return ApprovalDecisionRequest(
        decision=choice,
        intent_digest=p2b.approval.intent_digest,
        expected_revision=expected_revision,
    )


def _apply_for_owner(p2b, p2c, owner, *, key="p2c-decision-001", choice="approve", revision=None, now=None, decision=None):
    return p2c.apply(
        P2CApprovalDecisionRequest(
            owner_user_id=owner,
            p2b_result=p2b,
            decision=decision or _decision(p2b, choice=choice),
            current_session_revision=revision or p2b.previous_session_revision,
            idempotency_key=key,
            now=now or NOW + timedelta(seconds=3),
        )
    )


def test_valid_deny_returns_terminal_projection_without_event():
    _p2a, owner, p2b, p2c, store = _pending()

    response = _apply_for_owner(p2b, p2c, owner, choice="deny")

    assert response.replayed is False
    assert response.result.approval.status == "denied"
    assert response.result.decision.resolution_reason == "user_denied"
    assert response.result.lifecycle.status == "approval_decided"
    assert response.result.lifecycle.state == "awaiting_confirmation"
    assert response.result.decision.result_refs == []
    assert store.get_result(owner_id=owner, approval_id=p2b.approval.approval_id).status == "denied"


def test_valid_approve_writes_exactly_one_prototype_event_and_completed_projection():
    event_store = PrototypeEventStore()
    _p2a, owner, p2b, p2c, approvals = _pending(event_writer=event_store)

    response = _apply_for_owner(p2b, p2c, owner)

    assert response.result.approval.status == "executed"
    assert response.result.lifecycle.status == "completed"
    assert len(response.result.decision.result_refs) == 1
    assert response.result.decision.result_refs[0].type == "event"
    assert event_store.count_events(owner_id=owner) == 1
    assert approvals.get_result(owner_id=owner, approval_id=p2b.approval.approval_id).result_refs == response.result.decision.result_refs


def test_supported_r2_is_approved_without_new_medical_output():
    p2a, owner, _session_id, p2a_result = _p2a_draft()
    event_store = PrototypeEventStore()
    approvals = PrototypeApprovalStore(event_writer=event_store)
    p2b_service = _service(p2a_result, owner, approval_store=approvals)
    p2b = p2b_service.apply(_request(p2a_result, owner, safety=_safety(tier="R2"))).result
    p2c = P2CApprovalDecisionApplicationService(enabled=True, approval_store=approvals)
    p2c.bind_session(owner_user_id=owner, session_id=p2b.source_session_id)

    response = _apply_for_owner(p2b, p2c, owner)

    assert response.result.approval.status == "executed"
    assert event_store.count_events(owner_id=owner) == 1
    assert "diagnos" not in json.dumps(response.result.model_dump(mode="json"), ensure_ascii=False).lower()


def test_same_key_replay_is_byte_stable_and_does_not_write_again():
    event_store = PrototypeEventStore()
    _p2a, owner, p2b, p2c, _approvals = _pending(event_writer=event_store)

    first = _apply_for_owner(p2b, p2c, owner, key="p2c-replay-001")
    second = _apply_for_owner(p2b, p2c, owner, key="p2c-replay-001")

    assert second.replayed is True
    assert first.result.model_dump(mode="json") == second.result.model_dump(mode="json")
    assert event_store.count_events(owner_id=owner) == 1


def test_terminal_approval_replays_with_a_new_network_key():
    event_store = PrototypeEventStore()
    _p2a, owner, p2b, p2c, _approvals = _pending(event_writer=event_store)

    first = _apply_for_owner(p2b, p2c, owner, key="p2c-terminal-001")
    replay = _apply_for_owner(p2b, p2c, owner, key="p2c-terminal-002", revision=999)

    assert replay.replayed is True
    assert replay.result.model_dump(mode="json") == first.result.model_dump(mode="json")
    assert event_store.count_events(owner_id=owner) == 1


def test_same_key_with_another_request_digest_is_rejected():
    _p2a, owner, p2b, p2c, store = _pending()
    _apply_for_owner(p2b, p2c, owner, key="p2c-conflict-001", choice="deny")
    with pytest.raises(P2CApprovalDecisionApplicationConflict) as exc_info:
        _apply_for_owner(p2b, p2c, owner, key="p2c-conflict-001", choice="approve")
    assert exc_info.value.code == "P2C_IDEMPOTENCY_KEY_REUSED"
    assert store.get(owner_id=owner, approval_id=p2b.approval.approval_id).approval.status == "denied"


def test_stale_current_session_revision_is_rejected_without_side_effect():
    event_store = PrototypeEventStore()
    _p2a, owner, p2b, p2c, approvals = _pending(event_writer=event_store)

    with pytest.raises(P2CApprovalDecisionApplicationConflict) as exc_info:
        _apply_for_owner(p2b, p2c, owner, revision=p2b.previous_session_revision + 1)
    assert exc_info.value.code == "P2C_SESSION_REVISION_MISMATCH"
    assert approvals.get(owner_id=owner, approval_id=p2b.approval.approval_id).approval.status == "pending"
    assert event_store.count_events(owner_id=owner) == 0


def test_wrong_digest_is_rejected_before_event_writer():
    event_store = PrototypeEventStore()
    _p2a, owner, p2b, p2c, approvals = _pending(event_writer=event_store)
    bad = _decision(p2b).model_copy(update={"intent_digest": "sha256:" + "a" * 64})

    with pytest.raises(P2CApprovalDecisionApplicationConflict) as exc_info:
        _apply_for_owner(p2b, p2c, owner, decision=bad)
    assert exc_info.value.code == "P2C_INTENT_DIGEST_MISMATCH"
    assert approvals.get(owner_id=owner, approval_id=p2b.approval.approval_id).approval.status == "pending"
    assert event_store.count_events(owner_id=owner) == 0


def test_wrong_approval_revision_is_rejected():
    _p2a, owner, p2b, p2c, approvals = _pending()
    with pytest.raises(P2CApprovalDecisionApplicationConflict) as exc_info:
        _apply_for_owner(p2b, p2c, owner, decision=_decision(p2b, expected_revision=2))
    assert exc_info.value.code == "P2C_APPROVAL_REVISION_MISMATCH"
    assert approvals.get(owner_id=owner, approval_id=p2b.approval.approval_id).approval.status == "pending"


def test_model_constructed_decision_is_revalidated_before_store_call():
    _p2a, owner, p2b, p2c, approvals = _pending()
    forged = ApprovalDecisionRequest.model_construct(
        decision="approve",
        intent_digest=p2b.approval.intent_digest,
        expected_revision=0,
    )
    with pytest.raises(P2CApprovalDecisionApplicationConflict) as exc_info:
        _apply_for_owner(p2b, p2c, owner, decision=forged)
    assert exc_info.value.code == "P2C_DECISION_REJECTED"
    assert approvals.get(owner_id=owner, approval_id=p2b.approval.approval_id).approval.status == "pending"


def test_expired_pending_intent_is_not_silently_executed():
    p2a, owner, _session_id, p2a_result = _p2a_draft()
    approvals = PrototypeApprovalStore(event_writer=PrototypeEventStore())
    p2b_service = _service(p2a_result, owner, approval_store=approvals)
    p2b = p2b_service.apply(replace(_request(p2a_result, owner), now=NOW)).result
    p2c = P2CApprovalDecisionApplicationService(enabled=True, approval_store=approvals)
    p2c.bind_session(owner_user_id=owner, session_id=p2b.source_session_id)

    with pytest.raises(P2CApprovalDecisionApplicationConflict) as exc_info:
        _apply_for_owner(p2b, p2c, owner, now=NOW + timedelta(minutes=15))
    assert exc_info.value.code == "P2C_APPROVAL_EXPIRED"
    assert approvals.get(owner_id=owner, approval_id=p2b.approval.approval_id).approval.status == "pending"


def test_cross_owner_is_not_enumerable():
    _p2a, owner, p2b, p2c, _approvals = _pending()
    with pytest.raises(P2CApprovalDecisionApplicationConflict) as exc_info:
        _apply_for_owner(p2b, p2c, uuid4())
    assert exc_info.value.code == "P2C_RESOURCE_NOT_FOUND"


def test_forged_p2b_model_is_rejected_by_relation_validation():
    _p2a, owner, p2b, p2c, approvals = _pending()
    forged = p2b.model_copy(update={"source_turn_id": uuid4()})
    with pytest.raises(P2CApprovalDecisionApplicationConflict) as exc_info:
        _apply_for_owner(forged, p2c, owner)
    assert exc_info.value.code == "P2C_P2B_RESULT_REJECTED"
    assert approvals.get(owner_id=owner, approval_id=p2b.approval.approval_id).approval.status == "pending"


def test_store_immutable_binding_mismatch_is_rejected():
    _p2a, owner, p2b, p2c, approvals = _pending()
    altered_approval = p2b.approval.model_copy(
        update={"created_at": p2b.approval.created_at + timedelta(seconds=1)}
    )
    altered = p2b.model_copy(update={"approval": altered_approval})
    with pytest.raises(P2CApprovalDecisionApplicationConflict) as exc_info:
        _apply_for_owner(altered, p2c, owner)
    assert exc_info.value.code == "P2C_SOURCE_BINDING_MISMATCH"
    assert approvals.get(owner_id=owner, approval_id=p2b.approval.approval_id).approval.status == "pending"


class _FailingEventWriter:
    def commit_confirmed(self, **_kwargs):
        raise RuntimeError("synthetic writer failure")


def test_event_writer_failure_returns_stable_error_and_keeps_pending():
    _p2a, owner, p2b, p2c, approvals = _pending(event_writer=_FailingEventWriter())
    with pytest.raises(P2CApprovalDecisionApplicationConflict) as exc_info:
        _apply_for_owner(p2b, p2c, owner)
    assert exc_info.value.code == "P2C_EVENT_WRITE_FAILED"
    assert approvals.get(owner_id=owner, approval_id=p2b.approval.approval_id).approval.status == "pending"


def test_deny_never_calls_a_failing_event_writer():
    _p2a, owner, p2b, p2c, approvals = _pending(event_writer=_FailingEventWriter())
    response = _apply_for_owner(p2b, p2c, owner, choice="deny")
    assert response.result.approval.status == "denied"
    assert response.result.decision.result_refs == []
    assert approvals.get_result(owner_id=owner, approval_id=p2b.approval.approval_id).status == "denied"


def test_existing_context_invalidated_terminal_is_projected_without_refs():
    _p2a, owner, p2b, p2c, approvals = _pending()
    intent = approvals.get(owner_id=owner, approval_id=p2b.approval.approval_id)
    invalidated = approvals.decide(
        owner_id=owner,
        approval_id=intent.approval.approval_id,
        request=_decision(p2b),
        idempotency_key="external-invalidate-001",
        current_session_revision=p2b.previous_session_revision + 1,
        session_snapshot={},
        latest_turn={},
        now=NOW + timedelta(seconds=3),
    )
    assert invalidated.status == "invalidated"

    response = _apply_for_owner(p2b, p2c, owner, key="p2c-invalidated-001")

    assert response.replayed is True
    assert response.result.approval.status == "invalidated"
    assert response.result.lifecycle.state == "awaiting_confirmation"
    assert response.result.decision.result_refs == []
    schema = json.loads((ROOT / "docs/contracts/approval-decision-application-result.schema.json").read_text())
    Draft202012Validator(schema, format_checker=FormatChecker()).validate(
        response.result.model_dump(mode="json", exclude_none=True)
    )


def test_result_schema_and_privacy_surface_are_valid():
    _p2a, owner, p2b, p2c, _approvals = _pending(event_writer=PrototypeEventStore())
    result = _apply_for_owner(p2b, p2c, owner).result
    payload = result.model_dump(mode="json", exclude_none=True)
    schema = json.loads((ROOT / "docs/contracts/approval-decision-application-result.schema.json").read_text())
    Draft202012Validator(schema, format_checker=FormatChecker()).validate(payload)
    serialized = json.dumps(payload, ensure_ascii=False)
    for forbidden in ("synthetic server-captured input", "candidate", "SafetyEvaluation", "prompt", str(owner)):
        assert forbidden.lower() not in serialized.lower()


def test_disabled_feature_and_invalid_key_have_zero_calls():
    _p2a, owner, p2b, p2c, approvals = _pending()
    p2c.enabled = False
    with pytest.raises(P2CApprovalDecisionApplicationConflict) as disabled:
        _apply_for_owner(p2b, p2c, owner)
    assert disabled.value.code == "P2C_DISABLED"
    p2c.enabled = True
    with pytest.raises(P2CApprovalDecisionApplicationConflict) as bad_key:
        _apply_for_owner(p2b, p2c, owner, key="bad")
    assert bad_key.value.code == "P2C_INVALID_IDEMPOTENCY_KEY"
    assert approvals.get(owner_id=owner, approval_id=p2b.approval.approval_id).approval.status == "pending"


def test_p2c_does_not_change_p2a_projection():
    p2a, owner, p2b, p2c, _approvals = _pending(event_writer=PrototypeEventStore())
    before_session = p2a.get_session(owner_user_id=owner, session_id=p2b.source_session_id)
    before_turn = p2a.ledger.get_latest_turn(owner_user_id=owner, session_id=p2b.source_session_id)

    _apply_for_owner(p2b, p2c, owner)

    assert p2a.get_session(owner_user_id=owner, session_id=p2b.source_session_id) == before_session
    assert p2a.ledger.get_latest_turn(owner_user_id=owner, session_id=p2b.source_session_id) == before_turn
