from __future__ import annotations

from datetime import datetime, timezone
from uuid import UUID, uuid4

import pytest
from pydantic_ai.models.test import TestModel

from body_companion.agents.assessment_agent import AgentExecutionError, AssessmentAgentRunner
from body_companion.application.p1g_agent_handoff import (
    P1GAgentHandoffRequest,
    P1GAgentHandoffService,
    StructuredAgentPromptBuilder,
)
from body_companion.domain.agent_context import (
    AgentConsentGrant,
    AgentReadContext,
    AgentSourceRef,
    BodyProfileContext,
)
from body_companion.domain.agent_handoff import P1GAgentHandoffResult
from body_companion.domain.ios_signal_intake import IOSClientSafetyState
from body_companion.domain.policy import digest_for
from body_companion.domain.types import AgentQuestion, AskQuestionCandidate, DraftCandidate

from test_ios_signal_intake import SESSION_ID, make_payload
from test_ios_signal_intake_application import RecordingSafetyEngine, evaluation, request
from body_companion.application.ios_signal_intake_service import IOSSignalIntakeApplicationService


def ready_handoff(*, raw_user_text: str | None = "synthetic raw secret"):
    return IOSSignalIntakeApplicationService(RecordingSafetyEngine(evaluation())).handoff(
        request(draft=make_payload(raw_user_text=raw_user_text))
    )


def ask_candidate(summary: str = "synthetic") -> AskQuestionCandidate:
    return AskQuestionCandidate(
        questions=(
            AgentQuestion(
                question_id="sensation.type",
                category="sensation",
                prompt="你更接近哪一种感觉？",
                answer_type="free_text",
                required=True,
            ),
        ),
        context_summary=summary,
    )


class RecordingRunner:
    def __init__(self, candidate=None, error: Exception | None = None) -> None:
        self.candidate = candidate or ask_candidate()
        self.error = error
        self.calls: list[tuple[str, object]] = []

    def run_sync(self, prompt: str, *, deps: object):
        self.calls.append((prompt, deps))
        if self.error is not None:
            raise self.error
        return self.candidate


def profile_context(user_id: UUID) -> AgentReadContext:
    return AgentReadContext(
        authenticated_user_id=user_id,
        purpose="assessment",
        grants=(
            AgentConsentGrant(
                subject_user_id=user_id,
                scope="body_profile_read",
                consent_receipt_id=uuid4(),
                purpose="assessment",
                granted_at=datetime.now(timezone.utc),
            ),
        ),
        profile=BodyProfileContext(
            owner_user_id=user_id,
            profile_revision=3,
            activity_types=("running",),
            work_pattern="desk",
            sources=(
                AgentSourceRef(
                    source_id="profile-revision-3",
                    source_type="body_profile",
                    revision=3,
                    field_keys=("activity_types", "work_pattern"),
                ),
            ),
        ),
        redaction_policy_version="p3-redaction-1",
    )


def enabled_service(runner) -> P1GAgentHandoffService:
    return P1GAgentHandoffService(runner, enabled=True)


def test_ready_handoff_runs_typed_agent_and_returns_unconfirmed_candidate():
    runner = RecordingRunner()
    result = enabled_service(runner).run(
        P1GAgentHandoffRequest(handoff=ready_handoff(), authenticated_user_id=uuid4())
    )

    assert result.status == "agent_completed"
    assert result.handoff_status == "ready_for_agent"
    assert result.candidate is not None
    assert result.candidate.kind == "ask_question"
    assert result.agent_version == "p1g-agent-1"
    assert result.prompt_version == "p1g-prompt-1"
    assert len(runner.calls) == 1


def test_feature_flag_is_disabled_by_default():
    runner = RecordingRunner()
    result = P1GAgentHandoffService(runner).run(
        P1GAgentHandoffRequest(handoff=ready_handoff(), authenticated_user_id=uuid4())
    )
    assert (result.status, result.error_code) == ("agent_unavailable", "P1G_DISABLED")
    assert runner.calls == []


