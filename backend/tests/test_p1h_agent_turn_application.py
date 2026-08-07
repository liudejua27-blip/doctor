from __future__ import annotations

import json
from pathlib import Path
from uuid import UUID, uuid4

import pytest
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

from body_companion.agents.assessment_agent import AgentExecutionError
from body_companion.application.p1h_agent_turn_application import (
    AgentTurnApplicationRequest,
    AgentTurnApplicationService,
)
from body_companion.domain.types import DraftCandidate
from body_companion.domain.policy import digest_for

from test_ios_signal_intake import SESSION_ID, make_payload
from test_ios_signal_intake_application import RecordingSafetyEngine, evaluation, request
from test_p1g_agent_handoff import RecordingRunner, ask_candidate
from body_companion.application.ios_signal_intake_service import IOSSignalIntakeApplicationService


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_USER_ID = UUID("c8b3a11a-9d73-4ba2-93aa-3f5f4c9fc201")


def ready_handoff(*, revision: int = 2, raw_user_text: str | None = "secret raw turn text"):
    return IOSSignalIntakeApplicationService(RecordingSafetyEngine(evaluation())).handoff(
        request(draft=make_payload(revision=revision, raw_user_text=raw_user_text), engine_revision=revision)
    )


def non_ready_handoff(kind: str):
    if kind == "safety":
        result = evaluation(tier="R0", ordinary=False)
    elif kind == "offline":
        result = evaluation(unavailable=True)
    else:
        return IOSSignalIntakeApplicationService(RecordingSafetyEngine(evaluation())).handoff(
            request(draft=make_payload(phase="choosing_location"))
        )
    return IOSSignalIntakeApplicationService(RecordingSafetyEngine(result)).handoff(request())


def turn_request(
    *,
    service: AgentTurnApplicationService,
    handoff=None,
    user_id: UUID | None = None,
    turn_id: UUID | None = None,
    sequence: int = 1,
    revision: int = 2,
    predecessor: UUID | None = None,
    key: str = "turn-key-1",
):
    return service.apply(
        AgentTurnApplicationRequest(
            session_id=SESSION_ID,
            turn_id=turn_id or uuid4(),
            sequence=sequence,
            draft_revision=revision,
            in_reply_to_turn_id=predecessor,
            handoff=handoff or ready_handoff(revision=revision),
            authenticated_user_id=user_id or DEFAULT_USER_ID,
            idempotency_key=key,
        )
    )


def enabled_service(runner: RecordingRunner | None = None) -> AgentTurnApplicationService:
    return AgentTurnApplicationService(runner or RecordingRunner(), enabled=True)


def test_first_ready_turn_maps_ask_candidate_and_sequence():
    runner = RecordingRunner()
    response = turn_request(service=enabled_service(runner), key="turn-key-01")

    assert response.replayed is False
    assert response.result.status == "accepted"
    assert response.result.state == "awaiting_user"
    assert response.result.agent_result_status == "agent_completed"
    assert response.result.sequence == 1
    assert response.result.in_reply_to_turn_id is None
    assert len(runner.calls) == 1


@pytest.mark.parametrize("kind", ["safety", "offline", "rejected"])
def test_non_ready_handoff_never_calls_runner(kind: str):
    runner = RecordingRunner()
    response = turn_request(
        service=enabled_service(runner),
        handoff=non_ready_handoff(kind),
        key=f"non-ready-{kind}",
    )

    assert len(runner.calls) == 0
    assert response.result.candidate is None
    if kind == "safety":
        assert response.result.state == "safety_action_required"
    elif kind == "offline":
        assert response.result.state == "offline_only"
    else:
        assert response.result.status == "rejected"
        assert response.result.state == "rejected"


def test_draft_candidate_stays_unconfirmed_and_enters_confirmation_state():
    handoff = ready_handoff()
    assert handoff.assessment_draft is not None
    candidate = DraftCandidate(
        event_draft=handoff.assessment_draft,
        user_fact_summary="synthetic candidate",
        uncertainties=["trend"],
        draft_digest=digest_for(handoff.assessment_draft),
    )
    response = turn_request(
        service=enabled_service(RecordingRunner(candidate=candidate)), handoff=handoff, key="draft-key-01"
    )

    assert response.result.state == "awaiting_confirmation"
    assert response.result.candidate is not None
    assert response.result.candidate.kind == "draft_ready"
    assert response.result.model_dump(mode="json").keys().isdisjoint(
        {"user_id", "event_id", "approval_id", "episode_id", "raw_user_text"}
    )


