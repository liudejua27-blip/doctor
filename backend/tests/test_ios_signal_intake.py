from __future__ import annotations

from datetime import datetime, timezone
from uuid import UUID, uuid4

import pytest

from body_companion.domain.ios_signal_intake import (
    IOSClientSafetyState,
    IOSSignalBackgroundFact,
    IOSSignalFacts,
    IOSSignalFactor,
    IOSSignalFunctionalImpact,
    IOSSignalIntakeDraft,
    IOSSignalIntakeAdapterResult,
    IOSSignalIntensity,
    IOSSignalSensation,
    IOSSignalTemporal,
    adapt_ios_signal_intake,
)
from body_companion.domain.policy import PolicyValidator, digest_for
from body_companion.domain.types import (
    Anchor2D,
    BodyLocation,
    DraftCandidate,
    Mapping,
    SafetyEvaluation,
    LocationSource,
)


SESSION_ID = UUID("5dfe5e17-8e10-4b63-86da-09e78b66cf1b")


def make_location(marker_id: UUID | None = None, *, reviewed: bool = True) -> BodyLocation:
    return BodyLocation(
        marker_id=marker_id or uuid4(),
        region_id="body.knee.general",
        ontology_version="body-ontology-test",
        laterality="left",
        surface="anterior",
        depth="unspecified",
        shape="point",
        anchor_2d=Anchor2D(
            asset_id="body-2d-test",
            asset_version="1",
            view="front",
            point={"x": 0.4, "y": 0.6},
        ),
        mapping=Mapping(method="direct_user_selection", confidence=1, reviewed_by_user=reviewed),
        source=LocationSource(interaction="body_map_2d"),
        created_at=datetime.now(timezone.utc),
    )


def make_payload(
    *,
    session_id: UUID = SESSION_ID,
    revision: int = 2,
    marker_id: UUID | None = None,
    client_safety: IOSClientSafetyState | None = None,
    phase: str = "safety_review",
    raw_user_text: str | None = "合成测试原话，不应出现在适配结果。",
) -> IOSSignalIntakeDraft:
    location = make_location(marker_id)
    marker = location.marker_id
    return IOSSignalIntakeDraft(
        session_id=session_id,
        draft_revision=revision,
        phase=phase,
        locations=[location],
        facts=IOSSignalFacts(
            sensations=[
                IOSSignalSensation(
                    sensation_id=uuid4(),
                    code="tightness",
                    location_marker_ids=[marker],
                    source="user",
                    status="user_entered",
                )
            ],
            intensity=IOSSignalIntensity(context="current", value=4, source="user", status="user_entered"),
            temporal=IOSSignalTemporal(
                onset_mode="gradual",
                course="intermittent",
                user_text="最近几天",
                source="user",
                status="user_entered",
            ),
            functional_impacts=[
                IOSSignalFunctionalImpact(
                    impact_id=uuid4(),
                    domain="training",
                    severity="mild",
                    source="user",
                    status="user_entered",
                )
            ],
            raw_user_text=raw_user_text,
        ),
        safety=client_safety or IOSClientSafetyState(status="not_run", ordinary_agent_allowed=False),
        reviewed_groups=["sensation", "intensity", "temporal", "functional_impact"],
        updated_at=datetime.now(timezone.utc),
    )


def server_safety(*, tier: str = "R2", no_rule: bool = False, ordinary: bool = True) -> SafetyEvaluation:
    if no_rule:
        tier = "R3"
        outcome = "no_rule_triggered"
        triggered_ids: list[str] = []
    else:
        outcome = "triggered"
        triggered_ids = ["prototype.r2"]
    return SafetyEvaluation(
        status="complete",
        tier=tier,  # type: ignore[arg-type]
        rule_outcome=outcome,  # type: ignore[arg-type]
        triggered_rule_ids=triggered_ids,
        required_question_ids=[],
        rule_set_version="test-rules-1",
        all_current_rules_executed=True,
        scenario_support="supported",
        unresolved_safety=False,
        ordinary_agent_allowed=ordinary,
        answers=[],
        rule_hits=[],
        required_action_code=None,
        evaluated_at=datetime.now(timezone.utc),
    )


