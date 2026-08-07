from __future__ import annotations

from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
from uuid import UUID, uuid4

import pytest
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

import body_companion.domain.session_turn_projection as session_turn_projection

from body_companion.application.p2a_session_turn_projection import (
    P2ASessionTurnProjectionService,
    P2ATurnApplicationRequest,
)
from body_companion.domain.agent_turn_application import AgentTurnApplicationResult
from body_companion.domain.session_turn_projection import (
    P2ASessionTurnLedger,
    SessionTurnProjectionConflict,
)
from body_companion.domain.types import (
    AgentQuestion,
    AskQuestionCandidate,
    ApproximateDateTime,
    AssessmentDraft,
    BodyLocation,
    DraftCandidate,
    Sensation,
    SourceRef,
    TemporalPattern,
)


ROOT = Path(__file__).resolve().parents[2]


def _now() -> datetime:
    return datetime(2026, 8, 6, 10, 0, tzinfo=timezone.utc)


@pytest.fixture(autouse=True)
def _freeze_p2a_wall_clock(monkeypatch: pytest.MonkeyPatch) -> None:
    """Keep requests that exercise the production default clock deterministic."""
    monkeypatch.setattr(
        session_turn_projection,
        "utc_now",
        lambda: _now() + timedelta(seconds=1),
    )


def _ask_result(
    session_id: UUID,
    *,
    turn_id: UUID | None = None,
    sequence: int = 1,
    draft_revision: int = 1,
    in_reply_to_turn_id: UUID | None = None,
    created_at: datetime | None = None,
) -> AgentTurnApplicationResult:
    return AgentTurnApplicationResult(
        session_id=session_id,
        turn_id=turn_id or uuid4(),
        sequence=sequence,
        draft_revision=draft_revision,
        in_reply_to_turn_id=in_reply_to_turn_id,
        status="accepted",
        state="awaiting_user",
        handoff_status="ready_for_agent",
        agent_result_status="agent_completed",
        candidate=AskQuestionCandidate(
            questions=[
                AgentQuestion(
                    question_id="sensation.type",
                    category="sensation",
                    prompt="哪一种感觉更接近？",
                    answer_type="free_text",
                    required=True,
                )
            ],
            context_summary="synthetic context",
        ),
        agent_source_ids=["source.synthetic"],
        agent_version="test-agent-1",
        prompt_version="test-prompt-1",
        created_at=created_at or _now(),
    )


def _draft_result(session_id: UUID) -> AgentTurnApplicationResult:
    marker_id = uuid4()
    source = SourceRef(type="user_report", source_id="synthetic-turn")
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
        mapping={"method": "direct_user_selection", "confidence": 1, "reviewed_by_user": False},
        source={"interaction": "body_map_2d"},
        created_at=_now(),
    )
    draft = AssessmentDraft(
        locations=[location],
        sensations=[
            Sensation(
                sensation_id=uuid4(),
                code="aching",
                intensities=[],
                location_marker_ids=[marker_id],
                source=source,
            )
        ],
        temporal=TemporalPattern(
            onset=ApproximateDateTime(precision="unknown", user_text="未知"),
            onset_mode="unknown",
            course="intermittent",
            frequency="unknown",
        ),
        trend="unknown",
    )
    return AgentTurnApplicationResult(
        session_id=session_id,
        turn_id=uuid4(),
        sequence=1,
        draft_revision=1,
        status="accepted",
        state="awaiting_confirmation",
        handoff_status="ready_for_agent",
        agent_result_status="agent_completed",
        candidate=DraftCandidate(
            event_draft=draft,
            user_fact_summary="synthetic facts",
            uncertainties=[],
            draft_digest="sha256:" + "0" * 64,
        ),
        agent_source_ids=["source.synthetic"],
        agent_version="test-agent-1",
        prompt_version="test-prompt-1",
        created_at=_now(),
    )


def _service() -> tuple[P2ASessionTurnProjectionService, UUID, UUID]:
    service = P2ASessionTurnProjectionService(enabled=True)
    owner = uuid4()
    session_id = uuid4()
    service.start_session(owner_user_id=owner, session_id=session_id, idempotency_key="start-001", now=_now())
    return service, owner, session_id


def test_new_session_is_typed_and_owner_is_not_in_projection():
    service = P2ASessionTurnProjectionService(enabled=True)
    owner = uuid4()
    session_id = uuid4()
    started = service.start_session(
        owner_user_id=owner,
        session_id=session_id,
        idempotency_key="start-001",
        now=_now(),
    )
    assert started.session.state == "created"
    assert started.session.revision == 1
    assert started.session.latest_sequence == 0
    assert "owner_user_id" not in started.session.model_dump()


