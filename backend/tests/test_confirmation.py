from __future__ import annotations

from datetime import datetime, timezone
from uuid import uuid4

import pytest

from body_companion.domain.confirmation import (
    CONFIRMABLE_FIELDS,
    ApprovalDecisionRequest,
    ConfirmationConflict,
    ConfirmationRequest,
    PrototypeApprovalStore,
)
from body_companion.domain.policy import digest_for
from body_companion.domain.safety import RuleCatalog, SafetyEngine
from body_companion.domain.types import (
    AssessmentDraft,
    BodyLocation,
    LocationSource,
    Mapping,
    SourceRef,
    Sensation,
    ApproximateDateTime,
    Intensity,
    TemporalPattern,
    DraftCandidate,
    EpisodeSelection,
)


def draft() -> tuple[AssessmentDraft, DraftCandidate]:
    marker_id = uuid4()
    now = datetime.now(timezone.utc)
    location = BodyLocation(
        marker_id=marker_id,
        region_id="body.lower_limb.knee",
        ontology_version="pending",
        laterality="left",
        surface="anterior",
        depth="unspecified",
        shape="point",
        anchor_2d={
            "asset_id": "prototype-2d",
            "asset_version": "pending",
            "view": "front",
            "point": {"x": 0.5, "y": 0.6},
        },
        mapping=Mapping(method="direct_user_selection", confidence=1, reviewed_by_user=False),
        source=LocationSource(interaction="body_map_2d"),
        created_at=now,
    )
    sensation = Sensation(
        sensation_id=uuid4(),
        code="aching",
        intensities=[Intensity(context="current", value=3)],
        location_marker_ids=[marker_id],
        source=SourceRef(type="user_report", source_id="turn-input"),
    )
    event_draft = AssessmentDraft(
        locations=[location],
        sensations=[sensation],
        temporal=TemporalPattern(
            onset=ApproximateDateTime(precision="unknown", user_text="不清楚"),
            onset_mode="unknown",
            course="intermittent",
            frequency="unknown",
        ),
        trend="unknown",
    )
    return event_draft, DraftCandidate(
        event_draft=event_draft,
        user_fact_summary="synthetic draft",
        draft_digest=digest_for(event_draft),
    )


def safety():
    return SafetyEngine(RuleCatalog(version="rules.test", available=True)).evaluate(user_text="synthetic")


def confirmation(candidate, *, session_id, turn_id, revision=2):
    return ConfirmationRequest(
        turn_id=turn_id,
        expected_revision=revision,
        reviewed_fields=list(CONFIRMABLE_FIELDS),
        draft_digest=candidate.draft_digest,
        episode_selection=EpisodeSelection(mode="create_new", started_on=datetime.now(timezone.utc).date()),
    )


def test_confirmation_requires_second_explicit_decision_and_is_idempotent():
    event_draft, candidate = draft()
    session_id = uuid4()
    turn_id = uuid4()
    owner_id = uuid4()
    store = PrototypeApprovalStore()
    intent = store.create_intent(
        owner_id=owner_id,
        session_id=session_id,
        current_revision=2,
        candidate=candidate,
        source_turn_id=turn_id,
        confirmation=confirmation(candidate, session_id=session_id, turn_id=turn_id),
        safety=safety(),
    )
    assert intent.approval.status == "pending"
    assert intent.approval.revision == 1

    request = ApprovalDecisionRequest(
        decision="approve",
        intent_digest=intent.approval.intent_digest,
        expected_revision=1,
    )
    snapshot = {"session_id": str(session_id), "state": "awaiting_approval", "revision": 2}
    turn = {"turn_id": str(turn_id), "status": "approval_required"}
    result = store.decide(
        owner_id=owner_id,
        approval_id=intent.approval.approval_id,
        request=request,
        idempotency_key="confirm-1",
        current_session_revision=2,
        session_snapshot=snapshot,
        latest_turn=turn,
    )
    assert result.status == "executed"
    assert result.revision == 4
    assert len(result.result_refs) == 1

    replay = store.decide(
        owner_id=owner_id,
        approval_id=intent.approval.approval_id,
        request=request,
        idempotency_key="confirm-1",
        current_session_revision=2,
        session_snapshot=snapshot,
        latest_turn=turn,
    )
    assert replay == result
    second_key = store.decide(
        owner_id=owner_id,
        approval_id=intent.approval.approval_id,
        request=request,
        idempotency_key="confirm-2",
        current_session_revision=2,
        session_snapshot=snapshot,
        latest_turn=turn,
    )
    assert second_key.result_refs == result.result_refs