def test_continuation_requires_new_p1f_handoff_and_monotonic_revision():
    runner = RecordingRunner()
    service = enabled_service(runner)
    first = turn_request(service=service, key="continue-key-01")
    second = turn_request(
        service=service,
        handoff=ready_handoff(revision=3),
        sequence=2,
        revision=3,
        predecessor=first.result.turn_id,
        key="continue-key-02",
    )

    assert second.result.sequence == 2
    assert second.result.in_reply_to_turn_id == first.result.turn_id
    assert len(runner.calls) == 2


def test_wrong_predecessor_and_stale_revision_are_zero_side_effect():
    runner = RecordingRunner()
    service = enabled_service(runner)
    first = turn_request(service=service, key="cas-key-01")
    wrong_predecessor = turn_request(
        service=service,
        handoff=ready_handoff(revision=3),
        sequence=2,
        revision=3,
        predecessor=uuid4(),
        key="cas-key-02",
    )
    stale_revision = turn_request(
        service=service,
        handoff=ready_handoff(revision=2),
        sequence=2,
        revision=2,
        predecessor=first.result.turn_id,
        key="cas-key-03",
    )

    assert wrong_predecessor.result.error_code == "P1H_PREDECESSOR_MISMATCH"
    assert stale_revision.result.error_code == "P1H_REVISION_MISMATCH"
    assert len(runner.calls) == 1
    assert service.ledger_entry_count == 1


def test_same_key_same_request_replays_without_second_agent_call():
    runner = RecordingRunner()
    service = enabled_service(runner)
    handoff = ready_handoff()
    turn_id = uuid4()
    first = turn_request(service=service, handoff=handoff, turn_id=turn_id, key="replay-key-01")
    replay = turn_request(service=service, handoff=handoff, turn_id=turn_id, key="replay-key-01")

    assert replay.replayed is True
    assert replay.result == first.result
    assert len(runner.calls) == 1


def test_same_key_different_request_is_rejected_without_agent_call():
    runner = RecordingRunner()
    service = enabled_service(runner)
    first = turn_request(service=service, key="reuse-key-01")
    conflict = turn_request(
        service=service,
        handoff=ready_handoff(revision=3),
        turn_id=uuid4(),
        sequence=2,
        revision=3,
        predecessor=first.result.turn_id,
        key="reuse-key-01",
    )

    assert conflict.result.error_code == "P1H_IDEMPOTENCY_KEY_REUSED"
    assert len(runner.calls) == 1
    assert service.ledger_entry_count == 1


def test_different_key_cannot_reuse_turn_and_draft_state_cannot_continue():
    runner = RecordingRunner()
    service = enabled_service(runner)
    turn_id = uuid4()
    first = turn_request(service=service, turn_id=turn_id, key="turn-reuse-01")
    reused = turn_request(service=service, turn_id=turn_id, key="turn-reuse-02")
    assert reused.result.error_code == "P1H_TURN_ALREADY_APPLIED"

    handoff = ready_handoff()
    assert handoff.assessment_draft is not None
    draft_runner = RecordingRunner(
        candidate=DraftCandidate(
            event_draft=handoff.assessment_draft,
            user_fact_summary="synthetic draft",
            draft_digest=digest_for(handoff.assessment_draft),
        )
    )
    draft_service = enabled_service(draft_runner)
    draft = turn_request(service=draft_service, key="draft-cont-01")
    blocked = turn_request(
        service=draft_service,
        handoff=ready_handoff(revision=3),
        sequence=2,
        revision=3,
        predecessor=draft.result.turn_id,
        key="draft-cont-02",
    )
    assert blocked.result.error_code == "P1H_CONTINUATION_NOT_ALLOWED"
    assert len(draft_runner.calls) == 1


