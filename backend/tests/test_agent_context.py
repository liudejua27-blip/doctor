from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import uuid4

import pytest
from jsonschema import Draft202012Validator
from pydantic import ValidationError
from pydantic_ai.models.test import TestModel

from body_companion.agents.assessment_agent import AgentDependencies, AssessmentAgentRunner, ToolAuthorizationError
from body_companion.application.assessment_service import AssessmentRequest, AssessmentService
from body_companion.domain.agent_context import (
    AgentConsentGrant,
    AgentReadContext,
    AgentSourceRef,
    BodyProfileContext,
    ContextAuthorizationError,
    ConfirmedEventSummary,
    EpisodeContext,
)
from body_companion.domain.safety import RuleCatalog, RuleDefinition, RuleHit, SafetyEngine
from body_companion.domain.types import UserTurnInput


ROOT = Path(__file__).resolve().parents[2]


def profile_context(user_id, *, grant_scope="body_profile_read"):
    now = datetime.now(timezone.utc)
    grant = AgentConsentGrant(
        subject_user_id=user_id,
        scope=grant_scope,
        consent_receipt_id=uuid4(),
        purpose="assessment",
        granted_at=now,
    )
    profile = BodyProfileContext(
        owner_user_id=user_id,
        profile_revision=4,
        activity_types=("running", "desk_work"),
        training_frequency_per_week=3,
        work_pattern="desk",
        preferred_language=None,
        timezone=None,
        sources=(
            AgentSourceRef(
                source_id="profile-4",
                source_type="body_profile",
                revision=4,
                field_keys=("activity_types", "training_frequency_per_week", "work_pattern"),
            ),
        ),
    )
    return AgentReadContext(
        authenticated_user_id=user_id,
        purpose="assessment",
        grants=(grant,),
        profile=profile,
        redaction_policy_version="p3-redaction-1",
    )


def test_profile_tool_returns_typed_minimal_projection_and_redacted_audit():
    user_id = uuid4()
    deps = AgentDependencies(authenticated_user_id=user_id, context=profile_context(user_id))

    projection = deps.read_profile_snapshot()

    assert projection["scope"] == "body_profile_read"
    assert projection["projection"]["profile_revision"] == 4
    assert projection["projection"]["activity_types"] == ["running", "desk_work"]
    assert "preferred_language" not in projection["projection"]
    assert "consent_receipt_id" in projection
    assert deps.read_audit.summary() == {
        "successful_reads": [
            {"scope": "body_profile_read", "source_ids": ["profile-4"], "revision": 4}
        ],
        "denied_scopes": [],
    }


def test_context_rejects_unknown_fields_and_cross_user_grant():
    user_id = uuid4()
    with pytest.raises(ValidationError):
        AgentReadContext.model_validate(
            {
                **profile_context(user_id).model_dump(mode="json"),
                "unexpected_raw_transcript": "不要进入模型上下文",
            }
        )

    with pytest.raises(ValidationError, match="outside the source field allowlist"):
        BodyProfileContext(
            owner_user_id=user_id,
            profile_revision=1,
            preferred_language="zh-CN",
            sources=(
                AgentSourceRef(
                    source_id="profile-without-language-allowlist",
                    source_type="body_profile",
                    revision=1,
                    field_keys=("activity_types",),
                ),
            ),
        )

    other = uuid4()
    with pytest.raises(ValidationError, match="consent grant subject"):
        AgentReadContext(
            authenticated_user_id=user_id,
            purpose="assessment",
            grants=(
                AgentConsentGrant(
                    subject_user_id=other,
                    scope="body_profile_read",
                    consent_receipt_id=uuid4(),
                    purpose="assessment",
                    granted_at=datetime.now(timezone.utc),
                ),
            ),
            redaction_policy_version="p3-redaction-1",
        )


def test_expiry_and_scope_are_rechecked_on_every_read():
    user_id = uuid4()
    now = datetime.now(timezone.utc)
    context = profile_context(user_id).model_copy(
        update={
            "grants": (
                AgentConsentGrant(
                    subject_user_id=user_id,
                    scope="body_profile_read",
                    consent_receipt_id=uuid4(),
                    purpose="assessment",
                    granted_at=now - timedelta(minutes=2),
                    expires_at=now - timedelta(seconds=1),
                ),
            )
        }
    )
    deps = AgentDependencies(authenticated_user_id=user_id, context=context)
    with pytest.raises(ToolAuthorizationError):
        deps.read_profile_snapshot()

    current_only = profile_context(user_id)
    with pytest.raises(ToolAuthorizationError):
        AgentDependencies(authenticated_user_id=user_id, context=current_only).read_current_episode()


