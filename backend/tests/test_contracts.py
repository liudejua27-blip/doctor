from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

from jsonschema import Draft202012Validator
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