def test_runner_failure_is_fixed_and_exception_text_does_not_escape():
    secret = "provider-secret-health-exception"
    response = turn_request(
        service=enabled_service(RecordingRunner(error=AgentExecutionError(secret))),
        key="failure-key-01",
    )
    serialized = response.result.model_dump_json()

    assert response.result.state == "failed"
    assert response.result.error_code == "AGENT_EXECUTION_UNAVAILABLE"
    assert secret not in serialized
    assert "RuntimeError" not in serialized


def test_cross_user_session_is_rejected_before_agent():
    runner = RecordingRunner()
    service = enabled_service(runner)
    owner = uuid4()
    first = turn_request(service=service, user_id=owner, key="owner-key-01")
    other = turn_request(service=service, user_id=uuid4(), key="owner-key-02")

    assert first.result.status == "accepted"
    assert other.result.error_code == "P1H_SESSION_OWNER_MISMATCH"
    assert len(runner.calls) == 1


def test_disabled_p1h_keeps_ready_handoff_as_fixed_failure():
    runner = RecordingRunner()
    service = AgentTurnApplicationService(runner)
    response = turn_request(service=service, key="disabled-key-01")

    assert response.result.status == "accepted"
    assert response.result.state == "failed"
    assert response.result.error_code == "P1H_DISABLED"
    assert runner.calls == []


def test_malformed_ready_handoff_fails_closed_before_runner():
    handoff = ready_handoff()
    forged = handoff.model_copy(update={"assessment_draft": None})
    runner = RecordingRunner()
    service = enabled_service(runner)
    response = turn_request(service=service, handoff=forged, key="forged-key-01")

    assert response.result.status == "rejected"
    assert response.result.error_code == "P1F_NOT_AGENT_READY"
    assert runner.calls == []
    assert service.ledger_entry_count == 0


def test_result_has_no_identity_prompt_or_formal_resource_fields():
    response = turn_request(service=enabled_service(), key="privacy-key-01")
    payload = response.result.model_dump(mode="json", exclude_none=True)
    serialized = json.dumps(payload, ensure_ascii=False)

    for forbidden in (
        "user_id",
        "raw_user_text",
        "raw_text",
        "access_token",
        "provider_key",
        "event_id",
        "approval_id",
        "episode_id",
        "report_id",
        "messages",
    ):
        assert forbidden not in payload
        assert forbidden not in serialized


def test_result_schema_accepts_candidate_and_fixed_failure_instances():
    schema_path = ROOT / "docs/contracts/agent-turn-application-result.schema.json"
    schema = json.loads(schema_path.read_text())
    registry = Registry()
    for name in ("agent-turn.schema.json", "body-location.schema.json", "body-signal-event.schema.json"):
        referenced = json.loads((ROOT / "docs/contracts" / name).read_text())
        registry = registry.with_resource(referenced["$id"], Resource.from_contents(referenced))
    validator = Draft202012Validator(schema, registry=registry)

    ready = turn_request(service=enabled_service(), key="schema-key-01").result
    failure = turn_request(
        service=enabled_service(),
        handoff=non_ready_handoff("offline"),
        key="schema-key-02",
    ).result
    rejected = turn_request(
        service=enabled_service(),
        handoff=non_ready_handoff("rejected"),
        key="schema-key-03",
    ).result

    for result in (ready, failure, rejected):
        validator.validate(result.model_dump(mode="json", exclude_none=True))

    with pytest.raises(Exception):
        validator.validate({**ready.model_dump(mode="json", exclude_none=True), "user_id": str(uuid4())})


def test_no_formal_resource_store_is_touched():
    service = enabled_service()
    handoff = ready_handoff()
    first = turn_request(service=service, handoff=handoff, key="formal-key-01")
    replay = turn_request(
        service=service,
        handoff=handoff,
        turn_id=first.result.turn_id,
        key="formal-key-01",
    )

    assert service.ledger_entry_count == 1
    assert first.result.model_dump(mode="json").keys().isdisjoint(
        {"event_id", "approval_id", "episode_id", "report_id", "profile_id"}
    )
    assert replay.replayed is True
