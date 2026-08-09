from __future__ import annotations

import copy
import json
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

import pytest
from jsonschema import Draft202012Validator
from jsonschema.exceptions import ValidationError
from referencing import Registry, Resource
from pydantic_ai.models.test import TestModel

from body_companion.agents.assessment_agent import AssessmentAgentRunner
from body_companion.application.assessment_service import AssessmentRequest, AssessmentService
from body_companion.domain.safety import RuleCatalog, RuleDefinition, SafetyEngine
from body_companion.domain.types import (
    Anchor3D,
    BodyLocation,
    Barycentric,
    LocationSource,
    Mapping,
    ModelAsset,
    RuleHit,
    UV,
    UserTurnInput,
)


ROOT = Path(__file__).resolve().parents[2]


def validate_agent_turn(payload: dict) -> None:
    schema_path = ROOT / "docs/contracts/agent-turn.schema.json"
    schema = json.loads(schema_path.read_text())
    registry = Registry()
    for name in ("agent-turn.schema.json", "body-location.schema.json", "body-signal-event.schema.json"):
        referenced = json.loads((ROOT / "docs/contracts" / name).read_text())
        registry = registry.with_resource(referenced["$id"], Resource.from_contents(referenced))
    Draft202012Validator(schema, registry=registry).validate(payload)


def request() -> AssessmentRequest:
    return AssessmentRequest(
        session_id=uuid4(),
        turn_id=uuid4(),
        user_id=uuid4(),
        sequence=1,
        revision=1,
        turn_input=UserTurnInput(modality="text", text="synthetic input", submitted_at=datetime.now(timezone.utc)),
    )


def test_normal_agent_question_turn_matches_agent_turn_schema():
    rule = RuleDefinition(
        rule_id="test.r3.noop",
        required_question_id=None,
        evaluate=lambda _ctx: RuleHit(rule_id="test.r3.noop", result="not_matched"),
        required_action_code="PROTOTYPE_NONE",
        content_id="prototype.none",
        content_release_id="prototype.none",
        display_message="",
    )
    runner = AssessmentAgentRunner(
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
    )
    service = AssessmentService(SafetyEngine(RuleCatalog(version="rules.test", rules=(rule,), available=True)), runner)
    outcome = service.assess(request())
    validate_agent_turn(outcome.agent_turn)

    r2_normal_turn = copy.deepcopy(outcome.agent_turn)
    r2_normal_turn["deterministic_safety_gate"]["tier"] = "R2"
    r2_normal_turn["safety_envelope"]["safety"]["tier"] = "R2"
    with pytest.raises(ValidationError):
        validate_agent_turn(r2_normal_turn)


def test_ios_intake_contracts_reject_r2_ordinary_agent_permission():
    contracts = ROOT / "docs/contracts"

    client_schema = json.loads((contracts / "ios-signal-intake.schema.json").read_text())
    client_validator = Draft202012Validator(client_schema["$defs"]["SafetyState"])
    client_validator.validate({"status": "no_rule_triggered", "ordinary_agent_allowed": True})
    with pytest.raises(ValidationError):
        client_validator.validate({"status": "r2", "ordinary_agent_allowed": True})

    body_location_schema = json.loads((contracts / "body-location.schema.json").read_text())
    client_registry = Registry()
    client_registry = client_registry.with_resource(client_schema["$id"], Resource.from_contents(client_schema))
    client_registry = client_registry.with_resource(body_location_schema["$id"], Resource.from_contents(body_location_schema))
    full_client_validator = Draft202012Validator(client_schema, registry=client_registry)
    normal_agent_draft = {
        "schema_version": "1.1",
        "session_id": str(uuid4()),
        "draft_revision": 1,
        "phase": "agent_draft",
        "locations": [],
        "facts": {
            "sensations": [],
            "aggravating_factors": [],
            "relieving_factors": [],
            "functional_impacts": [],
            "background_facts": [],
        },
        "safety": {"status": "no_rule_triggered", "ordinary_agent_allowed": True},
        "reviewed_groups": [],
        "unknown_groups": [],
        "updated_at": "2026-08-09T00:00:00Z",
    }
    # This schema test isolates phase/safety coupling. The Swift domain layer
    # separately rejects an agent phase without a selected BodyLocation.
    full_client_validator.validate({**normal_agent_draft, "locations": [{
        "marker_id": str(uuid4()),
        "region_id": "body.test.region",
        "ontology_version": "test",
        "laterality": "left",
        "surface": "anterior",
        "depth": "unspecified",
        "shape": "point",
        "anchor_2d": {
            "view": "front",
            "asset_id": "test",
            "asset_version": "1",
            "point": {"x": 0.5, "y": 0.5},
        },
        "mapping": {"method": "direct_user_selection", "confidence": 1.0, "reviewed_by_user": False},
        "source": {"interaction": "body_map_2d"},
        "created_at": "2026-08-09T00:00:00Z",
    }]})
    with pytest.raises(ValidationError):
        full_client_validator.validate({
            **normal_agent_draft,
            "safety": {"status": "r2", "ordinary_agent_allowed": False},
        })

    p4_schema = json.loads((contracts / "ios-draft-envelope.schema.json").read_text())
    p4_validator = Draft202012Validator(p4_schema)
    valid_p4_envelope = {
        "schema_version": "1.1",
        "draft_id": str(uuid4()),
        "owner_id": str(uuid4()),
        "client_operation_id": str(uuid4()),
        "draft_revision": 1,
        "lifecycle": "editing",
        "locations": [],
        "facts": {
            "sensations": [{"code": "sore", "location_marker_ids": [str(uuid4())]}],
            "aggravating_factors": [],
            "relieving_factors": [],
            "functional_impacts": [],
            "background_facts": [],
            "time_pattern": "",
        },
        "sync": {"state": "not_queued", "attempt_count": 0},
        "created_at": "2026-08-09T00:00:00Z",
        "updated_at": "2026-08-09T00:00:00Z",
    }
    p4_validator.validate(valid_p4_envelope)
    with pytest.raises(ValidationError):
        p4_validator.validate({
            **valid_p4_envelope,
            "facts": {
                **valid_p4_envelope["facts"],
                "sensations": [{"code": "sore", "location_marker_ids": []}],
            },
        })

    handoff_schema = json.loads((contracts / "ios-signal-intake-application-handoff.schema.json").read_text())
    server_validator = Draft202012Validator(handoff_schema["$defs"]["ServerSafetyProjection"])
    r3_projection = {
        "status": "complete",
        "tier": "R3",
        "rule_outcome": "no_rule_triggered",
        "triggered_rule_ids": [],
        "required_question_ids": [],
        "rule_set_version": "rules.test",
        "all_current_rules_executed": True,
        "scenario_support": "supported",
        "unresolved_safety": False,
        "ordinary_agent_allowed": True,
        "evaluated_at": "2026-08-09T00:00:00Z",
    }
    server_validator.validate(r3_projection)
    r2_projection = {
        **r3_projection,
        "tier": "R2",
        "rule_outcome": "triggered",
        "triggered_rule_ids": ["test.r2"],
    }
    with pytest.raises(ValidationError):
        server_validator.validate(r2_projection)

    adapter_schema = json.loads((contracts / "ios-signal-intake-adapter-result.schema.json").read_text())
    ready_rule = Draft202012Validator(adapter_schema["allOf"][0])
    ready_rule.validate({"status": "ready_for_agent", "assessment_draft": {}, "server_safety_tier": "R3"})
    with pytest.raises(ValidationError):
        ready_rule.validate({"status": "ready_for_agent", "assessment_draft": {}, "server_safety_tier": "R2"})