@pytest.mark.parametrize(
    ("handoff", "expected_status"),
    [
        (IOSSignalIntakeApplicationService(RecordingSafetyEngine(evaluation(tier="R0", ordinary=False))).handoff(request()), "safety_action_required"),
        (IOSSignalIntakeApplicationService(RecordingSafetyEngine(evaluation(unavailable=True))).handoff(request()), "offline_only"),
        (
            IOSSignalIntakeApplicationService(RecordingSafetyEngine(evaluation())).handoff(
                request(draft=make_payload(revision=2), engine_revision=3)
            ),
            "rejected",
        ),
    ],
)
def test_non_ready_p1f_handoff_never_calls_agent(handoff, expected_status: str):
    runner = RecordingRunner()
    result = enabled_service(runner).run(
        P1GAgentHandoffRequest(handoff=handoff, authenticated_user_id=uuid4())
    )
    assert result.status == expected_status
    assert result.candidate is None
    assert runner.calls == []


def test_forged_or_incomplete_ready_envelope_fails_closed_before_agent():
    forged = ready_handoff().model_copy(update={"assessment_draft": None})
    # model_copy(update=...) intentionally bypasses assignment validators; the
    # P1G boundary must revalidate it before treating it as model permission.
    runner = RecordingRunner()
    result = enabled_service(runner).run(
        P1GAgentHandoffRequest(handoff=forged, authenticated_user_id=uuid4())
    )
    assert (result.status, result.handoff_status, result.error_code) == (
        "rejected",
        "rejected",
        "P1F_NOT_AGENT_READY",
    )
    assert runner.calls == []


def test_client_safety_spoof_cannot_override_server_ready_gate():
    payload = make_payload(
        client_safety=IOSClientSafetyState(
            status="r0",
            ordinary_agent_allowed=False,
            display_message="client-only status; server must decide",
        )
    )
    handoff = IOSSignalIntakeApplicationService(RecordingSafetyEngine(evaluation())).handoff(
        request(draft=payload)
    )
    runner = RecordingRunner()
    result = enabled_service(runner).run(
        P1GAgentHandoffRequest(handoff=handoff, authenticated_user_id=uuid4())
    )
    assert result.status == "agent_completed"
    assert len(runner.calls) == 1


def test_structured_prompt_excludes_p1d_raw_text_and_forbidden_transport_keys():
    secret = "SECRET-RAW-HEALTH-TEXT"
    handoff = ready_handoff(raw_user_text=secret)
    runner = RecordingRunner()
    enabled_service(runner).run(
        P1GAgentHandoffRequest(handoff=handoff, authenticated_user_id=uuid4())
    )
    prompt = runner.calls[0][0]
    assert secret not in prompt
    for forbidden in ("raw_user_text", "user_id", "access_token", "provider_key", "event_id"):
        assert forbidden not in prompt
    assert "BODY_SIGNAL_DATA" in prompt


def test_pydantic_ai_test_model_runs_only_after_p1f_ready():
    runner = AssessmentAgentRunner(
        TestModel(
            call_tools=[],
            custom_output_args=ask_candidate().model_dump(mode="json"),
        )
    )
    result = enabled_service(runner).run(
        P1GAgentHandoffRequest(handoff=ready_handoff(), authenticated_user_id=uuid4())
    )
    assert result.status == "agent_completed"
    assert result.candidate is not None
    assert result.candidate.kind == "ask_question"


def test_policy_rejects_forbidden_agent_text_without_returning_candidate():
    runner = RecordingRunner(candidate=ask_candidate("诊断：这不是允许的输出"))
    result = enabled_service(runner).run(
        P1GAgentHandoffRequest(handoff=ready_handoff(), authenticated_user_id=uuid4())
    )
    assert (result.status, result.error_code) == ("agent_output_rejected", "AGENT_OUTPUT_INVALID")
    assert result.candidate is None