def test_first_ask_result_advances_session_and_turn_atomically():
    service, owner, session_id = _service()
    response = service.apply(
        P2ATurnApplicationRequest(
            owner_user_id=owner,
            result=_ask_result(session_id),
            expected_revision=1,
            idempotency_key="turn-001",
            now=_now() + timedelta(seconds=1),
        )
    )
    assert response.replayed is False
    assert response.result.transition == "initial_turn"
    assert response.result.session.state == "awaiting_user"
    assert response.result.session.revision == response.result.turn.revision == 2
    assert response.result.session.latest_turn_id == response.result.turn.turn_id


def test_default_request_clock_is_frozen_by_the_p2a_fixture():
    service, owner, session_id = _service()
    response = service.apply(
        P2ATurnApplicationRequest(
            owner_user_id=owner,
            result=_ask_result(session_id),
            expected_revision=1,
            idempotency_key="turn-default-clock",
        )
    )
    assert response.result.session.updated_at == _now() + timedelta(seconds=1)
    assert response.result.created_at == _now() + timedelta(seconds=1)
    assert response.result.turn.created_at == _now()


def test_draft_result_stops_at_confirmation_without_formal_resource_refs():
    service = P2ASessionTurnProjectionService(enabled=True)
    owner = uuid4()
    session_id = uuid4()
    service.start_session(owner_user_id=owner, session_id=session_id, idempotency_key="start-001", now=_now())
    response = service.apply(
        P2ATurnApplicationRequest(
            owner_user_id=owner,
            result=_draft_result(session_id),
            expected_revision=1,
            idempotency_key="turn-001",
            now=_now() + timedelta(seconds=1),
        )
    )
    assert response.result.session.state == "awaiting_confirmation"
    assert response.result.turn.output_kind == "draft_ready"
    payload = response.result.model_dump(mode="json")
    assert not any(key in json.dumps(payload) for key in ("approval_id", "event_id", "episode_id", "user_id"))


def test_awaiting_user_continuation_requires_direct_predecessor_and_higher_draft_revision():
    service, owner, session_id = _service()
    first = service.apply(
        P2ATurnApplicationRequest(
            owner_user_id=owner,
            result=_ask_result(session_id),
            expected_revision=1,
            idempotency_key="turn-001",
            now=_now() + timedelta(seconds=1),
        )
    ).result.turn
    second = _ask_result(
        session_id,
        sequence=2,
        draft_revision=2,
        in_reply_to_turn_id=first.turn_id,
        created_at=_now() + timedelta(seconds=2),
    )
    response = service.apply(
        P2ATurnApplicationRequest(
            owner_user_id=owner,
            result=second,
            expected_revision=2,
            idempotency_key="turn-002",
            now=_now() + timedelta(seconds=2),
        )
    )
    assert response.result.transition == "continuation"
    assert response.result.session.revision == 3
    assert response.result.turn.in_reply_to_turn_id == first.turn_id


def test_confirmation_state_cannot_be_used_for_another_agent_turn():
    service = P2ASessionTurnProjectionService(enabled=True)
    owner = uuid4()
    session_id = uuid4()
    service.start_session(owner_user_id=owner, session_id=session_id, idempotency_key="start-001", now=_now())
    service.apply(
        P2ATurnApplicationRequest(
            owner_user_id=owner,
            result=_draft_result(session_id),
            expected_revision=1,
            idempotency_key="turn-001",
            now=_now() + timedelta(seconds=1),
        )
    )
    with pytest.raises(SessionTurnProjectionConflict) as exc:
        service.apply(
            P2ATurnApplicationRequest(
                owner_user_id=owner,
                result=_ask_result(session_id, sequence=2, draft_revision=2, in_reply_to_turn_id=uuid4()),
                expected_revision=2,
                idempotency_key="turn-002",
            )
        )
    assert exc.value.code == "P2A_CONTINUATION_NOT_ALLOWED"
    assert service.get_session(owner_user_id=owner, session_id=session_id).revision == 2


@pytest.mark.parametrize(
    ("expected_revision", "mutator", "code"),
    [
        (2, lambda result: result.model_copy(update={"sequence": 3, "draft_revision": 2, "in_reply_to_turn_id": uuid4()}), "P2A_PREDECESSOR_MISMATCH"),
        (1, lambda result: result, "P2A_REVISION_MISMATCH"),
    ],
)
def test_wrong_predecessor_or_stale_revision_has_zero_side_effects(expected_revision, mutator, code):
    service, owner, session_id = _service()
    first = service.apply(
        P2ATurnApplicationRequest(
            owner_user_id=owner,
            result=_ask_result(session_id),
            expected_revision=1,
            idempotency_key="turn-001",
        )
    ).result.turn
    candidate = _ask_result(session_id, sequence=2, draft_revision=2, in_reply_to_turn_id=first.turn_id)
    bad = mutator(candidate)
    with pytest.raises(SessionTurnProjectionConflict) as exc:
        service.apply(
            P2ATurnApplicationRequest(
                owner_user_id=owner,
                result=bad,
                expected_revision=expected_revision,
                idempotency_key="turn-002",
            )
        )
    assert exc.value.code == code
    assert service.get_session(owner_user_id=owner, session_id=session_id).revision == 2


