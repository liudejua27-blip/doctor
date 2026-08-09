from __future__ import annotations

from datetime import datetime, timezone
from uuid import UUID, uuid4

import pytest

from body_companion.application.ios_signal_intake_service import (
    IOSSignalIntakeApplicationRequest,
    IOSSignalIntakeApplicationService,
)
from body_companion.domain.ios_signal_intake import IOSClientSafetyState
from body_companion.domain.safety import RuleCatalog, SafetyEngine
from body_companion.domain.types import SafetyAnswer, SafetyEvaluation

from test_ios_signal_intake import SESSION_ID, make_payload


FIXED_TIME = datetime(2026, 1, 2, 3, 4, 5, tzinfo=timezone.utc)


def evaluation(
    *,
    status: str = "complete",
    tier: str = "R3",
    rule_outcome: str | None = None,
    ordinary: bool = True,
    supported: bool = True,
    unavailable: bool = False,
) -> SafetyEvaluation:
    if unavailable:
        status = "unavailable"
        tier = "undetermined"
        rule_outcome = "unavailable"
        ordinary = False
        required_questions: list[str] = []
        all_executed = False
        unresolved = True
        triggered: list[str] = []
    elif status == "incomplete":
        tier = "undetermined"
        rule_outcome = "unresolved"
        ordinary = False
        required_questions = ["safety.review"]
        all_executed = False
        unresolved = True
        triggered = []
    elif rule_outcome == "no_rule_triggered" or (rule_outcome is None and tier == "R3"):
        tier = "R3"
        rule_outcome = "no_rule_triggered"
        required_questions = []
        all_executed = True
        unresolved = False
        triggered = []
    else:
        rule_outcome = rule_outcome or "triggered"
        required_questions = []
        all_executed = True
        unresolved = False
        triggered = ["test.rule"] if tier in {"R0", "R1", "R2"} else []
    return SafetyEvaluation(
        status=status,  # type: ignore[arg-type]
        tier=tier,  # type: ignore[arg-type]
        rule_outcome=rule_outcome,  # type: ignore[arg-type]
        triggered_rule_ids=triggered,
        required_question_ids=required_questions,
        rule_set_version="rules.p1f.test",
        all_current_rules_executed=all_executed,
        scenario_support="supported" if supported else "unsupported",
        unresolved_safety=unresolved,
        ordinary_agent_allowed=ordinary,
        answers=[],
        rule_hits=[],
        required_action_code="TEST_ACTION" if triggered else None,
        content_id="test.content" if triggered else None,
        content_release_id="test.release" if triggered else None,
        evaluated_at=FIXED_TIME,
    )


class RecordingSafetyEngine(SafetyEngine):
    def __init__(self, result: SafetyEvaluation) -> None:
        super().__init__(RuleCatalog(version="rules.p1f.test", available=True))
        self.result = result
        self.calls: list[dict[str, object]] = []

    def evaluate(self, **kwargs: object) -> SafetyEvaluation:  # type: ignore[override]
        self.calls.append(kwargs)
        return self.result


class RaisingSafetyEngine(SafetyEngine):
    def __init__(self) -> None:
        super().__init__(RuleCatalog(version="rules.p1f.raise", available=True))

    def evaluate(self, **kwargs: object) -> SafetyEvaluation:  # type: ignore[override]
        raise RuntimeError("secret provider details must not escape")


def request(*, draft=None, engine_revision: int = 2, answers: tuple[SafetyAnswer, ...] = ()):
    return IOSSignalIntakeApplicationRequest(
        draft=draft or make_payload(revision=engine_revision),
        expected_session_id=SESSION_ID,
        expected_draft_revision=engine_revision,
        safety_answers=answers,
    )


def test_valid_draft_runs_safety_once_and_returns_ready_without_agent():
    engine = RecordingSafetyEngine(evaluation())
    result = IOSSignalIntakeApplicationService(engine).handoff(request())

    assert result.status == "ready_for_agent"
    assert result.assessment_draft is not None
    assert result.server_safety is not None
    assert len(engine.calls) == 1
    assert engine.calls[0]["user_text"] == "合成测试原话，不应出现在适配结果。"
    assert engine.calls[0]["source_fact_ids"] == (f"ios-signal-intake:{SESSION_ID}:draft:2",)


def test_structural_session_or_revision_failure_does_not_run_safety():
    engine = RecordingSafetyEngine(evaluation())
    stale_session = IOSSignalIntakeApplicationRequest(
        draft=make_payload(revision=2), expected_session_id=uuid4(), expected_draft_revision=2
    )
    stale_revision = IOSSignalIntakeApplicationRequest(
        draft=make_payload(revision=2), expected_session_id=SESSION_ID, expected_draft_revision=3
    )

    first = IOSSignalIntakeApplicationService(engine).handoff(stale_session)
    second = IOSSignalIntakeApplicationService(engine).handoff(stale_revision)

    assert (first.status, first.error_code) == ("rejected", "INTAKE_SESSION_MISMATCH")
    assert (second.status, second.error_code) == ("rejected", "INTAKE_REVISION_MISMATCH")
    assert engine.calls == []