def test_r0_escalation_turn_matches_agent_turn_schema():
    rule = RuleDefinition(
        rule_id="test.r0",
        required_question_id=None,
        evaluate=lambda _ctx: RuleHit(rule_id="test.r0", result="matched", tier="R0", evidence_refs=["input"]),
        required_action_code="PROTOTYPE_R0",
        content_id="prototype.r0",
        content_release_id="prototype.none",
        display_message="prototype escalation",
    )
    service = AssessmentService(SafetyEngine(RuleCatalog(version="rules.test", rules=(rule,), available=True)))
    outcome = service.assess(request())
    validate_agent_turn(outcome.agent_turn)


def test_application_safety_question_turn_matches_agent_turn_schema():
    rule = RuleDefinition(
        rule_id="test.safety.unresolved",
        required_question_id="safety.synthetic_question",
        evaluate=lambda _ctx: RuleHit(rule_id="test.safety.unresolved", result="undetermined"),
        required_action_code="PROTOTYPE_SAFETY_CLARIFICATION",
        content_id="prototype.safety.clarification",
        content_release_id="prototype.none",
        display_message="",
    )
    service = AssessmentService(SafetyEngine(RuleCatalog(version="rules.test", rules=(rule,), available=True)))
    outcome = service.assess(request())

    assert outcome.status == "awaiting_user"
    assert outcome.agent_turn["output_origin"] == "application"
    assert outcome.agent_turn["safety_envelope"]["mode"] == "degraded"
    assert [question["question_id"] for question in outcome.agent_turn["output"]["questions"]] == [
        "safety.synthetic_question"
    ]
    assert {question["category"] for question in outcome.agent_turn["output"]["questions"]} == {"safety"}
    validate_agent_turn(outcome.agent_turn)


def test_python_body_location_matches_canonical_schema():
    schema_path = ROOT / "docs/contracts/body-location.schema.json"
    schema = json.loads(schema_path.read_text())
    location = BodyLocation(
        marker_id=uuid4(),
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
            "point": {"x": 0.4, "y": 0.5},
        },
        mapping=Mapping(method="direct_user_selection", confidence=1, reviewed_by_user=False),
        source=LocationSource(interaction="body_map_2d"),
        created_at=datetime.now(timezone.utc),
    )
    Draft202012Validator(schema).validate(location.model_dump(mode="json", exclude_none=True))

    three_d = location.model_copy(
        update={
            "anchor_2d": None,
            "anchor_3d": Anchor3D(
                entity_id="approved-placeholder",
                local_position={"x": 0.1, "y": 0.2, "z": 0.3},
                local_normal={"x": 0, "y": 1, "z": 0},
                triangle_index=7,
                barycentric=Barycentric(u=0.2, v=0.3, w=0.5),
                uv=UV(u=0.4, v=0.5),
            ),
            "model_asset": ModelAsset(
                asset_id="approved-placeholder",
                asset_version="pending",
                variant="default_neutral",
                coordinate_convention="realitykit_y_up_right_handed",
            ),
            "source": LocationSource(interaction="body_map_3d"),
        }
    )
    Draft202012Validator(schema).validate(three_d.model_dump(mode="json", exclude_none=True))