def test_same_key_same_request_replays_exact_result_without_revision_increment():
    service, owner, session_id = _service()
    result = _ask_result(session_id)
    request = P2ATurnApplicationRequest(owner_user_id=owner, result=result, expected_revision=1, idempotency_key="turn-001", now=_now() + timedelta(seconds=1))
    first = service.apply(request)
    replay = service.apply(request)
    assert replay.replayed is True
    assert replay.result == first.result
    assert replay.result.model_dump(mode="json") == first.result.model_dump(mode="json")
    assert service.get_session(owner_user_id=owner, session_id=session_id).revision == 2


def test_same_key_different_digest_is_rejected_without_consuming_next_sequence():
    service, owner, session_id = _service()
    service.apply(P2ATurnApplicationRequest(owner_user_id=owner, result=_ask_result(session_id), expected_revision=1, idempotency_key="turn-001"))
    different = _ask_result(session_id, sequence=2, draft_revision=2)
    with pytest.raises(SessionTurnProjectionConflict) as exc:
        service.apply(P2ATurnApplicationRequest(owner_user_id=owner, result=different, expected_revision=2, idempotency_key="turn-001"))
    assert exc.value.code == "P2A_IDEMPOTENCY_KEY_REUSED"
    assert service.ledger.ledger_entry_count == 1


def test_reused_turn_with_new_key_is_rejected():
    service, owner, session_id = _service()
    result = _ask_result(session_id)
    service.apply(P2ATurnApplicationRequest(owner_user_id=owner, result=result, expected_revision=1, idempotency_key="turn-001"))
    with pytest.raises(SessionTurnProjectionConflict) as exc:
        service.apply(P2ATurnApplicationRequest(owner_user_id=owner, result=result, expected_revision=2, idempotency_key="turn-002"))
    assert exc.value.code == "P2A_TURN_ALREADY_APPLIED"
    assert service.ledger.ledger_entry_count == 1


def test_cross_owner_cannot_read_or_apply_session():
    service, owner, session_id = _service()
    other = uuid4()
    with pytest.raises(SessionTurnProjectionConflict) as exc:
        service.get_session(owner_user_id=other, session_id=session_id)
    assert exc.value.code == "P2A_SESSION_OWNER_MISMATCH"
    with pytest.raises(SessionTurnProjectionConflict) as exc:
        service.apply(P2ATurnApplicationRequest(owner_user_id=other, result=_ask_result(session_id), expected_revision=1, idempotency_key="turn-001"))
    assert exc.value.code == "P2A_SESSION_OWNER_MISMATCH"
    assert service.ledger.ledger_entry_count == 0


def test_rejected_p1h_result_does_not_consume_ledger():
    service, owner, session_id = _service()
    rejected = AgentTurnApplicationResult(
        session_id=session_id,
        turn_id=uuid4(),
        sequence=1,
        draft_revision=1,
        status="rejected",
        state="rejected",
        handoff_status="rejected",
        agent_result_status="rejected",
        error_code="P1F_NOT_AGENT_READY",
    )
    with pytest.raises(SessionTurnProjectionConflict) as exc:
        service.apply(P2ATurnApplicationRequest(owner_user_id=owner, result=rejected, expected_revision=1, idempotency_key="turn-001"))
    assert exc.value.code == "P2A_P1H_RESULT_REJECTED"
    assert service.ledger.ledger_entry_count == 0
    accepted = service.apply(P2ATurnApplicationRequest(owner_user_id=owner, result=_ask_result(session_id), expected_revision=1, idempotency_key="turn-002"))
    assert accepted.result.turn.sequence == 1


def test_invalid_forged_result_is_rejected_before_owner_ledger_write():
    service, owner, session_id = _service()
    forged = AgentTurnApplicationResult.model_construct(
        session_id=session_id,
        turn_id=uuid4(),
        sequence=1,
        draft_revision=1,
        status="accepted",
        state="awaiting_user",
        handoff_status="ready_for_agent",
        agent_result_status="agent_completed",
        candidate=None,
        created_at=_now(),
    )
    with pytest.raises(SessionTurnProjectionConflict) as exc:
        service.apply(P2ATurnApplicationRequest(owner_user_id=owner, result=forged, expected_revision=1, idempotency_key="turn-001"))
    assert exc.value.code == "P2A_P1H_RESULT_REJECTED"
    assert service.ledger.ledger_entry_count == 0


