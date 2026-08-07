"""Strongly typed domain objects for the Phase 1 prototype.

The models intentionally keep candidate facts, safety results and application
output in separate types. They are stricter than the API transport and reject
unknown fields so a model cannot smuggle a medical or persistence field into a
draft.
"""

from __future__ import annotations

from datetime import date as Date, datetime, timezone
from typing import Annotated, Any, Literal, Union
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", validate_assignment=True)


Laterality = Literal["left", "right", "midline", "bilateral", "unspecified"]
BodySurface = Literal[
    "anterior",
    "posterior",
    "medial",
    "lateral",
    "superior",
    "inferior",
    "circumferential",
    "unspecified",
]
BodyDepth = Literal["superficial", "deep", "joint_nearby", "unspecified"]
BodyShape = Literal["point", "area", "path"]
SourceType = Literal[
    "user_report",
    "confirmed_profile",
    "confirmed_event",
    "device_summary",
    "uploaded_document",
    "professional_record",
    "agent_inference",
]


class Point2D(StrictModel):
    x: float = Field(ge=0, le=1)
    y: float = Field(ge=0, le=1)


class Point3D(StrictModel):
    x: float
    y: float
    z: float


class Anchor2D(StrictModel):
    asset_id: str = Field(min_length=1, max_length=100)
    asset_version: str = Field(min_length=1, max_length=40)
    view: Literal["front", "back"]
    point: Point2D | None = None
    path: list[Point2D] | None = Field(default=None, min_length=2, max_length=256)
    region_mask_id: str | None = Field(default=None, min_length=1, max_length=120)

    @model_validator(mode="after")
    def require_surface_reference(self) -> "Anchor2D":
        if self.point is None and self.path is None and self.region_mask_id is None:
            raise ValueError("anchor_2d requires point, path, or region_mask_id")
        return self


class Barycentric(StrictModel):
    u: float = Field(ge=0, le=1)
    v: float = Field(ge=0, le=1)
    w: float = Field(ge=0, le=1)

    @model_validator(mode="after")
    def validate_sum(self) -> "Barycentric":
        if abs(self.u + self.v + self.w - 1) > 1e-4:
            raise ValueError("barycentric components must sum to 1")
        return self


class UV(StrictModel):
    u: float = Field(ge=0, le=1)
    v: float = Field(ge=0, le=1)


class Anchor3D(StrictModel):
    entity_id: str = Field(min_length=1, max_length=160)
    mesh_id: str | None = Field(default=None, min_length=1, max_length=160)
    local_position: Point3D
    local_normal: Point3D
    triangle_index: int | None = Field(default=None, ge=0)
    barycentric: Barycentric | None = None
    uv: UV | None = None

    @model_validator(mode="after")
    def validate_barycentric(self) -> "Anchor3D":
        if self.barycentric is not None:
            if self.triangle_index is None:
                raise ValueError("triangle_index is required with barycentric")
        elif self.triangle_index is not None:
            raise ValueError("barycentric is required with triangle_index")
        return self


class ModelAsset(StrictModel):
    asset_id: str = Field(min_length=1, max_length=100)
    asset_version: str = Field(min_length=1, max_length=40)
    variant: Literal["default_neutral", "professional_muscle_joint"]
    coordinate_convention: Literal["realitykit_y_up_right_handed"]


class Mapping(StrictModel):
    method: Literal[
        "direct_user_selection",
        "asset_region_map",
        "cross_asset_migration",
        "agent_normalization",
        "manual_review",
    ]
    confidence: float = Field(ge=0, le=1)
    reviewed_by_user: bool
    migration_id: str | None = Field(default=None, min_length=1, max_length=100)


class LocationSource(StrictModel):
    interaction: Literal[
        "body_map_2d",
        "body_map_3d",
        "body_part_search",
        "document_import",
        "agent_normalization",
    ]
    source_turn_id: UUID | None = None
    source_document_id: UUID | None = None


