from __future__ import annotations

from datetime import datetime, timedelta, timezone
from unittest.mock import patch
from uuid import uuid4

import pytest
from pydantic_ai import Agent as PydanticAIAgent
from pydantic_ai.messages import ModelResponse, ToolCallPart
from pydantic_ai.models.function import FunctionModel
from pydantic_ai.models.test import TestModel

from body_companion.agents.assessment_agent import (
    AgentDependencies,
    AssessmentAgentRunner,
    ToolAuthorizationError,
    build_assessment_agent,
)
from body_companion.domain.agent_context import (
    AgentConsentGrant,
    AgentReadContext,
    AgentSourceRef,
    BodyProfileContext,
)
from body_companion.domain.types import AgentQuestion


def test_agent_constructor_metadata_contains_only_non_sensitive_version() -> None:
    with patch(
        "body_companion.agents.assessment_agent.Agent",
        wraps=PydanticAIAgent,
    ) as agent_factory:
        build_assessment_agent(TestModel(), agent_version="agent-test")

    assert agent_factory.call_args.kwargs["metadata"] == {"agent_version": "agent-test"}


def test_pydantic_ai_runner_returns_typed_candidate():
    output = {
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
    runner = AssessmentAgentRunner(TestModel(call_tools=[], custom_output_args=output))
    candidate = runner.run_sync(
        "我的左膝有点不舒服",
        deps=AgentDependencies(authenticated_user_id=uuid4()),
    )
    assert candidate.kind == "ask_question"
    assert candidate.questions[0].question_id == "sensation.type"


def test_pydantic_ai_function_model_exercises_union_output_tool():
    """The pinned PydanticAI adapter must select the typed union branch by name."""

    def respond(_messages, agent_info):
        tool_name = next(
            tool.name for tool in agent_info.output_tools if tool.name.endswith("AskQuestionCandidate")
        )
        return ModelResponse(
            parts=[
                ToolCallPart(
                    tool_name,
                    {
                        "kind": "ask_question",
                        "questions": [
                            {
                                "question_id": "time.onset",
                                "category": "time",
                                "prompt": "大约什么时候开始？",
                                "answer_type": "free_text",
                                "required": True,
                            }
                        ],
                        "context_summary": "synthetic",
                    },
                    tool_call_id="function-model-ask",
                )
            ]
        )

    runner = AssessmentAgentRunner(FunctionModel(respond))
    candidate = runner.run_sync(
        "我的左膝有点不舒服",
        deps=AgentDependencies(authenticated_user_id=uuid4()),
    )
    assert candidate.kind == "ask_question"
    assert candidate.questions[0].question_id == "time.onset"


def test_pydantic_ai_function_model_accepts_draft_candidate_branch():
    marker_id = uuid4()
    now = "2026-08-05T00:00:00Z"

    def respond(_messages, agent_info):
        tool_name = next(
            tool.name for tool in agent_info.output_tools if tool.name.endswith("DraftCandidate")
        )
        return ModelResponse(
            parts=[
                ToolCallPart(
                    tool_name,
                    {
                        "kind": "draft_ready",
                        "event_draft": {
                            "locations": [
                                {
                                    "marker_id": str(marker_id),
                                    "region_id": "body.lower_limb.knee",
                                    "ontology_version": "pending",
                                    "laterality": "left",
                                    "surface": "anterior",
                                    "depth": "unspecified",
                                    "shape": "point",
                                    "anchor_2d": {
                                        "asset_id": "prototype-2d",
                                        "asset_version": "pending",
                                        "view": "front",
                                        "point": {"x": 0.5, "y": 0.6},
                                    },
                                    "mapping": {
                                        "method": "direct_user_selection",
                                        "confidence": 1,
                                        "reviewed_by_user": False,
                                    },
                                    "source": {"interaction": "body_map_2d"},
                                    "created_at": now,
                                }
                            ],
                            "sensations": [
                                {
                                    "sensation_id": str(uuid4()),
                                    "code": "aching",
                                    "intensities": [{"context": "current", "value": 3}],
                                    "location_marker_ids": [str(marker_id)],
                                    "source": {"type": "user_report", "source_id": "turn-input"},
                                }
                            ],
                            "temporal": {
                                "onset": {"precision": "unknown", "user_text": "不清楚"},
                                "onset_mode": "unknown",
                                "course": "intermittent",
                                "frequency": "unknown",
                            },
                            "trend": "unknown",
                        },
                        "user_fact_summary": "synthetic draft",
                        "uncertainties": [],
                        "draft_digest": "sha256:" + "a" * 64,
                    },
                    tool_call_id="function-model-draft",
                )
            ]
        )

    runner = AssessmentAgentRunner(FunctionModel(respond))
    candidate = runner.run_sync(
        "我的左膝有点不舒服",
        deps=AgentDependencies(authenticated_user_id=uuid4()),
    )
    assert candidate.kind == "draft_ready"
    assert candidate.event_draft.locations[0].region_id == "body.lower_limb.knee"


def test_tool_scope_is_checked_before_data_is_returned():
    deps = AgentDependencies(
        authenticated_user_id=uuid4(),
    )
    with pytest.raises(ToolAuthorizationError):
        deps.read_current_episode()

    user_id = deps.authenticated_user_id
    grant = AgentConsentGrant(
        subject_user_id=user_id,
        scope="body_profile_read",
        consent_receipt_id=uuid4(),
        purpose="assessment",
        granted_at=datetime.now(timezone.utc),
    )
    profile = BodyProfileContext(
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
    )
    context = AgentReadContext(
        authenticated_user_id=user_id,
        purpose="assessment",
        grants=(grant,),
        profile=profile,
        redaction_policy_version="p3-redaction-1",
    )
    authorized = AgentDependencies(authenticated_user_id=user_id, context=context)
    result = authorized.read_profile_snapshot()
    assert result["scope"] == "body_profile_read"
    assert result["projection"]["activity_types"] == ["running"]
    assert authorized.read_audit.source_ids == ("profile-revision-3",)


def test_typed_context_rejects_cross_user_profile_before_tool_returns_data():
    user_id = uuid4()
    other_user_id = uuid4()
    with pytest.raises(ValueError, match="profile owner"):
        AgentReadContext(
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
                owner_user_id=other_user_id,
                profile_revision=1,
                sources=(
                    AgentSourceRef(
                        source_id="other-profile",
                        source_type="body_profile",
                        revision=1,
                        field_keys=("work_pattern",),
                    ),
                ),
            ),
            redaction_policy_version="p3-redaction-1",
        )


def test_expired_profile_grant_is_rechecked_on_each_read():
    user_id = uuid4()
    now = datetime.now(timezone.utc)
    context = AgentReadContext(
        authenticated_user_id=user_id,
        purpose="assessment",
        grants=(
            AgentConsentGrant(
                subject_user_id=user_id,
                scope="body_profile_read",
                consent_receipt_id=uuid4(),
                purpose="assessment",
                granted_at=now - timedelta(minutes=2),
                expires_at=now - timedelta(seconds=1),
            ),
        ),
        profile=BodyProfileContext(
            owner_user_id=user_id,
            profile_revision=1,
            sources=(
                AgentSourceRef(
                    source_id="expired-profile",
                    source_type="body_profile",
                    revision=1,
                    field_keys=("work_pattern",),
                ),
            ),
        ),
        redaction_policy_version="p3-redaction-1",
    )
    deps = AgentDependencies(authenticated_user_id=user_id, context=context)
    with pytest.raises(ToolAuthorizationError):
        deps.read_profile_snapshot()
    assert deps.read_audit.denied_scopes == ["body_profile_read"]