def test_confirmation_rejects_risk_gate_and_stale_digest():
    _event_draft, candidate = draft()
    session_id = uuid4()
    turn_id = uuid4()
    store = PrototypeApprovalStore()
    blocked = SafetyEngine(RuleCatalog(version="none", available=False)).evaluate(user_text="synthetic")
    with pytest.raises(ConfirmationConflict) as exc_info:
        store.create_intent(
            owner_id=uuid4(),
            session_id=session_id,
            current_revision=2,
            candidate=candidate,
            source_turn_id=turn_id,
            confirmation=confirmation(candidate, session_id=session_id, turn_id=turn_id),
            safety=blocked,
        )
    assert exc_info.value.code == "SAFETY_GATE_BLOCKED"

    available_store = PrototypeApprovalStore()
    stale = ConfirmationRequest(
        turn_id=turn_id,
        expected_revision=2,
        reviewed_fields=list(CONFIRMABLE_FIELDS),
        draft_digest="sha256:" + "1" * 64,
        episode_selection=EpisodeSelection(mode="create_new", started_on=datetime.now(timezone.utc).date()),
    )
    with pytest.raises(ConfirmationConflict) as stale_error:
        available_store.create_intent(
            owner_id=uuid4(),
            session_id=session_id,
            current_revision=2,
            candidate=candidate,
            source_turn_id=turn_id,
            confirmation=stale,
            safety=safety(),
        )
    assert stale_error.value.code == "DRAFT_DIGEST_MISMATCH"


def test_approval_idempotency_key_cannot_change_request():
    _event_draft, candidate = draft()
    owner_id = uuid4()
    session_id = uuid4()
    turn_id = uuid4()
    store = PrototypeApprovalStore()
    intent = store.create_intent(
        owner_id=owner_id,
        session_id=session_id,
        current_revision=2,
        candidate=candidate,
        source_turn_id=turn_id,
        confirmation=confirmation(candidate, session_id=session_id, turn_id=turn_id),
        safety=safety(),
    )
    approve = ApprovalDecisionRequest(decision="approve", intent_digest=intent.approval.intent_digest, expected_revision=1)
    deny = ApprovalDecisionRequest(decision="deny", intent_digest=intent.approval.intent_digest, expected_revision=1)
    snapshot = {"session_id": str(session_id), "state": "awaiting_approval", "revision": 2}
    turn = {"turn_id": str(turn_id), "status": "approval_required"}
    store.decide(
        owner_id=owner_id,
        approval_id=intent.approval.approval_id,
        request=approve,
        idempotency_key="same-key",
        current_session_revision=2,
        session_snapshot=snapshot,
        latest_turn=turn,
    )
    with pytest.raises(ConfirmationConflict) as exc_info:
        store.decide(
            owner_id=owner_id,
            approval_id=intent.approval.approval_id,
            request=deny,
            idempotency_key="same-key",
            current_session_revision=2,
            session_snapshot=snapshot,
            latest_turn=turn,
        )
    assert exc_info.value.code == "IDEMPOTENCY_CONFLICT"


def test_denial_is_terminal_without_event_reference():
    _event_draft, candidate = draft()
    owner_id = uuid4()
    session_id = uuid4()
    turn_id = uuid4()
    store = PrototypeApprovalStore()
    intent = store.create_intent(
        owner_id=owner_id,
        session_id=session_id,
        current_revision=2,
        candidate=candidate,
        source_turn_id=turn_id,
        confirmation=confirmation(candidate, session_id=session_id, turn_id=turn_id),
        safety=safety(),
    )
    result = store.decide(
        owner_id=owner_id,
        approval_id=intent.approval.approval_id,
        request=ApprovalDecisionRequest(
            decision="deny", intent_digest=intent.approval.intent_digest, expected_revision=1
        ),
        idempotency_key="deny-1",
        current_session_revision=2,
        session_snapshot={"state": "awaiting_confirmation"},
        latest_turn={"turn_id": str(turn_id), "status": "draft_ready"},
    )
    assert result.status == "denied"
    assert result.revision == 2
    assert result.result_refs == []