def test_disabled_service_fails_closed_without_mutation():
    service = P2ASessionTurnProjectionService(enabled=False)
    owner = uuid4()
    session_id = uuid4()
    with pytest.raises(SessionTurnProjectionConflict) as exc:
        service.start_session(owner_user_id=owner, session_id=session_id, idempotency_key="start-001")
    assert exc.value.code == "P2A_DISABLED"


def test_result_matches_schema_and_excludes_identity_and_formal_refs():
    service, owner, session_id = _service()
    response = service.apply(P2ATurnApplicationRequest(owner_user_id=owner, result=_ask_result(session_id), expected_revision=1, idempotency_key="turn-001"))
    payload = response.result.model_dump(mode="json", exclude_none=True)
    assert "owner_user_id" not in json.dumps(payload)
    assert "access_token" not in json.dumps(payload)
    assert not any(key in json.dumps(payload) for key in ("approval_id", "event_id", "episode_id", "report_id"))
    schema = json.loads((ROOT / "docs/contracts/session-turn-projection-result.schema.json").read_text())
    registry = Registry()
    for name in ("session-turn-projection-result.schema.json", "agent-turn.schema.json", "body-location.schema.json", "body-signal-event.schema.json"):
        referenced = json.loads((ROOT / "docs/contracts" / name).read_text())
        registry = registry.with_resource(referenced["$id"], Resource.from_contents(referenced))
    Draft202012Validator(schema, registry=registry).validate(payload)


def test_start_same_key_replays_same_session_projection():
    service = P2ASessionTurnProjectionService(enabled=True)
    owner = uuid4()
    session_id = uuid4()
    first = service.start_session(owner_user_id=owner, session_id=session_id, idempotency_key="start-001", now=_now())
    replay = service.start_session(owner_user_id=owner, session_id=session_id, idempotency_key="start-001", now=_now() + timedelta(minutes=1))
    assert replay.replayed is True
    assert replay.session == first.session


def test_expired_session_rejects_projection_without_mutation():
    ledger = P2ASessionTurnLedger(ttl=timedelta(minutes=1))
    service = P2ASessionTurnProjectionService(enabled=True, ledger=ledger)
    owner = uuid4()
    session_id = uuid4()
    service.start_session(owner_user_id=owner, session_id=session_id, idempotency_key="start-001", now=_now())
    with pytest.raises(SessionTurnProjectionConflict) as exc:
        service.apply(
            P2ATurnApplicationRequest(
                owner_user_id=owner,
                result=_ask_result(session_id, created_at=_now() + timedelta(minutes=2)),
                expected_revision=1,
                idempotency_key="turn-001",
                now=_now() + timedelta(minutes=2),
            )
        )
    assert exc.value.code == "P2A_SESSION_EXPIRED"
    assert ledger.ledger_entry_count == 0


def test_safety_offline_and_failed_results_are_terminal_p2a_stops():
    cases = (
        ("safety_action_required", "safety_action_required", "safety_action_required", None),
        ("offline_only", "offline_only", "offline_only", None),
        ("failed", "ready_for_agent", "agent_unavailable", "AGENT_UNAVAILABLE"),
    )
    for state, handoff_status, agent_result_status, error_code in cases:
        service = P2ASessionTurnProjectionService(enabled=True)
        owner = uuid4()
        session_id = uuid4()
        service.start_session(owner_user_id=owner, session_id=session_id, idempotency_key="start-001", now=_now())
        result = AgentTurnApplicationResult(
            session_id=session_id,
            turn_id=uuid4(),
            sequence=1,
            draft_revision=1,
            status="accepted",
            state=state,
            handoff_status=handoff_status,
            agent_result_status=agent_result_status,
            error_code=error_code,
        )
        applied = service.apply(
            P2ATurnApplicationRequest(
                owner_user_id=owner,
                result=result,
                expected_revision=1,
                idempotency_key="turn-001",
                now=_now() + timedelta(seconds=1),
            )
        )
        assert applied.result.session.state == state
        with pytest.raises(SessionTurnProjectionConflict) as exc:
            service.apply(
                P2ATurnApplicationRequest(
                    owner_user_id=owner,
                    result=_ask_result(
                        session_id,
                        sequence=2,
                        draft_revision=2,
                        in_reply_to_turn_id=result.turn_id,
                    ),
                    expected_revision=2,
                    idempotency_key="turn-002",
                )
            )
        assert exc.value.code == "P2A_CONTINUATION_NOT_ALLOWED"