class BodyLocation(StrictModel):
    marker_id: UUID
    region_id: str = Field(pattern=r"^body\.[a-z0-9_]+(?:\.[a-z0-9_]+)+$", max_length=120)
    ontology_version: str = Field(pattern=r"^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$")
    laterality: Laterality
    surface: BodySurface
    depth: BodyDepth
    shape: BodyShape
    user_label: str | None = Field(default=None, min_length=1, max_length=200)
    anchor_2d: Anchor2D | None = None
    anchor_3d: Anchor3D | None = None
    model_asset: ModelAsset | None = None
    mapping: Mapping
    source: LocationSource
    created_at: datetime

    @model_validator(mode="after")
    def validate_asset_coupling(self) -> "BodyLocation":
        if self.anchor_3d is not None and self.model_asset is None:
            raise ValueError("model_asset is required when anchor_3d is present")
        if self.anchor_3d is None and self.model_asset is not None:
            raise ValueError("model_asset is only valid with anchor_3d")
        if self.shape == "path" and (self.anchor_2d is None or self.anchor_2d.path is None):
            raise ValueError("path shape requires a 2D path anchor")
        if self.shape == "point" and not (
            (self.anchor_2d is not None and self.anchor_2d.point is not None) or self.anchor_3d is not None
        ):
            raise ValueError("point shape requires a 2D point or 3D anchor")
        if self.source.interaction == "body_map_2d" and self.anchor_2d is None:
            raise ValueError("2D body-map source requires a 2D anchor")
        if self.source.interaction == "body_map_3d" and (self.anchor_3d is None or self.model_asset is None):
            raise ValueError("3D body-map source requires an anchor and model asset")
        if self.source.interaction == "document_import" and self.source.source_document_id is None:
            raise ValueError("document source requires source_document_id")
        if self.source.interaction == "agent_normalization" and self.source.source_turn_id is None:
            raise ValueError("Agent-normalized source requires source_turn_id")
        if self.mapping.method == "cross_asset_migration" and self.mapping.migration_id is None:
            raise ValueError("cross-asset mapping requires migration_id")
        return self


class EpisodeSelection(StrictModel):
    """The user's explicit Episode target choice before event approval."""

    mode: Literal["create_new", "join_existing", "reopen_existing"]
    episode_id: UUID | None = None
    expected_revision: int | None = Field(default=None, ge=1)
    title: str | None = Field(default=None, min_length=1, max_length=200)
    started_on: Date | None = None

    @model_validator(mode="after")
    def validate_target(self) -> "EpisodeSelection":
        if self.mode == "create_new":
            if self.episode_id is not None or self.expected_revision is not None:
                raise ValueError("create_new cannot carry an existing Episode target")
            if self.started_on is None:
                raise ValueError("create_new requires a user-provided started_on")
            if self.title is not None and any(
                term in self.title.casefold() for term in ("诊断", "鉴别诊断", "疾病", "处方", "治疗", "diagnosis", "prescription")
            ):
                raise ValueError("Episode title must remain non-diagnostic")
            return self
        if self.episode_id is None or self.expected_revision is None:
            raise ValueError("existing Episode selection requires id and revision")
        if self.title is not None or self.started_on is not None:
            raise ValueError("existing Episode selection cannot carry create-new fields")
        return self


class SourceRef(StrictModel):
    type: SourceType
    source_id: str = Field(min_length=1, max_length=240)
    observed_at: datetime | None = None
    confidence: float | None = Field(default=None, ge=0, le=1)


class ApproximateDateTime(StrictModel):
    value: datetime | None = None
    date: Date | None = None
    precision: Literal["exact", "hour", "day", "week", "month", "approximate", "unknown"]
    user_text: str | None = Field(default=None, min_length=1, max_length=200)

    @model_validator(mode="after")
    def validate_precision(self) -> "ApproximateDateTime":
        if self.value is not None and self.date is not None:
            raise ValueError("value and date are mutually exclusive")
        if self.precision in {"exact", "hour"} and self.value is None:
            raise ValueError("exact/hour precision requires value")
        if self.precision in {"day", "week", "month"} and self.date is None:
            raise ValueError("day/week/month precision requires date")
        if self.precision in {"approximate", "unknown"} and not self.user_text:
            raise ValueError("approximate/unknown precision requires user_text")
        if self.precision == "unknown" and (self.value is not None or self.date is not None):
            raise ValueError("unknown precision cannot carry a date anchor")
        return self


class MeasurementWindow(StrictModel):
    start: ApproximateDateTime | None = None
    end: ApproximateDateTime | None = None
    duration_minutes: int | None = Field(default=None, ge=1, le=525600)
    label: str | None = Field(default=None, min_length=1, max_length=200)

    @model_validator(mode="after")
    def validate_window(self) -> "MeasurementWindow":
        if not ((self.start is not None and self.end is not None) or self.duration_minutes or self.label):
            raise ValueError("a measurement window needs start/end, duration, or label")
        return self