def test_current_episode_scope_cannot_be_used_as_historical_scope():
    user_id = uuid4()
    episode_id = uuid4()
    source = AgentSourceRef(
        source_id="event-1",
        source_type="confirmed_event",
        revision=1,
        field_keys=("region_ids", "sensation_codes", "trend"),
    )
    event = ConfirmedEventSummary(
        event_id=uuid4(),
        episode_id=episode_id,
        owner_user_id=user_id,
        resource_revision=1,
        region_ids=("body.lower_limb.knee",),
        sensation_codes=("aching",),
        trend="unknown",
        source=source,
    )
    context = AgentReadContext(
        authenticated_user_id=user_id,
        purpose="assessment",
        grants=(
            AgentConsentGrant(
                subject_user_id=user_id,
                scope="current_episode_read",
                consent_receipt_id=uuid4(),
                purpose="assessment",
                granted_at=datetime.now(timezone.utc),
            ),
        ),
        episode=EpisodeContext(
            owner_user_id=user_id,
            episode_id=episode_id,
            episode_revision=2,
            status="open",
            scope="current_episode_read",
            events=(event,),
            source=source,
        ),
        redaction_policy_version="p3-redaction-1",
    )
    deps = AgentDependencies(authenticated_user_id=user_id, context=context)
    with pytest.raises(ContextAuthorizationError):
        deps.context.projection("historical_events_read")


def test_historical_scope_is_explicit_and_returns_only_confirmed_summary():
    user_id = uuid4()
    episode_id = uuid4()
    source = AgentSourceRef(
        source_id="history-event-1",
        source_type="confirmed_event",
        revision=2,
        field_keys=("region_ids", "sensation_codes", "trend"),
    )
    context = AgentReadContext(
        authenticated_user_id=user_id,
        purpose="assessment",
        grants=(
            AgentConsentGrant(
                subject_user_id=user_id,
                scope="historical_events_read",
                consent_receipt_id=uuid4(),
                purpose="assessment",
                granted_at=datetime.now(timezone.utc),
            ),
        ),
        episode=EpisodeContext(
            owner_user_id=user_id,
            episode_id=episode_id,
            episode_revision=3,
            status="resolved",
            scope="historical_events_read",
            events=(
                ConfirmedEventSummary(
                    event_id=uuid4(),
                    episode_id=episode_id,
                    owner_user_id=user_id,
                    resource_revision=2,
                    region_ids=("body.upper_limb.shoulder",),
                    sensation_codes=("tightness",),
                    trend="improving",
                    source=source,
                ),
            ),
            source=source,
        ),
        redaction_policy_version="p3-redaction-1",
    )
    deps = AgentDependencies(authenticated_user_id=user_id, context=context)

    result = deps.read_historical_events()

    assert result["scope"] == "historical_events_read"
    assert result["projection"]["events"][0]["sensation_codes"] == ["tightness"]
    assert "raw_text" not in result["projection"]["events"][0]


def test_pydantic_ai_tool_uses_typed_context_and_records_source_usage():
    user_id = uuid4()
    output = {
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
        "context_summary": "仅使用用户授权的背景摘要",
    }
    deps = AgentDependencies(authenticated_user_id=user_id, context=profile_context(user_id))
    runner = AssessmentAgentRunner(TestModel(call_tools=["read_profile_snapshot"], custom_output_args=output))

    candidate = runner.run_sync("我的膝盖有点不舒服", deps=deps)

    assert candidate.kind == "ask_question"
    assert deps.read_audit.source_ids == ("profile-4",)


def test_application_service_propagates_only_actual_typed_context_sources():
    user_id = uuid4()
    output = {
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
    }
    runner = AssessmentAgentRunner(TestModel(call_tools=["read_profile_snapshot"], custom_output_args=output))
    rule = RuleDefinition(
        rule_id="test.p3.noop",
        required_question_id=None,
        evaluate=lambda _ctx: RuleHit(rule_id="test.p3.noop", result="not_matched"),
        required_action_code="PROTOTYPE_NONE",
        content_id="prototype.none",
        content_release_id="prototype.none",
        display_message="synthetic no-op rule",
    )
    service = AssessmentService(SafetyEngine(RuleCatalog(version="rules.p3", rules=(rule,), available=True)), runner)
    request = AssessmentRequest(
        session_id=uuid4(),
        turn_id=uuid4(),
        user_id=user_id,
        sequence=1,
        revision=1,
        turn_input=UserTurnInput(
            modality="text",
            text="我的膝盖有点不舒服",
            submitted_at=datetime.now(timezone.utc),
        ),
        agent_context=profile_context(user_id),
    )

    outcome = service.assess(request)

    assert outcome.candidate is not None
    assert outcome.envelope.data_sources_used == ["profile-4"]


def test_agent_context_json_schema_accepts_typed_projection():
    schema = json.loads((ROOT / "docs/contracts/agent-context.schema.json").read_text())
    context = profile_context(uuid4())
    Draft202012Validator(schema).validate(context.model_dump(mode="json", exclude_none=True))