def test_missing_server_safety_never_returns_agent_draft():
    payload = make_payload(
        client_safety=IOSClientSafetyState(
            status="no_rule_triggered",
            ordinary_agent_allowed=True,
            display_message="当前回答未触发已审核规则（不等于安全）",
        )
    )

    result = adapt_ios_signal_intake(
        payload,
        expected_session_id=SESSION_ID,
        expected_draft_revision=2,
    )

    assert result.status == "needs_safety_precheck"
    assert result.assessment_draft is None


def test_server_r2_maps_typed_draft_and_policy_accepts_it():
    result = adapt_ios_signal_intake(
        make_payload(),
        expected_session_id=SESSION_ID,
        expected_draft_revision=2,
        server_safety=server_safety(),
    )

    assert result.status == "ready_for_agent"
    draft = result.assessment_draft
    assert draft is not None
    assert draft.trend == "unknown"
    assert draft.sensations[0].location_marker_ids == [draft.locations[0].marker_id]
    assert draft.sensations[0].source.type == "user_report"
    assert draft.sensations[0].intensities[0].source is not None
    assert draft.temporal.source is not None

    candidate = DraftCandidate(
        event_draft=draft,
        user_fact_summary="合成测试候选",
        draft_digest=digest_for(draft),
    )
    assert PolicyValidator().validate(candidate, location_marker_ids=[str(draft.locations[0].marker_id)]) == candidate


def test_no_rule_triggered_server_result_is_ready_without_safety_claim():
    payload = make_payload(
        client_safety=IOSClientSafetyState(
            status="no_rule_triggered",
            ordinary_agent_allowed=True,
            display_message="当前回答未触发已审核规则（不等于安全）",
        )
    )
    result = adapt_ios_signal_intake(
        payload,
        expected_session_id=SESSION_ID,
        expected_draft_revision=2,
        server_safety=server_safety(no_rule=True),
    )
    assert result.status == "ready_for_agent"
    assert result.server_safety_tier == "R3"


@pytest.mark.parametrize(
    ("tier", "expected"),
    [("R0", "safety_action_required"), ("R1", "safety_action_required"), ("undetermined", "safety_action_required")],
)
def test_server_high_risk_or_undetermined_never_returns_agent_draft(tier: str, expected: str):
    result = adapt_ios_signal_intake(
        make_payload(),
        expected_session_id=SESSION_ID,
        expected_draft_revision=2,
        server_safety=server_safety(tier=tier, ordinary=False),
    )
    assert result.status == expected
    assert result.assessment_draft is None


def test_session_and_revision_are_server_authoritative():
    stale_session = adapt_ios_signal_intake(
        make_payload(),
        expected_session_id=uuid4(),
        expected_draft_revision=2,
    )
    stale_revision = adapt_ios_signal_intake(
        make_payload(),
        expected_session_id=SESSION_ID,
        expected_draft_revision=3,
    )
    assert stale_session.status == "rejected"
    assert stale_session.error_code == "INTAKE_SESSION_MISMATCH"
    assert stale_revision.status == "rejected"
    assert stale_revision.error_code == "INTAKE_REVISION_MISMATCH"


def test_unknown_required_sensation_becomes_explicit_unknown_without_inference():
    payload = make_payload()
    payload.facts.sensations = []
    payload.reviewed_groups.append("location")
    payload.unknown_groups.append("sensation")
    result = adapt_ios_signal_intake(
        payload,
        expected_session_id=SESSION_ID,
        expected_draft_revision=2,
        server_safety=server_safety(),
    )
    assert result.status == "ready_for_agent"
    assert result.assessment_draft is not None
    assert result.assessment_draft.sensations[0].code == "unknown"
    assert result.assessment_draft.trend == "unknown"


def test_unknown_or_unreviewed_required_group_is_rejected():
    payload = make_payload()
    payload.facts.intensity = None
    result = adapt_ios_signal_intake(
        payload,
        expected_session_id=SESSION_ID,
        expected_draft_revision=2,
        server_safety=server_safety(),
    )
    assert result.status == "rejected"
    assert result.error_code == "INTAKE_INTENSITY_REQUIRED"