class Intensity(StrictModel):
    context: Literal["current", "peak", "rest", "during_activity", "after_activity"]
    value: int = Field(ge=0, le=10)
    scale_min: Literal[0] = 0
    scale_max: Literal[10] = 10
    window: MeasurementWindow | None = None
    source: SourceRef | None = None

    @model_validator(mode="after")
    def validate_peak_window(self) -> "Intensity":
        if self.context == "peak" and self.window is None:
            raise ValueError("peak intensity requires a measurement window")
        return self


SensationCode = Literal[
    "aching",
    "dull_pain",
    "sharp_pain",
    "stabbing",
    "throbbing",
    "tenderness",
    "pressure",
    "burning",
    "electric",
    "radiating",
    "tingling",
    "numbness",
    "reduced_sensation",
    "tightness",
    "stiffness",
    "cramping",
    "catching",
    "clicking",
    "weakness",
    "instability",
    "giving_way",
    "movement_fear",
    "swelling",
    "redness",
    "warmth",
    "bruising",
    "itching",
    "fatigue",
    "heaviness",
    "post_activity_soreness",
    "other",
    "unknown",
]


class Sensation(StrictModel):
    sensation_id: UUID
    code: SensationCode
    user_label: str | None = Field(default=None, min_length=1, max_length=200)
    intensities: list[Intensity] = Field(default_factory=list, max_length=5)
    location_marker_ids: list[UUID] = Field(min_length=1, max_length=20)
    source: SourceRef

    @model_validator(mode="after")
    def require_other_label(self) -> "Sensation":
        if self.code == "other" and not self.user_label:
            raise ValueError("other sensation requires user_label")
        if len(set(self.location_marker_ids)) != len(self.location_marker_ids):
            raise ValueError("location_marker_ids must be unique")
        return self


FactorCategory = Literal["activity", "posture", "load", "time", "sleep", "rest", "environment", "other"]


class Factor(StrictModel):
    factor_id: UUID
    category: FactorCategory
    code: str | None = Field(default=None, pattern=r"^[a-z0-9_]{1,80}$")
    label: str = Field(min_length=1, max_length=200)
    reported_effect: Literal["worse", "better", "no_change", "uncertain"]
    reproducible: Literal["yes", "no", "uncertain", "not_checked"] | None = None
    source: SourceRef


class AggravatingFactor(Factor):
    reported_effect: Literal["worse", "uncertain"]


class RelievingFactor(Factor):
    reported_effect: Literal["better", "uncertain"]


class FunctionalImpact(StrictModel):
    domain: Literal[
        "sleep",
        "sitting",
        "standing",
        "walking",
        "running",
        "stairs",
        "lifting",
        "work",
        "training",
        "self_care",
        "other",
    ]
    severity: Literal["none", "mild", "moderate", "severe", "unable", "unknown"]
    user_text: str | None = Field(default=None, max_length=500)
    source: SourceRef


class BackgroundFact(StrictModel):
    fact_id: UUID
    category: Literal[
        "activity_change",
        "specific_incident",
        "work_context",
        "prior_same_region_issue",
        "surgery_history",
        "medication_context",
        "health_context",
        "other",
    ]
    value: str = Field(min_length=1, max_length=1000)
    status: Literal["user_confirmed", "candidate", "conflicting", "outdated"]
    source: SourceRef
    observed_at: ApproximateDateTime


class TemporalPattern(StrictModel):
    onset: ApproximateDateTime | None = None
    onset_mode: Literal["sudden", "gradual", "after_specific_event", "unknown"]
    course: Literal["continuous", "intermittent", "recurrent", "single_occurrence", "unknown"]
    frequency: Literal[
        "constant",
        "multiple_times_daily",
        "daily",
        "several_times_weekly",
        "weekly_or_less",
        "activity_specific",
        "unknown",
    ]
    typical_duration_minutes: int | None = Field(default=None, ge=0, le=525600)
    time_of_day: list[Literal["morning", "daytime", "evening", "night", "during_sleep", "unknown"]] = Field(
        default_factory=list,
        max_length=6,
    )
    user_text: str | None = Field(default=None, max_length=500)
    source: SourceRef | None = None


