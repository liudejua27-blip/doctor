from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
import json
from pathlib import Path
from uuid import UUID, uuid4

import pytest
from jsonschema import Draft202012Validator, FormatChecker
from pydantic import ValidationError

from body_companion.application.p2a_session_turn_projection import (
    P2ASessionTurnProjectionService,
    P2ATurnApplicationRequest,
)
from body_companion.application.p2b_confirmation_intent_application import (
    P2BConfirmationIntentApplicationConflict,
    P2BConfirmationIntentApplicationService,
    P2BConfirmationRequest,
)
from body_companion.domain.agent_turn_application import AgentTurnApplicationResult
from body_companion.domain.confirmation import CONFIRMABLE_FIELDS, ConfirmationRequest, PrototypeApprovalStore
from body_companion.domain.events import PrototypeEventStore
from body_companion.domain.policy import digest_for
from body_companion.domain.safety import RuleCatalog, RuleDefinition, SafetyEngine
from body_companion.domain.session_turn_projection import SessionTurnProjectionResult
from body_companion.domain.types import (
    AgentQuestion,
    AskQuestionCandidate,
    ApproximateDateTime,
    AssessmentDraft,
    BodyLocation,
    DraftCandidate,
    EpisodeSelection,
    LocationSource,
    Mapping,
    RuleHit,
    SafetyEvaluation,
    Sensation,
    SourceRef,
    TemporalPattern,
    UserTurnInput,
)


ROOT = Path(__file__).resolve().parents[2]
NOW = datetime(2026, 8, 6, 10, 0, tzinfo=timezone.utc)


