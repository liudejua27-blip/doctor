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


def test_service_uses_agent_only_after_complete_r3_gate():
    definition = RuleDefinition(
        rule_id="test.r3.noop",
        required_question_id=None,
        evaluate=lambda _ctx: RuleHit(rule_id="test.r3.noop", result="not_matched"),
        required_action_code="PROTOTYPE_NONE",
        content_id="prototype.none",
        content_release_id="prototype.none",
        display_message="",
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
