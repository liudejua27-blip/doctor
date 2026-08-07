from __future__ import annotations

from datetime import date, datetime, timezone
import hashlib
import json
from pathlib import Path
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

from body_companion.api.app import create_prototype_app
from body_companion.domain.confirmation import (
    ApprovalDecisionRequest,
    ConfirmationConflict,
    ConfirmationRequest,
    PrototypeApprovalStore,
)
from body_companion.domain.events import PrototypeEventStore
from body_companion.domain.policy import digest_for
from body_companion.domain.types import EpisodeSelection, UserTurnInput

from test_api import confirmation_service, draft_agent, location
from test_confirmation import draft, safety


ROOT = Path(__file__).resolve().parents[2]


def validate_event(payload: dict) -> None:
    schema = json.loads((ROOT / "docs/contracts/body-signal-event.schema.json").read_text())
    registry = Registry()
    for name in ("body-location.schema.json", "body-signal-event.schema.json"):
        content = json.loads((ROOT / "docs/contracts" / name).read_text())
        registry = registry.with_resource(content["$id"], Resource.from_contents(content))
    Draft202012Validator(schema, registry=registry).validate(payload)


def prototype_request(candidate, *, session_id, turn_id, selection=None) -> ConfirmationRequest:
    return ConfirmationRequest(
        turn_id=turn_id,
        expected_revision=2,
        reviewed_fields=[
            "locations",
            "sensations",
            "temporal",
            "trend",
            "aggravating_factors",
            "relieving_factors",
            "functional_impacts",
            "background_facts",
        ],
        draft_digest=candidate.draft_digest,
        episode_selection=selection
        or EpisodeSelection(mode="create_new", started_on=date(2026, 8, 5)),
    )


def commit_direct(*, selection=None):
    _event_draft, candidate = draft()
    owner_id = uuid4()
    session_id = uuid4()
    turn_id = uuid4()
    event_store = PrototypeEventStore()
    approvals = PrototypeApprovalStore(event_writer=event_store)
    confirmation = prototype_request(candidate, session_id=session_id, turn_id=turn_id, selection=selection)
    intent = approvals.create_intent(
        owner_id=owner_id,
        session_id=session_id,
        current_revision=2,
        candidate=candidate,
        source_turn_id=turn_id,
        confirmation=confirmation,
        safety=safety(),
        raw_input=UserTurnInput(
            modality="text",
            text="我的左膝有点不舒服",
            language="zh-CN",
            submitted_at=datetime.now(timezone.utc),
        ),
        agent_versions={
            "agent_version": "p1b-agent-test",
            "prompt_version": "p1b-prompt-test",
            "provider": "injected",
            "model_name": "prototype",
            "model_version": "test",
        },
    )
    result = approvals.decide(
        owner_id=owner_id,
        approval_id=intent.approval.approval_id,
        request=ApprovalDecisionRequest(
            decision="approve",
            intent_digest=intent.approval.intent_digest,
            expected_revision=1,
        ),
        idempotency_key="p2-direct-1",
        current_session_revision=2,
        session_snapshot={"session_id": str(session_id), "revision": 2},
        latest_turn={"turn_id": str(turn_id), "status": "approval_required"},
    )
    return owner_id, approvals, event_store, intent, result