class AssessmentDraft(StrictModel):
    """The only candidate body-event object an Agent may return."""

    schema_version: Literal["1.0"] = "1.0"
    locations: list[BodyLocation] = Field(min_length=1, max_length=20)
    sensations: list[Sensation] = Field(min_length=1, max_length=20)
    temporal: TemporalPattern
    trend: Literal["improving", "stable", "worsening", "fluctuating", "unknown"]
    aggravating_factors: list[AggravatingFactor] = Field(default_factory=list, max_length=30)
    relieving_factors: list[RelievingFactor] = Field(default_factory=list, max_length=30)
    functional_impacts: list[FunctionalImpact] = Field(default_factory=list, max_length=30)
    background_facts: list[BackgroundFact] = Field(default_factory=list, max_length=50)


class QuestionChoice(StrictModel):
    value: str = Field(min_length=1, max_length=120)
    label: str = Field(min_length=1, max_length=200)


class AgentQuestion(StrictModel):
    question_id: str = Field(pattern=r"^[A-Za-z0-9._-]{1,120}$")
    category: Literal["location", "sensation", "intensity", "time", "trigger", "impact", "background", "episode"]
    prompt: str = Field(min_length=1, max_length=500)
    answer_type: Literal["boolean", "single_choice", "multiple_choice", "integer_scale", "free_text"]
    required: bool
    choices: list[QuestionChoice] | None = Field(default=None, max_length=20)
    why_asked: str | None = Field(default=None, max_length=300)

    @model_validator(mode="after")
    def validate_choices(self) -> "AgentQuestion":
        if self.answer_type in {"single_choice", "multiple_choice"} and not self.choices:
            raise ValueError("choice question requires choices")
        if self.answer_type not in {"single_choice", "multiple_choice"} and self.choices is not None:
            raise ValueError("non-choice question cannot carry choices")
        return self


class AskQuestionCandidate(StrictModel):
    kind: Literal["ask_question"] = "ask_question"
    questions: list[AgentQuestion] = Field(min_length=1, max_length=20)
    context_summary: str = Field(min_length=1, max_length=1000)


class DraftCandidate(StrictModel):
    kind: Literal["draft_ready"] = "draft_ready"
    event_draft: AssessmentDraft
    user_fact_summary: str = Field(min_length=1, max_length=2000)
    uncertainties: list[str] = Field(default_factory=list, max_length=20)
    draft_digest: str = Field(pattern=r"^sha256:[a-f0-9]{64}$")


AgentCandidate = Annotated[Union[AskQuestionCandidate, DraftCandidate], Field(discriminator="kind")]


class SafetyAnswer(StrictModel):
    question_id: str = Field(pattern=r"^[A-Za-z0-9._-]{1,120}$")
    answer_type: Literal["boolean", "single_choice", "multiple_choice"]
    answer_state: Literal["answered", "unknown", "declined"]
    boolean_value: bool | None = None
    choice_values: list[str] | None = Field(default=None, max_length=20)
    raw_text: str | None = Field(default=None, max_length=500)
    answered_at: datetime


SafetyTier = Literal["R0", "R1", "R2", "R3", "undetermined"]
SafetyStatus = Literal["complete", "incomplete", "unavailable"]
SafetyOutcome = Literal["triggered", "no_rule_triggered", "unresolved", "unavailable"]


class RuleHit(StrictModel):
    rule_id: str = Field(pattern=r"^[A-Za-z0-9._-]{1,120}$")
    result: Literal["matched", "not_matched", "undetermined"]
    tier: Literal["R0", "R1", "R2", "R3"] | None = None
    evidence_refs: list[str] = Field(default_factory=list, max_length=50)