def test_marker_relation_is_not_inferred_or_copied():
    payload = make_payload()
    payload.facts.sensations[0].location_marker_ids = [uuid4()]
    result = adapt_ios_signal_intake(
        payload,
        expected_session_id=SESSION_ID,
        expected_draft_revision=2,
        server_safety=server_safety(),
    )
    assert result.status == "rejected"
    assert result.error_code == "INTAKE_SENSATION_LOCATION_MISMATCH"


def test_duplicate_location_markers_are_rejected():
    payload = make_payload()
    payload.locations.append(payload.locations[0])
    result = adapt_ios_signal_intake(
        payload,
        expected_session_id=SESSION_ID,
        expected_draft_revision=2,
    )
    assert result.status == "rejected"
    assert result.error_code == "INTAKE_LOCATION_DUPLICATE"


def test_agent_candidate_and_background_status_remain_unconfirmed():
    payload = make_payload()
    payload.facts.sensations[0].source = "agent_candidate"
    payload.facts.sensations[0].status = "candidate"
    payload.facts.background_facts = [
        IOSSignalBackgroundFact(
            fact_id=uuid4(),
            category="activity_change",
            value="合成测试负荷变化",
            source="agent_candidate",
            status="candidate",
        )
    ]
    result = adapt_ios_signal_intake(
        payload,
        expected_session_id=SESSION_ID,
        expected_draft_revision=2,
        server_safety=server_safety(),
    )
    assert result.assessment_draft is not None
    assert result.assessment_draft.sensations[0].source.type == "agent_inference"
    assert result.assessment_draft.background_facts[0].status == "candidate"


@pytest.mark.parametrize("source", ["profile", "system"])
def test_unauthorized_or_system_sources_fail_closed(source: str):
    payload = make_payload()
    payload.facts.sensations[0].source = source  # type: ignore[assignment]
    payload.facts.sensations[0].status = "candidate"
    result = adapt_ios_signal_intake(
        payload,
        expected_session_id=SESSION_ID,
        expected_draft_revision=2,
    )
    assert result.status == "rejected"
    assert result.error_code in {"INTAKE_PROFILE_SOURCE_REF_REQUIRED", "INTAKE_SYSTEM_FACT_SOURCE_FORBIDDEN"}


def test_raw_user_text_is_not_in_result_or_error():
    secret = "合成原话-不应进入结果-健康内容"
    result = adapt_ios_signal_intake(
        make_payload(raw_user_text=secret),
        expected_session_id=SESSION_ID,
        expected_draft_revision=2,
        server_safety=server_safety(),
    )
    serialized = result.model_dump_json()
    assert secret not in serialized
    assert "event_id" not in serialized
    assert "approval_id" not in serialized
    assert "episode_id" not in serialized
    assert "user_id" not in serialized


def test_unknown_fields_are_rejected_without_migration():
    raw = make_payload().model_dump(mode="json")
    raw["unexpected_field"] = True
    result = adapt_ios_signal_intake(raw, expected_session_id=SESSION_ID, expected_draft_revision=2)
    assert result.status == "rejected"
    assert result.error_code == "INTAKE_INVALID_PAYLOAD"


def test_result_schema_cannot_carry_draft_for_non_ready_status():
    with pytest.raises(ValueError):
        IOSSignalIntakeAdapterResult(
            session_id=SESSION_ID,
            draft_revision=2,
            status="ready_for_agent",
            client_safety_status="no_rule_triggered",
            server_safety_tier="R3",
            assessment_draft=None,
        )


def test_repeated_unknown_mapping_is_deterministic():
    payload = make_payload()
    payload.facts.sensations = []
    payload.unknown_groups.append("sensation")
    first = adapt_ios_signal_intake(
        payload,
        expected_session_id=SESSION_ID,
        expected_draft_revision=2,
        server_safety=server_safety(),
    )
    second = adapt_ios_signal_intake(
        payload,
        expected_session_id=SESSION_ID,
        expected_draft_revision=2,
        server_safety=server_safety(),
    )
    assert first.model_dump(mode="json") == second.model_dump(mode="json")