@pytest.mark.parametrize(
    ("result", "expected"),
    [
        (evaluation(tier="R0", ordinary=False), "safety_action_required"),
        (evaluation(tier="R1", ordinary=False), "safety_action_required"),
        (evaluation(status="incomplete"), "safety_action_required"),
        (evaluation(tier="R2", ordinary=False), "safety_action_required"),
        (evaluation(supported=False, tier="R3", rule_outcome="no_rule_triggered", ordinary=False), "safety_action_required"),
    ],
)
def test_non_ready_server_safety_never_carries_agent_draft(result: SafetyEvaluation, expected: str):
    service = IOSSignalIntakeApplicationService(RecordingSafetyEngine(result))
    handoff = service.handoff(request())
    assert handoff.status == expected
    assert handoff.assessment_draft is None
    assert handoff.server_safety is not None


def test_unavailable_safety_returns_offline_and_fixed_error():
    result = IOSSignalIntakeApplicationService(RecordingSafetyEngine(evaluation(unavailable=True))).handoff(request())
    assert result.status == "offline_only"
    assert result.error_code == "SAFETY_PRECHECK_UNAVAILABLE"
    assert result.assessment_draft is None
    assert result.server_safety is not None
    assert result.server_safety.rule_outcome == "unavailable"


def test_safety_exception_fails_closed_without_exception_text():
    secret = "secret provider details must not escape"
    payload = make_payload(raw_user_text=secret)
    result = IOSSignalIntakeApplicationService(RaisingSafetyEngine()).handoff(request(draft=payload))
    serialized = result.model_dump_json()
    assert result.status == "offline_only"
    assert result.error_code == "SAFETY_PRECHECK_UNAVAILABLE"
    assert secret not in serialized
    assert "RuntimeError" not in serialized


def test_client_safety_claim_never_overrides_server_result():
    payload = make_payload(
        client_safety=IOSClientSafetyState(
            status="no_rule_triggered",
            ordinary_agent_allowed=True,
            display_message="当前回答未触发已审核规则（不等于安全）",
        )
    )
    result = IOSSignalIntakeApplicationService(
        RecordingSafetyEngine(evaluation(tier="R0", ordinary=False))
    ).handoff(request(draft=payload))
    assert result.status == "safety_action_required"
    assert result.server_safety is not None
    assert result.server_safety.tier == "R0"


def test_raw_text_answers_identity_and_formal_resource_refs_are_absent():
    secret = "secret-health-answer-should-not-escape"
    payload = make_payload(raw_user_text=secret)
    answer = SafetyAnswer(
        question_id="safety.review",
        answer_type="boolean",
        answer_state="answered",
        boolean_value=False,
        raw_text=secret,
        answered_at=FIXED_TIME,
    )
    result = IOSSignalIntakeApplicationService(RecordingSafetyEngine(evaluation())).handoff(
        request(draft=payload, answers=(answer,))
    )
    serialized = result.model_dump_json()
    assert secret not in serialized
    for forbidden in ("user_id", "access_token", "provider_key", "event_id", "approval_id", "episode_id", "report_id"):
        assert forbidden not in serialized
    assert result.server_safety is not None
    assert "answers" not in result.server_safety.model_dump()


def test_profile_or_system_source_is_rejected_before_safety():
    payload = make_payload()
    payload.facts.sensations[0].source = "profile"  # type: ignore[assignment]
    payload.facts.sensations[0].status = "candidate"
    engine = RecordingSafetyEngine(evaluation())
    result = IOSSignalIntakeApplicationService(engine).handoff(request(draft=payload))
    assert result.status == "rejected"
    assert result.error_code == "INTAKE_PROFILE_SOURCE_REF_REQUIRED"
    assert engine.calls == []


def test_repeated_same_revision_is_deterministic_and_has_no_formal_side_effect():
    engine = RecordingSafetyEngine(evaluation())
    service = IOSSignalIntakeApplicationService(engine)
    payload = make_payload()
    first = service.handoff(request(draft=payload))
    second = service.handoff(request(draft=payload))
    assert first.model_dump(mode="json") == second.model_dump(mode="json")
    assert first.assessment_draft is not None
    assert first.assessment_draft.locations[0].marker_id == payload.locations[0].marker_id


def test_no_rule_triggered_is_ready_without_safety_claim():
    result = IOSSignalIntakeApplicationService(
        RecordingSafetyEngine(evaluation(tier="R3", rule_outcome="no_rule_triggered"))
    ).handoff(request())
    assert result.status == "ready_for_agent"
    assert result.server_safety is not None
    assert result.server_safety.rule_outcome == "no_rule_triggered"
    assert "安全" not in result.model_dump_json()


def test_handoff_schema_rejects_non_ready_draft_and_ready_without_gate():
    from body_companion.domain.ios_signal_intake import IOSSignalIntakeApplicationHandoff

    with pytest.raises(ValueError):
        IOSSignalIntakeApplicationHandoff(
            session_id=SESSION_ID,
            draft_revision=2,
            status="safety_action_required",
            client_safety_status="r0",
            assessment_draft=make_payload().facts,  # type: ignore[arg-type]
        )

    with pytest.raises(ValueError):
        IOSSignalIntakeApplicationHandoff(
            session_id=SESSION_ID,
            draft_revision=2,
            status="ready_for_agent",
            client_safety_status="r2",
        )