def test_confirmed_event_projection_is_schema_valid_and_user_reviewed():
    owner_id, _approvals, store, _intent, result = commit_direct()
    assert result.status == "executed"
    assert len(result.result_refs) == 1
    event = store.get_event(owner_id=owner_id, event_id=result.result_refs[0].id)
    validate_event(event.model_dump(mode="json", exclude_none=True))
    assert event.lifecycle == "confirmed"
    assert event.resource_revision == 1
    assert event.correction_sequence == 1
    assert event.content_digest and event.confirmation is not None
    assert all(location.mapping.reviewed_by_user for location in event.locations)
    assert store.count_events(owner_id=owner_id) == 1
    canonical = json.dumps(event.canonical_payload(), ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    assert event.content_digest == "sha256:" + hashlib.sha256(canonical).hexdigest()


def test_confirmed_event_replay_never_creates_a_second_event():
    owner_id, approvals, store, intent, first = commit_direct()
    request = ApprovalDecisionRequest(
        decision="approve", intent_digest=intent.approval.intent_digest, expected_revision=1
    )
    replay = approvals.decide(
        owner_id=owner_id,
        approval_id=intent.approval.approval_id,
        request=request,
        idempotency_key="p2-direct-1",
        current_session_revision=2,
        session_snapshot={"session_id": str(intent.approval.source_session_id), "revision": 2},
        latest_turn={"turn_id": str(intent.source_turn_id), "status": "approval_required"},
    )
    different_key = approvals.decide(
        owner_id=owner_id,
        approval_id=intent.approval.approval_id,
        request=request,
        idempotency_key="p2-direct-2",
        current_session_revision=2,
        session_snapshot={"session_id": str(intent.approval.source_session_id), "revision": 2},
        latest_turn={"turn_id": str(intent.source_turn_id), "status": "approval_required"},
    )
    assert replay == first
    assert different_key.result_refs == first.result_refs
    assert store.count_events(owner_id=owner_id) == 1


def test_join_existing_monitoring_episode_reopens_only_with_valid_revision():
    _event_draft, candidate = draft()
    owner_id = uuid4()
    store = PrototypeEventStore()
    episode = store.seed_episode(
        owner_id=owner_id,
        region_id="body.lower_limb.knee",
        status="monitoring",
        started_on=date(2026, 8, 1),
    )
    selection = EpisodeSelection(mode="join_existing", episode_id=episode.episode_id, expected_revision=1)
    sid, tid = uuid4(), uuid4()
    approvals = PrototypeApprovalStore(event_writer=store)
    confirmation = prototype_request(candidate, session_id=sid, turn_id=tid, selection=selection)
    intent = approvals.create_intent(
        owner_id=owner_id,
        session_id=sid,
        current_revision=2,
        candidate=candidate,
        source_turn_id=tid,
        confirmation=confirmation,
        safety=safety(),
        raw_input=UserTurnInput(modality="text", text="膝盖不舒服", submitted_at=datetime.now(timezone.utc)),
        agent_versions={"agent_version": "a", "prompt_version": "p", "provider": "i", "model_name": "m", "model_version": "v"},
    )
    result = approvals.decide(
        owner_id=owner_id,
        approval_id=intent.approval.approval_id,
        request=ApprovalDecisionRequest(decision="approve", intent_digest=intent.approval.intent_digest, expected_revision=1),
        idempotency_key="join-1",
        current_session_revision=2,
        session_snapshot={},
        latest_turn={"turn_id": str(tid)},
    )
    assert result.status == "executed"
    updated = store.get_episode(owner_id=owner_id, episode_id=episode.episode_id)
    assert updated.status == "open"
    assert updated.revision == 2


def test_join_resolved_episode_is_rejected_without_explicit_reopen_and_zero_writes():
    _event_draft, candidate = draft()
    owner_id = uuid4()
    store = PrototypeEventStore()
    episode = store.seed_episode(
        owner_id=owner_id,
        region_id="body.lower_limb.knee",
        status="resolved",
        started_on=date(2026, 8, 1),
    )
    sid, tid = uuid4(), uuid4()
    approvals = PrototypeApprovalStore(event_writer=store)
    selection = EpisodeSelection(mode="join_existing", episode_id=episode.episode_id, expected_revision=1)
    intent = approvals.create_intent(
        owner_id=owner_id,
        session_id=sid,
        current_revision=2,
        candidate=candidate,
        source_turn_id=tid,
        confirmation=prototype_request(candidate, session_id=sid, turn_id=tid, selection=selection),
        safety=safety(),
        raw_input=UserTurnInput(modality="text", text="再次不舒服", submitted_at=datetime.now(timezone.utc)),
        agent_versions={"agent_version": "a", "prompt_version": "p", "provider": "i", "model_name": "m", "model_version": "v"},
    )
    with pytest.raises(ConfirmationConflict) as exc_info:
        approvals.decide(
            owner_id=owner_id,
            approval_id=intent.approval.approval_id,
            request=ApprovalDecisionRequest(decision="approve", intent_digest=intent.approval.intent_digest, expected_revision=1),
            idempotency_key="reject-1",
            current_session_revision=2,
            session_snapshot={},
            latest_turn={"turn_id": str(tid)},
        )
    assert exc_info.value.code == "EPISODE_NOT_REOPENABLE"
    assert store.count_events(owner_id=owner_id) == 0


def test_reopen_existing_requires_explicit_selection_and_updates_episode():
    _event_draft, candidate = draft()
    owner_id = uuid4()
    store = PrototypeEventStore()
    episode = store.seed_episode(
        owner_id=owner_id,
        region_id="body.lower_limb.knee",
        status="closed",
        started_on=date(2026, 8, 1),
    )
    selection = EpisodeSelection(mode="reopen_existing", episode_id=episode.episode_id, expected_revision=1)
    sid, tid = uuid4(), uuid4()
    approvals = PrototypeApprovalStore(event_writer=store)
    intent = approvals.create_intent(
        owner_id=owner_id,
        session_id=sid,
        current_revision=2,
        candidate=candidate,
        source_turn_id=tid,
        confirmation=prototype_request(candidate, session_id=sid, turn_id=tid, selection=selection),
        safety=safety(),
        raw_input=UserTurnInput(modality="text", text="明确重新记录", submitted_at=datetime.now(timezone.utc)),
        agent_versions={"agent_version": "a", "prompt_version": "p", "provider": "i", "model_name": "m", "model_version": "v"},
    )
    result = approvals.decide(
        owner_id=owner_id,
        approval_id=intent.approval.approval_id,
        request=ApprovalDecisionRequest(decision="approve", intent_digest=intent.approval.intent_digest, expected_revision=1),
        idempotency_key="reopen-1",
        current_session_revision=2,
        session_snapshot={},
        latest_turn={"turn_id": str(tid)},
    )
    assert result.status == "executed"
    updated = store.get_episode(owner_id=owner_id, episode_id=episode.episode_id)
    assert updated.status == "open"
    assert updated.revision == 2


def test_event_validation_failure_keeps_approval_pending_and_writes_nothing():
    event_draft, candidate = draft()
    bad_sensation = event_draft.sensations[0].model_copy(update={"location_marker_ids": [uuid4()]})
    bad_draft = event_draft.model_copy(update={"sensations": [bad_sensation]})
    bad_candidate = candidate.model_copy(update={"event_draft": bad_draft, "draft_digest": digest_for(bad_draft)})
    owner_id, session_id, turn_id = uuid4(), uuid4(), uuid4()
    store = PrototypeEventStore()
    approvals = PrototypeApprovalStore(event_writer=store)
    confirmation = prototype_request(bad_candidate, session_id=session_id, turn_id=turn_id)
    intent = approvals.create_intent(
        owner_id=owner_id,
        session_id=session_id,
        current_revision=2,
        candidate=bad_candidate,
        source_turn_id=turn_id,
        confirmation=confirmation,
        safety=safety(),
        raw_input=UserTurnInput(modality="text", text="位置引用错误", submitted_at=datetime.now(timezone.utc)),
        agent_versions={"agent_version": "a", "prompt_version": "p", "provider": "i", "model_name": "m", "model_version": "v"},
    )
    with pytest.raises(ConfirmationConflict) as exc_info:
        approvals.decide(
            owner_id=owner_id,
            approval_id=intent.approval.approval_id,
            request=ApprovalDecisionRequest(decision="approve", intent_digest=intent.approval.intent_digest, expected_revision=1),
            idempotency_key="invalid-event-1",
            current_session_revision=2,
            session_snapshot={},
            latest_turn={"turn_id": str(turn_id)},
        )
    assert exc_info.value.code == "EVENT_VALIDATION_FAILED"
    assert store.count_events(owner_id=owner_id) == 0
    assert approvals.get(owner_id=owner_id, approval_id=intent.approval.approval_id).approval.status == "pending"


def test_p2_http_approve_returns_event_and_episode_recovery():
    marker_id = str(uuid4())
    candidate = draft_agent(marker_id)
    store = PrototypeEventStore()
    client = TestClient(create_prototype_app(confirmation_service(marker_id, candidate), event_store=store))
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
    ).json()
    confirmation_response = client.post(
        f"/v1/agent/sessions/{session['session_id']}/confirmations",
        headers=headers,
        json={
            "turn_id": turn["turn"]["turn_id"],
            "expected_revision": 2,
            "decision": "confirm_facts",
            "reviewed_fields": [
                "locations", "sensations", "temporal", "trend",
                "aggravating_factors", "relieving_factors", "functional_impacts", "background_facts",
            ],
            "draft_digest": turn["turn"]["output"]["draft_digest"],
            "episode_selection": {"mode": "create_new", "started_on": "2026-08-05"},
        },
    )
    assert confirmation_response.status_code == 201, confirmation_response.text
    approval = confirmation_response.json()["approval"]
    decision = client.post(
        f"/v1/approvals/{approval['approval_id']}/decisions",
        headers={**headers, "Idempotency-Key": "p2-http-1"},
        json={"decision": "approve", "intent_digest": approval["intent_digest"], "expected_revision": 1},
    )
    assert decision.status_code == 200, decision.text
    body = decision.json()
    event_id = body["result_refs"][0]["id"]
    assert body["status"] == "executed"
    assert body["session_snapshot"]["episode_id"]
    event_response = client.get(f"/v1/body-signal-events/{event_id}", headers=headers)
    assert event_response.status_code == 200, event_response.text
    validate_event(event_response.json())
    episode_id = event_response.json()["episode_id"]
    episode_response = client.get(f"/v1/episodes/{episode_id}", headers=headers)
    assert episode_response.status_code == 200, episode_response.text
    episode_body = episode_response.json()
    assert episode_body["latest_event_id"] == event_id
    assert episode_body["page"] == {"next_cursor": None, "has_more": False}
    assert episode_body["event_refs"][0]["event_id"] == event_id
    assert episode_body["event_refs"][0]["content_digest"] == event_response.json()["content_digest"]
    other_user = client.get(f"/v1/body-signal-events/{event_id}", headers={"X-Prototype-User-Id": str(uuid4())})
    assert other_user.status_code == 404
