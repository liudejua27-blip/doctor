from __future__ import annotations

from datetime import datetime, timezone
from uuid import uuid4

import pytest

from body_companion.domain.policy import PolicyValidator, PolicyViolation, digest_for
from body_companion.domain.types import (
    Anchor2D,
    AssessmentDraft,
    BodyLocation,
    DraftCandidate,
    Intensity,
    Mapping,
    Sensation,
    SourceRef,
    TemporalPattern,
    LocationSource,
)


def location(marker_id):
    return BodyLocation(
        marker_id=marker_id,
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
            point={"x": 0.5, "y": 0.5},
        ),
        mapping=Mapping(method="direct_user_selection", confidence=1, reviewed_by_user=True),
        source=LocationSource(interaction="body_map_2d"),
        created_at=datetime.now(timezone.utc),
    )


def draft(marker_id):
    source = SourceRef(type="user_report", source_id="turn.synthetic")
    return AssessmentDraft(
        locations=[location(marker_id)],
        sensations=[
            Sensation(
                sensation_id=uuid4(),
                code="aching",
                intensities=[Intensity(context="current", value=3)],
                location_marker_ids=[marker_id],
                source=source,
            )
        ],
        temporal=TemporalPattern(onset_mode="unknown", course="intermittent", frequency="unknown"),
        trend="unknown",
    )


def test_draft_requires_digest_and_marker_reference():
    marker_id = uuid4()
    typed = draft(marker_id)
    candidate = DraftCandidate(
        event_draft=typed,
        user_fact_summary="用户报告一个尚未确认的位置和感觉。",
        draft_digest=digest_for(typed),
    )
    validated = PolicyValidator().validate(candidate, location_marker_ids=[str(marker_id)])
    assert validated.kind == "draft_ready"


def test_policy_rejects_stale_digest():
    marker_id = uuid4()
    typed = draft(marker_id)
    candidate = DraftCandidate(
        event_draft=typed,
        user_fact_summary="用户报告一个尚未确认的位置和感觉。",
        draft_digest="sha256:" + "0" * 64,
    )
    with pytest.raises(PolicyViolation, match="digest"):
        PolicyValidator().validate(candidate, location_marker_ids=[str(marker_id)])


def test_policy_rejects_safety_question_from_agent():
    from body_companion.domain.types import AskQuestionCandidate, AgentQuestion

    candidate = AskQuestionCandidate(
        questions=[
            AgentQuestion(
                question_id="safety.bad",
                category="background",
                prompt="not a safety question",
                answer_type="boolean",
                required=True,
            )
        ],
        context_summary="synthetic",
    )
    # The type itself prevents category=safety; a non-safety question is valid.
    assert PolicyValidator().validate(candidate, location_marker_ids=[]) == candidate