def _draft_candidate() -> DraftCandidate:
    marker_id = uuid4()
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
        created_at=NOW,
    )
    event_draft = AssessmentDraft(
        locations=[location],
        sensations=[
            Sensation(
                sensation_id=uuid4(),
                code="aching",
                intensities=[],
                location_marker_ids=[marker_id],
                source=SourceRef(type="user_report", source_id="synthetic-turn"),
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
    return DraftCandidate(
        event_draft=event_draft,
        user_fact_summary="synthetic facts",
        uncertainties=[],
        draft_digest=digest_for(event_draft),
    )


def _draft_result(session_id: UUID, *, turn_id: UUID | None = None) -> AgentTurnApplicationResult:
    return AgentTurnApplicationResult(
        session_id=session_id,
        turn_id=turn_id or uuid4(),
        sequence=1,
        draft_revision=1,
        status="accepted",
        state="awaiting_confirmation",
        handoff_status="ready_for_agent",
        agent_result_status="agent_completed",
        candidate=_draft_candidate(),
        agent_source_ids=["source.synthetic"],
        agent_version="test-agent-1",
        prompt_version="test-prompt-1",
        created_at=NOW,
    )


def _ask_result(session_id: UUID) -> AgentTurnApplicationResult:
    return AgentTurnApplicationResult(
        session_id=session_id,
        turn_id=uuid4(),
        sequence=1,
        draft_revision=1,
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
        created_at=NOW,
    )


def _p2a_draft() -> tuple[P2ASessionTurnProjectionService, UUID, UUID, SessionTurnProjectionResult]:
    p2a = P2ASessionTurnProjectionService(enabled=True)
    owner = uuid4()
    session_id = uuid4()
    p2a.start_session(owner_user_id=owner, session_id=session_id, idempotency_key="start-001", now=NOW)
    result = p2a.apply(
        P2ATurnApplicationRequest(
            owner_user_id=owner,
            result=_draft_result(session_id),
            expected_revision=1,
            idempotency_key="turn-001",
            now=NOW + timedelta(seconds=1),
        )
    ).result
    return p2a, owner, session_id, result


def _confirmation(p2a: SessionTurnProjectionResult, *, mode: str = "create_new") -> ConfirmationRequest:
    selection = (
        EpisodeSelection(mode="create_new", started_on=date(2026, 8, 6))
        if mode == "create_new"
        else EpisodeSelection(mode=mode, episode_id=uuid4(), expected_revision=3)
    )
    assert isinstance(p2a.turn.candidate, DraftCandidate)
    return ConfirmationRequest(
        turn_id=p2a.turn.turn_id,
        expected_revision=p2a.session.revision,
        reviewed_fields=list(CONFIRMABLE_FIELDS),
        draft_digest=p2a.turn.candidate.draft_digest,
        episode_selection=selection,
    )


def _safety(*, tier: str = "R3", supported: bool = True, ordinary: bool | None = None) -> SafetyEvaluation:
    if ordinary is None:
        ordinary = tier == "R3"
    if tier == "R3":
        nonmatching_rule = RuleDefinition(
            rule_id="test.not_matched",
            required_question_id=None,
            evaluate=lambda _ctx: RuleHit(rule_id="test.not_matched", result="not_matched"),
            required_action_code="PROTOTYPE_ACTION",
            content_id="prototype.action.unconfigured",
            content_release_id="prototype.none",
            display_message="synthetic",
        )
        return SafetyEngine(
            RuleCatalog(
                version="rules.p2b.test",
                rules=(nonmatching_rule,),
                available=True,
                scenario_supported=supported,
            )
        ).evaluate(user_text="synthetic")
    return SafetyEvaluation(
        status="complete",
        tier=tier,  # type: ignore[arg-type]
        rule_outcome="triggered",
        triggered_rule_ids=["synthetic.r2"],
        required_question_ids=[],
        rule_set_version="rules.p2b.test",
        all_current_rules_executed=True,
        scenario_support="supported" if supported else "unsupported",
        unresolved_safety=False,
        ordinary_agent_allowed=ordinary,
        answers=[],
        rule_hits=[
            RuleHit(rule_id="synthetic.r2", result="matched", tier=tier, evidence_refs=["synthetic.fact"])
        ],  # type: ignore[arg-type]
        required_action_code=None,
        content_id=None,
        content_release_id=None,
        display_message=None,
        evaluated_at=NOW,
    )


def _raw_input(p2a: SessionTurnProjectionResult) -> UserTurnInput:
    assert isinstance(p2a.turn.candidate, DraftCandidate)
    return UserTurnInput(
        modality="mixed",
        text="synthetic server-captured input",
        locations=[p2a.turn.candidate.event_draft.locations[0]],
        submitted_at=NOW,
    )


def _service(
    p2a: SessionTurnProjectionResult,
    owner: UUID,
    *,
    enabled: bool = True,
    approval_store: PrototypeApprovalStore | None = None,
) -> P2BConfirmationIntentApplicationService:
    service = P2BConfirmationIntentApplicationService(enabled=enabled, approval_store=approval_store)
    service.bind_session(owner_user_id=owner, session_id=p2a.session.session_id)
    return service


def _request(
    p2a: SessionTurnProjectionResult,
    owner: UUID,
    *,
    key: str = "confirm-001",
    safety: SafetyEvaluation | None = None,
    confirmation: ConfirmationRequest | None = None,
    agent_versions: dict[str, str] | None = None,
) -> P2BConfirmationRequest:
    return P2BConfirmationRequest(
        owner_user_id=owner,
        p2a_result=p2a,
        confirmation=confirmation or _confirmation(p2a),
        safety=safety or _safety(),
        server_raw_input=_raw_input(p2a),
        agent_versions=agent_versions or {"agent_version": "test-agent-1", "prompt_version": "test-prompt-1"},
        idempotency_key=key,
        now=NOW + timedelta(seconds=2),
    )


def test_valid_r3_creates_one_pending_intent_and_projection():
    _p2a, owner, _session_id, p2a = _p2a_draft()
    event_store = PrototypeEventStore()
    approval_store = PrototypeApprovalStore(event_writer=event_store)
    service = _service(p2a, owner, approval_store=approval_store)

    response = service.apply(_request(p2a, owner))

    assert response.replayed is False
    assert response.result.approval.status == "pending"
    assert response.result.approval.revision == 1
    assert response.result.approval_projection.state == "awaiting_approval"
    assert response.result.approval_projection.revision == p2a.session.revision + 1
    assert response.result.approval_projection.sequence == p2a.turn.sequence + 1
    assert service.pending_intent_count == 1
    assert event_store.count_events(owner_id=owner) == 0


def test_valid_r2_supported_is_allowed_but_does_not_write_event():
    _p2a, owner, _session_id, p2a = _p2a_draft()
    event_store = PrototypeEventStore()
    service = _service(
        p2a,
        owner,
        approval_store=PrototypeApprovalStore(event_writer=event_store),
    )

    response = service.apply(_request(p2a, owner, safety=_safety(tier="R2")))

    assert response.result.approval.status == "pending"
    assert event_store.count_events(owner_id=owner) == 0


def test_non_draft_p2a_result_is_rejected_without_intent():
    p2a_service = P2ASessionTurnProjectionService(enabled=True)
    owner = uuid4()
    session_id = uuid4()
    p2a_service.start_session(owner_user_id=owner, session_id=session_id, idempotency_key="start-001", now=NOW)
    p2a = p2a_service.apply(
        P2ATurnApplicationRequest(
            owner_user_id=owner,
            result=_ask_result(session_id),
            expected_revision=1,
            idempotency_key="turn-001",
            now=NOW + timedelta(seconds=1),
        )
    ).result
    service = _service(p2a, owner)
    request = P2BConfirmationRequest(
        owner_user_id=owner,
        p2a_result=p2a,
        confirmation=ConfirmationRequest(
            turn_id=p2a.turn.turn_id,
            expected_revision=p2a.session.revision,
            reviewed_fields=list(CONFIRMABLE_FIELDS),
            draft_digest="sha256:" + "0" * 64,
            episode_selection=EpisodeSelection(mode="create_new", started_on=date(2026, 8, 6)),
        ),
        safety=_safety(),
        server_raw_input=UserTurnInput(modality="text", text="synthetic", submitted_at=NOW),
        idempotency_key="confirm-001",
        now=NOW + timedelta(seconds=2),
    )

    with pytest.raises(P2BConfirmationIntentApplicationConflict) as exc:
        service.apply(request)

    assert exc.value.code == "P2B_CONFIRMATION_NOT_ALLOWED"
    assert service.pending_intent_count == 0


def test_confirmation_requires_all_eight_reviewed_fields():
    _p2a, owner, _session_id, p2a = _p2a_draft()
    service = _service(p2a, owner)
    invalid = _confirmation(p2a)
    with pytest.raises(ValidationError):
        ConfirmationRequest(
            turn_id=invalid.turn_id,
            expected_revision=invalid.expected_revision,
            reviewed_fields=list(CONFIRMABLE_FIELDS[:-1]),
            draft_digest=invalid.draft_digest,
            episode_selection=invalid.episode_selection,
        )
    assert service.pending_intent_count == 0


def test_application_revalidates_model_construct_confirmation_before_digest_or_store():
    _p2a, owner, _session_id, p2a = _p2a_draft()
    service = _service(p2a, owner)
    assert isinstance(p2a.turn.candidate, DraftCandidate)
    forged = ConfirmationRequest.model_construct(
        turn_id=p2a.turn.turn_id,
        expected_revision=p2a.session.revision,
        reviewed_fields=["locations"],
        draft_digest=p2a.turn.candidate.draft_digest,
        episode_selection=EpisodeSelection(mode="create_new", started_on=date(2026, 8, 6)),
    )

    with pytest.raises(P2BConfirmationIntentApplicationConflict) as exc:
        service.apply(_request(p2a, owner, confirmation=forged))

    assert exc.value.code == "P2B_CONFIRMATION_REQUEST_REJECTED"
    assert service.pending_intent_count == 0

    expired_request = _request(p2a, owner)
    expired_request = P2BConfirmationRequest(
        owner_user_id=expired_request.owner_user_id,
        p2a_result=expired_request.p2a_result,
        confirmation=expired_request.confirmation,
        safety=expired_request.safety,
        server_raw_input=expired_request.server_raw_input,
        agent_versions=expired_request.agent_versions,
        idempotency_key="expired-001",
        now=p2a.session.expires_at,
    )
    with pytest.raises(P2BConfirmationIntentApplicationConflict) as expired_exc:
        service.apply(expired_request)
    assert expired_exc.value.code == "P2B_SESSION_EXPIRED"
    assert service.pending_intent_count == 0


@pytest.mark.parametrize(
    ("field", "value", "expected"),
    [
        ("turn_id", uuid4(), "P2B_TURN_MISMATCH"),
        ("expected_revision", 99, "P2B_REVISION_MISMATCH"),
        ("draft_digest", "sha256:" + "1" * 64, "P2B_DRAFT_DIGEST_MISMATCH"),
    ],
)
def test_stale_turn_revision_or_digest_is_rejected(field: str, value: object, expected: str):
    _p2a, owner, _session_id, p2a = _p2a_draft()
    service = _service(p2a, owner)
    confirmation = _confirmation(p2a)
    confirmation = confirmation.model_copy(update={field: value})

    with pytest.raises(P2BConfirmationIntentApplicationConflict) as exc:
        service.apply(_request(p2a, owner, confirmation=confirmation))

    assert exc.value.code == expected
    assert service.pending_intent_count == 0


@pytest.mark.parametrize(
    "blocked",
    [
        "R0",
        "incomplete",
        "unavailable",
        "unsupported",
    ],
)
def test_safety_gate_blocks_risky_incomplete_unavailable_or_unsupported(blocked: str):
    _p2a, owner, _session_id, p2a = _p2a_draft()
    service = _service(p2a, owner)
    if blocked == "R0":
        safety = _safety(tier=blocked, ordinary=False)
    elif blocked == "unsupported":
        safety = _safety(supported=False, ordinary=False)
    elif blocked == "incomplete":
        safety = SafetyEvaluation(
            status="incomplete",
            tier="undetermined",
            rule_outcome="unresolved",
            rule_set_version="rules.p2b.test",
            all_current_rules_executed=False,
            scenario_support="supported",
            unresolved_safety=True,
            ordinary_agent_allowed=False,
            required_question_ids=["safety.synthetic"],
            answers=[],
            rule_hits=[],
            evaluated_at=NOW,
        )
    else:
        safety = SafetyEngine(RuleCatalog(version="rules.p2b.none", available=False)).evaluate(user_text="synthetic")

    with pytest.raises(P2BConfirmationIntentApplicationConflict) as exc:
        service.apply(_request(p2a, owner, safety=safety))

    assert exc.value.code == "P2B_SAFETY_GATE_BLOCKED"
    assert service.pending_intent_count == 0


@pytest.mark.parametrize("mode", ["create_new", "join_existing", "reopen_existing"])
def test_episode_selection_is_explicit_and_retained_only_in_server_intent(mode: str):
    _p2a, owner, _session_id, p2a = _p2a_draft()
    store = PrototypeApprovalStore()
    service = _service(p2a, owner, approval_store=store)

    response = service.apply(_request(p2a, owner, confirmation=_confirmation(p2a, mode=mode)))
    stored = store.get(owner_id=owner, approval_id=response.result.approval.approval_id)

    assert stored.episode_selection.mode == mode
    assert "episode_selection" not in response.result.model_dump(mode="json")


def test_wrong_owner_or_unbound_session_fails_closed():
    _p2a, owner, _session_id, p2a = _p2a_draft()
    service = P2BConfirmationIntentApplicationService(enabled=True)

    with pytest.raises(P2BConfirmationIntentApplicationConflict) as exc:
        service.apply(_request(p2a, uuid4()))

    assert exc.value.code == "P2B_SESSION_OWNER_MISMATCH"
    assert service.pending_intent_count == 0
    assert owner != uuid4()


def test_forged_cross_session_p2a_result_is_rejected_without_health_content():
    _p2a, owner, _session_id, p2a = _p2a_draft()
    service = _service(p2a, owner)
    forged = p2a.model_copy(
        update={"turn": p2a.turn.model_copy(update={"session_id": uuid4()})}
    )

    with pytest.raises(P2BConfirmationIntentApplicationConflict) as exc:
        service.apply(_request(forged, owner))

    assert exc.value.code == "P2B_P2A_RESULT_REJECTED"
    assert "synthetic" not in str(exc.value).casefold()
    assert service.pending_intent_count == 0


def test_same_key_same_request_replays_identical_result_without_new_intent():
    _p2a, owner, _session_id, p2a = _p2a_draft()
    service = _service(p2a, owner)
    request = _request(p2a, owner)

    first = service.apply(request)
    replay = service.apply(request)

    assert replay.replayed is True
    assert replay.result == first.result
    assert service.pending_intent_count == 1


def test_same_key_with_changed_payload_is_rejected_without_second_intent():
    _p2a, owner, _session_id, p2a = _p2a_draft()
    service = _service(p2a, owner)
    service.apply(_request(p2a, owner))
    changed = _request(p2a, owner, agent_versions={"agent_version": "different"})

    with pytest.raises(P2BConfirmationIntentApplicationConflict) as exc:
        service.apply(changed)

    assert exc.value.code == "P2B_IDEMPOTENCY_KEY_REUSED"
    assert service.pending_intent_count == 1


def test_same_session_turn_with_different_key_is_rejected():
    _p2a, owner, _session_id, p2a = _p2a_draft()
    service = _service(p2a, owner)
    service.apply(_request(p2a, owner, key="confirm-001"))

    with pytest.raises(P2BConfirmationIntentApplicationConflict) as exc:
        service.apply(_request(p2a, owner, key="confirm-002"))

    assert exc.value.code == "P2B_CONFIRMATION_ALREADY_CREATED"
    assert service.pending_intent_count == 1


def test_result_matches_contract_and_excludes_identity_raw_candidate_and_safety_answers():
    _p2a, owner, _session_id, p2a = _p2a_draft()
    service = _service(p2a, owner)
    response = service.apply(_request(p2a, owner))
    payload = response.result.model_dump(mode="json", exclude_none=True)
    schema = json.loads((ROOT / "docs/contracts/confirmation-intent-application-result.schema.json").read_text())
    Draft202012Validator(schema, format_checker=FormatChecker()).validate(payload)
    serialized = json.dumps(payload, ensure_ascii=False)

    for forbidden in (
        "owner_user_id",
        "user_id",
        "server_raw_input",
        "synthetic server-captured input",
        "event_draft",
        "safety",
        "answers",
        "episode_id",
        "event_id",
        "report_id",
    ):
        assert forbidden not in serialized
    assert payload["approval_projection"]["source_turn_id"] == str(p2a.turn.turn_id)


def test_disabled_or_store_failure_has_fixed_error_and_no_projection():
    _p2a, owner, _session_id, p2a = _p2a_draft()
    disabled = _service(p2a, owner, enabled=False)
    with pytest.raises(P2BConfirmationIntentApplicationConflict) as disabled_exc:
        disabled.apply(_request(p2a, owner))
    assert disabled_exc.value.code == "P2B_DISABLED"

    class FailingStore(PrototypeApprovalStore):
        def create_intent(self, **_kwargs):  # type: ignore[no-untyped-def]
            raise RuntimeError("synthetic store failure")

    failed = _service(p2a, owner, approval_store=FailingStore())
    with pytest.raises(P2BConfirmationIntentApplicationConflict) as failed_exc:
        failed.apply(_request(p2a, owner))
    assert failed_exc.value.code == "P2B_APPLICATION_FAILED"
    assert failed.pending_intent_count == 0


def test_invalid_idempotency_key_is_rejected_before_store():
    _p2a, owner, _session_id, p2a = _p2a_draft()
    service = _service(p2a, owner)

    with pytest.raises(P2BConfirmationIntentApplicationConflict) as exc:
        service.apply(_request(p2a, owner, key="short"))

    assert exc.value.code == "P2B_INVALID_IDEMPOTENCY_KEY"
    assert service.pending_intent_count == 0

    invalid_time = _request(p2a, owner, key="confirm-time")
    invalid_time = P2BConfirmationRequest(
        owner_user_id=invalid_time.owner_user_id,
        p2a_result=invalid_time.p2a_result,
        confirmation=invalid_time.confirmation,
        safety=invalid_time.safety,
        server_raw_input=invalid_time.server_raw_input,
        agent_versions=invalid_time.agent_versions,
        idempotency_key=invalid_time.idempotency_key,
        now="not-a-time",  # type: ignore[arg-type]
    )
    with pytest.raises(P2BConfirmationIntentApplicationConflict) as time_exc:
        service.apply(invalid_time)
    assert time_exc.value.code == "P2B_INVALID_TIMESTAMP"
    assert service.pending_intent_count == 0
