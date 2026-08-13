from __future__ import annotations

from datetime import datetime, timezone
from uuid import uuid4

from pydantic_ai.models.test import TestModel

from body_companion.agents.assessment_agent import AssessmentAgentRunner
from body_companion.application.assessment_service import AssessmentRequest, AssessmentService
from body_companion.domain.safety import RuleCatalog, RuleDefinition, SafetyEngine
from body_companion.domain.types import RuleHit, UserTurnInput


def request() -> AssessmentRequest:
    return AssessmentRequest(
        session_id=uuid4(),
        turn_id=uuid4(),
        user_id=uuid4(),
        sequence=1,
        revision=1,
        turn_input=UserTurnInput(modality="text", text="synthetic input", submitted_at=datetime.now(timezone.utc)),
    )


def test_service_never_runs_agent_for_r0():
    definition = RuleDefinition(
        rule_id="test.r0",
        required_question_id=None,
        evaluate=lambda _ctx: RuleHit(rule_id="test.r0", result="matched", tier="R0", evidence_refs=["input"]),
        required_action_code="PROTOTYPE_R0",
        content_id="prototype.r0",
        content_release_id="prototype.none",
        display_message="prototype escalation",
    )
    service = AssessmentService(
        SafetyEngine(RuleCatalog(version="rules.test", rules=(definition,), available=True)),
        agent_runner=AssessmentAgentRunner(
            TestModel(
                call_tools=[],
                custom_output_args={
                    "kind": "ask_question",
                    "questions": [
                        {
                            "question_id": "should.not.run",
                            "category": "sensation",
                            "prompt": "should not run",
                            "answer_type": "free_text",
                            "required": True,
                        }
                    ],
                    "context_summary": "synthetic",
                }
            )
        ),
    )
    outcome = service.assess(request())
    assert outcome.status == "escalated"
    assert outcome.evaluation.tier == "R0"
    assert outcome.candidate is None
    assert outcome.agent_turn["output_origin"] == "application"


def test_service_keeps_r0_action_when_lower_priority_rule_is_unresolved():
    class CountingRunner:
        calls = 0

        def run_sync(self, _user_text, *, deps):
            self.calls += 1
            raise AssertionError("agent must not run after an R0 match")

    r0 = RuleDefinition(
        rule_id="test.r0",
        required_question_id=None,
        evaluate=lambda _ctx: RuleHit(
            rule_id="test.r0", result="matched", tier="R0", evidence_refs=["input"]
        ),
        required_action_code="PROTOTYPE_R0",
        content_id="prototype.r0",
        content_release_id="prototype.release.r0",
        display_message="prototype urgent action",
    )
    unresolved = RuleDefinition(
        rule_id="test.maybe",
        required_question_id="safety.lower_priority",
        evaluate=lambda _ctx: RuleHit(rule_id="test.maybe", result="undetermined"),
        required_action_code="PROTOTYPE_CLARIFY",
        content_id="prototype.clarify",
        content_release_id="prototype.release.clarify",
        display_message="prototype clarification",
    )
    runner = CountingRunner()
    service = AssessmentService(
        SafetyEngine(RuleCatalog(version="rules.priority", rules=(r0, unresolved), available=True)),
        agent_runner=runner,  # type: ignore[arg-type]
    )

    outcome = service.assess(request())

    assert outcome.status == "escalated"
    assert outcome.evaluation.tier == "R0"
    assert outcome.evaluation.required_action_code == "PROTOTYPE_R0"
    assert outcome.agent_turn["output"]["content_id"] == "prototype.r0"
    assert outcome.agent_turn["output"]["display_message"] == "prototype urgent action"
    assert runner.calls == 0


def test_service_never_runs_agent_for_available_but_empty_catalog():
    class CountingRunner:
        calls = 0

        def run_sync(self, _user_text, *, deps):
            self.calls += 1
            raise AssertionError("agent must not run without an executable safety catalog")

    runner = CountingRunner()
    service = AssessmentService(
        SafetyEngine(RuleCatalog(version="rules.empty", rules=(), available=True)),
        agent_runner=runner,  # type: ignore[arg-type]
    )

    outcome = service.assess(request())

    assert outcome.status == "failed"
    assert outcome.error_code == "SAFETY_SERVICE_UNAVAILABLE"
    assert outcome.evaluation.tier == "undetermined"
    assert runner.calls == 0


def test_service_uses_agent_only_after_complete_r3_gate():
    definition = RuleDefinition(
        rule_id="test.r3.noop",
        required_question_id=None,
        evaluate=lambda _ctx: RuleHit(rule_id="test.r3.noop", result="not_matched"),
        required_action_code="PROTOTYPE_NONE",
        content_id="prototype.none",
        content_release_id="prototype.none",
        display_message="synthetic no-op rule",
    )
    service = AssessmentService(
        SafetyEngine(RuleCatalog(version="rules.test", rules=(definition,), available=True)),
        agent_runner=AssessmentAgentRunner(
            TestModel(
                call_tools=[],
                custom_output_args={
                    "kind": "ask_question",
                    "questions": [
                        {
                            "question_id": "sensation.type",
                            "category": "sensation",
                            "prompt": "你更接近哪一种感觉？",
                            "answer_type": "free_text",
                            "required": True,
                        }
                    ],
                    "context_summary": "synthetic",
                }
            )
        ),
    )
    outcome = service.assess(request())
    assert outcome.status == "awaiting_user"
    assert outcome.candidate is not None
    assert outcome.envelope.mode == "normal"
    assert outcome.agent_turn["output_origin"] == "agent"