class SafetyEvaluation(StrictModel):
    status: SafetyStatus
    tier: SafetyTier
    rule_outcome: SafetyOutcome
    triggered_rule_ids: list[str] = Field(default_factory=list, max_length=50)
    required_question_ids: list[str] = Field(default_factory=list, max_length=50)
    rule_set_version: str = Field(min_length=1, max_length=64)
    all_current_rules_executed: bool
    scenario_support: Literal["supported", "unsupported"]
    unresolved_safety: bool
    ordinary_agent_allowed: bool
    answers: list[SafetyAnswer] = Field(default_factory=list, max_length=50)
    rule_hits: list[RuleHit] = Field(default_factory=list, max_length=50)
    required_action_code: str | None = Field(default=None, max_length=120)
    content_id: str | None = Field(default=None, max_length=160)
    content_release_id: str | None = Field(default=None, max_length=64)
    display_message: str | None = Field(default=None, max_length=2000)
    evaluated_at: datetime

    @model_validator(mode="after")
    def validate_gate_invariants(self) -> "SafetyEvaluation":
        if self.status == "complete":
            if not self.all_current_rules_executed or self.unresolved_safety or self.required_question_ids:
                raise ValueError("complete gate must have all rules executed and no unresolved questions")
        if self.status == "incomplete":
            if self.all_current_rules_executed is True or not self.unresolved_safety or not self.required_question_ids:
                raise ValueError("incomplete gate must require safety questions")
        if self.status == "unavailable":
            if self.all_current_rules_executed or not self.unresolved_safety or self.required_question_ids:
                raise ValueError("unavailable gate cannot claim executed rules or require rule questions")
        if self.ordinary_agent_allowed and not (
            self.status == "complete"
            and self.tier in {"R2", "R3"}
            and self.scenario_support == "supported"
            and not self.unresolved_safety
        ):
            raise ValueError("ordinary Agent is allowed only for a complete supported R2/R3 gate")
        if self.tier in {"R0", "R1", "undetermined"} and self.ordinary_agent_allowed:
            raise ValueError("ordinary Agent cannot run for R0/R1/undetermined")
        if self.rule_outcome == "no_rule_triggered" and (
            self.tier != "R3" or self.triggered_rule_ids or not self.all_current_rules_executed
        ):
            raise ValueError("no_rule_triggered must be complete R3 with no triggered IDs")
        if self.rule_outcome == "unavailable" and self.status != "unavailable":
            raise ValueError("unavailable rule outcome requires unavailable status")
        return self


class SafetyEnvelope(StrictModel):
    mode: Literal["emergency", "urgent", "normal", "manual", "unsupported", "degraded"]
    confirmed_facts: list[dict[str, Any]] = Field(default_factory=list, max_length=100)
    unconfirmed_items: list[dict[str, str]] = Field(default_factory=list, max_length=100)
    safety: dict[str, Any]
    possible_contributors: list[dict[str, Any]] = Field(default_factory=list, max_length=20)
    next_steps: list[dict[str, Any]] = Field(default_factory=list, max_length=20)
    data_sources_used: list[str] = Field(default_factory=list, max_length=100)
    uncertainty_statement_id: str = Field(min_length=1, max_length=120)
    ai_identity_label_id: str = Field(min_length=1, max_length=120)
    safetyBaselineId: str = Field(min_length=1, max_length=120)


class UserTurnInput(StrictModel):
    modality: Literal["text", "voice_transcript", "body_map", "mixed", "structured_answer"]
    text: str | None = Field(default=None, min_length=1, max_length=8000)
    language: str | None = Field(default=None, pattern=r"^[a-z]{2,3}(?:-[A-Z]{2})?$")
    locations: list[BodyLocation] | None = Field(default=None, min_length=1, max_length=1)
    question_answers: list[dict[str, Any]] | None = Field(default=None, min_length=1, max_length=50)
    temporary_source_refs: list[str] = Field(default_factory=list, max_length=10)
    in_reply_to_turn_id: UUID | None = None
    submitted_at: datetime

    @model_validator(mode="after")
    def validate_modality(self) -> "UserTurnInput":
        if self.modality in {"text", "voice_transcript"} and not self.text:
            raise ValueError("text modality requires text")
        if self.modality == "body_map" and not self.locations:
            raise ValueError("body_map modality requires locations")
        if self.modality == "structured_answer" and not (self.question_answers and self.in_reply_to_turn_id):
            raise ValueError("structured_answer requires question answers and predecessor turn")
        return self


class AgentVersions(StrictModel):
    pydantic_ai_version: Literal["2.23.0"] = "2.23.0"
    agent_version: str = Field(min_length=1, max_length=64)
    output_schema_version: Literal["1.0"] = "1.0"
    ontology_version: str = Field(min_length=1, max_length=64)
    rule_set_version: str = Field(min_length=1, max_length=64)
    prompt_version: str | None = Field(default=None, max_length=64)
    provider: str | None = Field(default=None, max_length=80)
    model_name: str | None = Field(default=None, max_length=160)


def utc_now() -> datetime:
    return datetime.now(timezone.utc)
