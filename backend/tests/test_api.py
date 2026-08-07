from __future__ import annotations

from datetime import datetime, timezone
from uuid import uuid4

from fastapi.testclient import TestClient
from test_contracts import validate_agent_turn

from body_companion.api.app import create_prototype_app
from body_companion.application.assessment_service import AssessmentService
from body_companion.domain.policy import digest_for
from body_companion.domain.safety import RuleCatalog, RuleDefinition, SafetyEngine
from body_companion.domain.types import DraftCandidate, RuleHit


def location(marker_id=None) -> dict:
    marker_id = marker_id or uuid4()
    return {
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
        "mapping": {"method": "direct_user_selection", "confidence": 1, "reviewed_by_user": False},
        "source": {"interaction": "body_map_2d"},
        "created_at": datetime.now(timezone.utc).isoformat(),
    }


def draft_agent(marker_id: str) -> dict:
    return {
        "kind": "draft_ready",
        "event_draft": {
            "locations": [location(marker_id)],
            "sensations": [
                {
                    "sensation_id": str(uuid4()),
                    "code": "aching",
                    "intensities": [{"context": "current", "value": 3}],
                    "location_marker_ids": [marker_id],
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
            "aggravating_factors": [],
            "relieving_factors": [],
            "functional_impacts": [],
            "background_facts": [],
        },
        "user_fact_summary": "synthetic draft",
        "uncertainties": [],
        "draft_digest": "sha256:" + "0" * 64,
    }


def confirmation_service(marker_id: str, candidate: dict) -> AssessmentService:
    rule = RuleDefinition(
        rule_id="test.r3.noop",
        required_question_id=None,
        evaluate=lambda _ctx: RuleHit(rule_id="test.r3.noop", result="not_matched"),
        required_action_code="PROTOTYPE_NONE",
        content_id="prototype.none",
        content_release_id="prototype.none",
        display_message="",
    )
    # The digest is computed from the exact typed payload we give TestModel.
    # Rebuild it once here rather than weakening the server-side validator.
    typed = DraftCandidate.model_validate(candidate)
    candidate["draft_digest"] = digest_for(typed.event_draft)

    class StaticRunner:
        def run_sync(self, _prompt, *, deps):
            return DraftCandidate.model_validate(candidate)

    return AssessmentService(SafetyEngine(RuleCatalog(version="rules.test", rules=(rule,), available=True)), StaticRunner())


def test_prototype_http_boundary_requires_explicit_user_header():
    client = TestClient(create_prototype_app(AssessmentService(SafetyEngine(RuleCatalog(version="none")))))
    response = client.post("/v1/agent/sessions", json={})
    assert response.status_code == 401


def test_prototype_http_boundary_preserves_session_revision():
    user_id = str(uuid4())
    client = TestClient(create_prototype_app(AssessmentService(SafetyEngine(RuleCatalog(version="none")))))
    session_response = client.post(
        "/v1/agent/sessions",
        headers={"X-Prototype-User-Id": user_id},
        json={},
    )
    assert session_response.status_code == 201
    session = session_response.json()
    response = client.post(
        f"/v1/agent/sessions/{session['session_id']}/turns",
        headers={"X-Prototype-User-Id": user_id},
        json={
            "turn_input": {
                "modality": "text",
                "text": "synthetic input",
                "submitted_at": datetime.now(timezone.utc).isoformat(),
            },
            "expected_revision": 1,
        },
    )
    assert response.status_code == 200
    assert response.json()["session"]["revision"] == 2
    assert response.json()["turn"]["status"] == "failed"


def test_prototype_http_confirmation_and_approval_are_two_distinct_steps():
    marker_id = str(uuid4())
    candidate = draft_agent(marker_id)
    client = TestClient(create_prototype_app(confirmation_service(marker_id, candidate)))
    user_id = str(uuid4())
    headers = {"X-Prototype-User-Id": user_id}
    session = client.post("/v1/agent/sessions", headers=headers, json={}).json()
    turn = client.post(
        f"/v1/agent/sessions/{session['session_id']}/turns",
        headers=headers,
        json={
            "turn_input": {
                "modality": "mixed",
                "text": "synthetic input",
                "locations": [location(marker_id)],
                "submitted_at": datetime.now(timezone.utc).isoformat(),
            },
            "expected_revision": 1,
        },
    )
    assert turn.status_code == 200, turn.text
    turn_body = turn.json()
    assert turn_body["session"]["state"] == "awaiting_confirmation"
    assert turn_body["session"]["revision"] == 2
    draft_digest = turn_body["turn"]["output"]["draft_digest"]
    confirmation = client.post(
        f"/v1/agent/sessions/{session['session_id']}/confirmations",
        headers=headers,
        json={
            "turn_id": turn_body["turn"]["turn_id"],
            "expected_revision": 2,
            "decision": "confirm_facts",
            "reviewed_fields": [
                "locations",
                "sensations",
                "temporal",
                "trend",
                "aggravating_factors",
                "relieving_factors",
                "functional_impacts",
                "background_facts",
            ],
            "draft_digest": draft_digest,
            "episode_selection": {
                "mode": "create_new",
                "started_on": datetime.now(timezone.utc).date().isoformat(),
            },
        },
    )
    assert confirmation.status_code == 201, confirmation.text
    confirmation_body = confirmation.json()
    assert confirmation_body["approval"]["status"] == "pending"
    assert confirmation_body["approval"]["revision"] == 1
    assert confirmation_body["session"]["state"] == "awaiting_approval"
    validate_agent_turn(confirmation_body["latest_turn"])

    approval = confirmation_body["approval"]
    decision = client.post(
        f"/v1/approvals/{approval['approval_id']}/decisions",
        headers={**headers, "Idempotency-Key": "approve-1"},
        json={
            "decision": "approve",
            "intent_digest": approval["intent_digest"],
            "expected_revision": 1,
        },
    )
    assert decision.status_code == 200, decision.text
    decision_body = decision.json()
    assert decision_body["status"] == "executed"
    assert decision_body["revision"] == 4
    assert len(decision_body["result_refs"]) == 1
    assert decision_body["latest_turn"]["status"] == "completed"
    assert decision_body["session_snapshot"]["state"] == "completed"
    validate_agent_turn(decision_body["latest_turn"])

    replay = client.post(
        f"/v1/approvals/{approval['approval_id']}/decisions",
        headers={**headers, "Idempotency-Key": "approve-1"},
        json={
            "decision": "approve",
            "intent_digest": approval["intent_digest"],
            "expected_revision": 1,
        },
    )
    assert replay.status_code == 200
    assert replay.json()["result_refs"] == decision_body["result_refs"]
    recovered = client.get(f"/v1/approvals/{approval['approval_id']}", headers=headers)
    assert recovered.status_code == 200
    assert recovered.json()["decision_result"]["status"] == "executed"