def test_policy_rejects_new_marker_and_bad_digest():
    handoff = ready_handoff()
    draft = handoff.assessment_draft
    assert draft is not None
    new_marker = uuid4()
    draft_payload = draft.model_dump(mode="json")
    draft_payload["locations"][0]["marker_id"] = str(new_marker)
    draft_payload["sensations"][0]["location_marker_ids"] = [str(new_marker)]
    new_draft = type(draft).model_validate(draft_payload)
    candidate = DraftCandidate(
        event_draft=new_draft,
        user_fact_summary="synthetic",
        uncertainties=[],
        draft_digest=digest_for(new_draft),
    )
    result = enabled_service(RecordingRunner(candidate=candidate)).run(
        P1GAgentHandoffRequest(handoff=handoff, authenticated_user_id=uuid4())
    )
    assert (result.status, result.error_code) == ("agent_output_rejected", "AGENT_OUTPUT_INVALID")

    bad = DraftCandidate(
        event_draft=draft,
        user_fact_summary="synthetic",
        uncertainties=[],
        draft_digest="sha256:" + "0" * 64,
    )
    bad_result = enabled_service(RecordingRunner(candidate=bad)).run(
        P1GAgentHandoffRequest(handoff=handoff, authenticated_user_id=uuid4())
    )
    assert (bad_result.status, bad_result.error_code) == ("agent_output_rejected", "AGENT_OUTPUT_INVALID")


def test_authorized_profile_tool_returns_only_source_audit():
    user_id = uuid4()
    runner = AssessmentAgentRunner(
        TestModel(
            call_tools=["read_profile_snapshot"],
            custom_output_args=ask_candidate().model_dump(mode="json"),
        )
    )
    result = enabled_service(runner).run(
        P1GAgentHandoffRequest(
            handoff=ready_handoff(),
            authenticated_user_id=user_id,
            authorized_scopes=frozenset({"body_profile_read"}),
            agent_context=profile_context(user_id),
        )
    )
    assert result.status == "agent_completed"
    assert result.agent_source_ids == ["profile-revision-3"]
    assert "desk" not in result.model_dump_json()


def test_unauthorized_tool_fails_closed_without_profile_data():
    runner = AssessmentAgentRunner(
        TestModel(
            call_tools=["read_profile_snapshot"],
            custom_output_args=ask_candidate().model_dump(mode="json"),
        )
    )
    result = enabled_service(runner).run(
        P1GAgentHandoffRequest(handoff=ready_handoff(), authenticated_user_id=uuid4())
    )
    assert result.status == "agent_unavailable"
    assert result.error_code == "AGENT_EXECUTION_UNAVAILABLE"
    assert result.agent_source_ids == []
    assert "profile" not in result.model_dump_json()


def test_cross_user_typed_context_is_rejected_before_agent_run():
    user_id = uuid4()
    # A valid context for another authenticated subject cannot be smuggled into the request.
    valid_other_context = profile_context(user_id)
    runner = RecordingRunner()
    result = enabled_service(runner).run(
        P1GAgentHandoffRequest(
            handoff=ready_handoff(),
            authenticated_user_id=uuid4(),
            authorized_scopes=frozenset({"body_profile_read"}),
            agent_context=valid_other_context,
        )
    )
    assert result.status == "agent_output_rejected"
    assert result.error_code == "AGENT_CONTEXT_UNAUTHORIZED"
    assert runner.calls == []


def test_runner_failure_uses_fixed_error_without_exception_details():
    secret = "provider stack secret"
    result = enabled_service(
        RecordingRunner(error=AgentExecutionError(secret))
    ).run(P1GAgentHandoffRequest(handoff=ready_handoff(), authenticated_user_id=uuid4()))
    serialized = result.model_dump_json()
    assert result.status == "agent_unavailable"
    assert result.error_code == "AGENT_EXECUTION_UNAVAILABLE"
    assert secret not in serialized
    assert "AgentExecutionError" not in serialized


def test_no_formal_resource_or_identity_fields_in_result():
    result = enabled_service(RecordingRunner()).run(
        P1GAgentHandoffRequest(handoff=ready_handoff(), authenticated_user_id=uuid4())
    )
    serialized = result.model_dump_json()
    for forbidden in ("user_id", "event_id", "approval_id", "episode_id", "report_id", "lifecycle", "confirmation"):
        assert forbidden not in serialized


def test_result_model_rejects_candidate_for_non_completed_status():
    with pytest.raises(ValueError):
        P1GAgentHandoffResult(
            session_id=SESSION_ID,
            draft_revision=2,
            status="agent_unavailable",
            handoff_status="ready_for_agent",
            candidate=ask_candidate(),
            error_code="AGENT_EXECUTION_UNAVAILABLE",
        )
