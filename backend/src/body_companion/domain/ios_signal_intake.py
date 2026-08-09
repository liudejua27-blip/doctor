"""Strict server-side adapter for the iOS P1D signal-intake projection.

The adapter is intentionally not an API endpoint and never writes an Event,
Episode or Approval.  It parses the client projection, preserves typed source
boundaries, and only exposes an ``AssessmentDraft`` after the application
service supplies a fresh server-side safety evaluation.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Literal, Mapping, Any
from uuid import UUID, uuid5

from pydantic import Field, ValidationError, model_validator

from .types import (
    AggravatingFactor,
    ApproximateDateTime,
    AssessmentDraft,
    BackgroundFact,
    BodyLocation,
    FunctionalImpact,
    Intensity,
    RelievingFactor,
    Sensation,
    SensationCode,
    SourceRef,
    StrictModel,
    SafetyEvaluation,
    TemporalPattern,
)


IOSSignalIntakePhase = Literal[
    "choosing_location",
    "collecting_facts",
    "safety_review",
    "safety_action",
    "agent_draft",
    "review_facts",
    "awaiting_approval",
    "offline_draft",
    "failed",
]
IOSFactGroup = Literal[
    "location",
    "sensation",
    "intensity",
    "temporal",
    "aggravating_factors",
    "relieving_factors",
    "functional_impact",
    "background",
]
IOSFactSource = Literal["user", "agent_candidate", "profile", "system"]
IOSFactStatus = Literal["user_entered", "candidate", "reviewed", "unknown"]
IOSSafetyStatus = Literal[
    "not_run",
    "no_rule_triggered",
    "r0",
    "r1",
    "r2",
    "undetermined",
    "unavailable",
]


class IOSSignalIntakeAdapterError(ValueError):
    """A safe, non-content-bearing rejection from the adapter."""

    def __init__(self, code: str) -> None:
        self.code = code
        super().__init__(code)


class IOSSignalSensation(StrictModel):
    sensation_id: UUID
    code: SensationCode
    user_label: str | None = Field(default=None, min_length=1, max_length=200)
    location_marker_ids: list[UUID] = Field(min_length=1, max_length=20)
    source: IOSFactSource
    status: IOSFactStatus

    @model_validator(mode="after")
    def validate_ids_and_label(self) -> "IOSSignalSensation":
        if len(set(self.location_marker_ids)) != len(self.location_marker_ids):
            raise ValueError("location_marker_ids must be unique")
        if self.code == "other" and not self.user_label:
            raise ValueError("other sensation requires user_label")
        return self


class IOSSignalIntensity(StrictModel):
    context: Literal["current", "peak", "rest", "during_activity", "after_activity"]
    value: int = Field(ge=0, le=10)
    source: IOSFactSource
    status: IOSFactStatus


class IOSSignalTemporal(StrictModel):
    onset_mode: Literal["sudden", "gradual", "after_specific_event", "unknown"]
    course: Literal["continuous", "intermittent", "recurrent", "single_occurrence", "unknown"]
    user_text: str | None = Field(default=None, max_length=500)
    source: IOSFactSource
    status: IOSFactStatus


class IOSSignalFactor(StrictModel):
    factor_id: UUID
    label: str = Field(min_length=1, max_length=200)
    effect: Literal["worse", "better", "uncertain"]
    source: IOSFactSource
    status: IOSFactStatus


class IOSSignalFunctionalImpact(StrictModel):
    impact_id: UUID
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
    source: IOSFactSource
    status: IOSFactStatus


class IOSSignalBackgroundFact(StrictModel):
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
    source: IOSFactSource
    status: IOSFactStatus


class IOSSignalFacts(StrictModel):
    sensations: list[IOSSignalSensation] = Field(default_factory=list, max_length=20)
    intensity: IOSSignalIntensity | None = None
    temporal: IOSSignalTemporal | None = None
    aggravating_factors: list[IOSSignalFactor] = Field(default_factory=list, max_length=30)
    relieving_factors: list[IOSSignalFactor] = Field(default_factory=list, max_length=30)
    functional_impacts: list[IOSSignalFunctionalImpact] = Field(default_factory=list, max_length=30)
    background_facts: list[IOSSignalBackgroundFact] = Field(default_factory=list, max_length=50)
    raw_user_text: str | None = Field(default=None, max_length=4000)


class IOSClientSafetyState(StrictModel):
    status: IOSSafetyStatus
    ordinary_agent_allowed: bool
    rule_set_version: str | None = Field(default=None, max_length=64)
    display_message: str | None = Field(default=None, max_length=500)

    @model_validator(mode="after")
    def validate_client_claim(self) -> "IOSClientSafetyState":
        expected = self.status == "no_rule_triggered"
        if self.ordinary_agent_allowed != expected:
            raise ValueError("client safety permission is inconsistent with status")
        if self.status == "no_rule_triggered" and self.display_message:
            if "安全" in self.display_message and "不等于安全" not in self.display_message:
                raise ValueError("no_rule_triggered cannot claim safety")
        return self


class IOSSignalIntakeDraft(StrictModel):
    schema_version: Literal["1.1"] = "1.1"
    session_id: UUID
    draft_revision: int = Field(ge=1)
    phase: IOSSignalIntakePhase
    locations: list[BodyLocation] = Field(max_length=20)
    facts: IOSSignalFacts
    safety: IOSClientSafetyState
    reviewed_groups: list[IOSFactGroup] = Field(default_factory=list, max_length=8)
    unknown_groups: list[IOSFactGroup] = Field(default_factory=list, max_length=8)
    last_error_code: str | None = Field(default=None, max_length=120)
    updated_at: datetime

    @model_validator(mode="after")
    def validate_group_sets(self) -> "IOSSignalIntakeDraft":
        if len(set(self.reviewed_groups)) != len(self.reviewed_groups):
            raise ValueError("reviewed_groups must be unique")
        if len(set(self.unknown_groups)) != len(self.unknown_groups):
            raise ValueError("unknown_groups must be unique")
        if not set(self.unknown_groups).issubset(self.reviewed_groups):
            raise ValueError("unknown_groups must be reviewed")
        location_ids = {location.marker_id for location in self.locations}
        if len(location_ids) != len(self.locations):
            raise ValueError("locations marker_id values must be unique")
        for sensation in self.facts.sensations:
            if not set(sensation.location_marker_ids).issubset(location_ids):
                raise ValueError("sensation references a marker outside locations")
        return self


IOSAdapterStatus = Literal[
    "needs_safety_precheck",
    "ready_for_agent",
    "safety_action_required",
    "offline_only",
    "rejected",
]


class IOSSignalIntakeAdapterResult(StrictModel):
    """Safe result envelope; raw user text and identity are intentionally absent."""

    schema_version: Literal["1.0"] = "1.0"
    session_id: UUID
    draft_revision: int = Field(ge=1)
    status: IOSAdapterStatus
    client_safety_status: IOSSafetyStatus
    server_safety_tier: Literal["R0", "R1", "R2", "R3", "undetermined"] | None = None
    assessment_draft: AssessmentDraft | None = None
    error_code: str | None = Field(default=None, pattern=r"^[A-Z0-9._-]{1,120}$")

    @model_validator(mode="after")
    def validate_result_shape(self) -> "IOSSignalIntakeAdapterResult":
        if self.status == "ready_for_agent":
            if self.assessment_draft is None or self.server_safety_tier != "R3":
                raise ValueError("ready_for_agent requires a safe server draft")
            if self.error_code is not None:
                raise ValueError("ready_for_agent cannot carry an error")
        elif self.assessment_draft is not None:
            raise ValueError("non-ready adapter result cannot carry a draft")
        if self.status == "rejected" and self.error_code is None:
            raise ValueError("rejected result requires an error code")
        return self


class IOSServerSafetyProjection(StrictModel):
    """Raw-text-free SafetyEvaluation projection for the P1F handoff."""

    status: Literal["complete", "incomplete", "unavailable"]
    tier: Literal["R0", "R1", "R2", "R3", "undetermined"]
    rule_outcome: Literal["triggered", "no_rule_triggered", "unresolved", "unavailable"]
    triggered_rule_ids: list[str] = Field(default_factory=list, max_length=50)
    required_question_ids: list[str] = Field(default_factory=list, max_length=50)
    rule_set_version: str = Field(min_length=1, max_length=64)
    all_current_rules_executed: bool
    scenario_support: Literal["supported", "unsupported"]
    unresolved_safety: bool
    ordinary_agent_allowed: bool
    required_action_code: str | None = Field(default=None, max_length=120)
    content_id: str | None = Field(default=None, max_length=160)
    content_release_id: str | None = Field(default=None, max_length=64)
    evaluated_at: datetime

    @model_validator(mode="after")
    def validate_projection(self) -> "IOSServerSafetyProjection":
        if self.status == "complete":
            if not self.all_current_rules_executed or self.unresolved_safety or self.required_question_ids:
                raise ValueError("complete safety projection must have no unresolved questions")
        if self.status == "incomplete":
            if self.all_current_rules_executed or not self.unresolved_safety or not self.required_question_ids:
                raise ValueError("incomplete safety projection must require questions")
        if self.status == "unavailable":
            if self.all_current_rules_executed or not self.unresolved_safety or self.required_question_ids:
                raise ValueError("unavailable safety projection cannot claim executed rules")
        if self.ordinary_agent_allowed and not (
            self.status == "complete"
            and self.tier == "R3"
            and self.scenario_support == "supported"
            and not self.unresolved_safety
        ):
            raise ValueError("ordinary Agent is allowed only for a complete supported R3 projection")
        if self.tier in {"R0", "R1", "R2", "undetermined"} and self.ordinary_agent_allowed:
            raise ValueError("ordinary Agent cannot run for R0/R1/R2/undetermined projection")
        if self.rule_outcome == "no_rule_triggered" and (
            self.tier != "R3" or self.triggered_rule_ids or not self.all_current_rules_executed
        ):
            raise ValueError("no_rule_triggered must be complete R3 with no triggered IDs")
        if self.rule_outcome == "unavailable" and self.status != "unavailable":
            raise ValueError("unavailable rule outcome requires unavailable status")
        return self

    @classmethod
    def from_evaluation(cls, evaluation: SafetyEvaluation) -> "IOSServerSafetyProjection":
        """Project a validated evaluation without answers, rule evidence or display text."""

        return cls(
            status=evaluation.status,
            tier=evaluation.tier,
            rule_outcome=evaluation.rule_outcome,
            triggered_rule_ids=list(evaluation.triggered_rule_ids),
            required_question_ids=list(evaluation.required_question_ids),
            rule_set_version=evaluation.rule_set_version,
            all_current_rules_executed=evaluation.all_current_rules_executed,
            scenario_support=evaluation.scenario_support,
            unresolved_safety=evaluation.unresolved_safety,
            ordinary_agent_allowed=evaluation.ordinary_agent_allowed,
            required_action_code=evaluation.required_action_code,
            content_id=evaluation.content_id,
            content_release_id=evaluation.content_release_id,
            evaluated_at=evaluation.evaluated_at,
        )


IOSApplicationHandoffStatus = Literal[
    "ready_for_agent",
    "safety_action_required",
    "offline_only",
    "rejected",
]


class IOSSignalIntakeApplicationHandoff(StrictModel):
    """Internal P1F result; it is never a public write response."""

    schema_version: Literal["1.0"] = "1.0"
    session_id: UUID
    draft_revision: int = Field(ge=1)
    status: IOSApplicationHandoffStatus
    client_safety_status: IOSSafetyStatus
    server_safety: IOSServerSafetyProjection | None = None
    assessment_draft: AssessmentDraft | None = None
    error_code: str | None = Field(default=None, pattern=r"^[A-Z0-9._-]{1,120}$")

    @model_validator(mode="after")
    def validate_handoff_shape(self) -> "IOSSignalIntakeApplicationHandoff":
        if self.status == "ready_for_agent":
            if self.server_safety is None or self.assessment_draft is None:
                raise ValueError("ready_for_agent requires server safety and assessment draft")
            if not (
                self.server_safety.status == "complete"
                and self.server_safety.tier == "R3"
                and self.server_safety.ordinary_agent_allowed
                and not self.server_safety.unresolved_safety
            ):
                raise ValueError("ready_for_agent requires an allowed server safety projection")
            if self.error_code is not None:
                raise ValueError("ready_for_agent cannot carry an error")
        elif self.assessment_draft is not None:
            raise ValueError("non-ready handoff cannot carry an assessment draft")
        if self.status in {"safety_action_required", "offline_only"} and self.server_safety is None:
            raise ValueError("safety/offline handoff requires server safety projection")
        if self.status == "rejected":
            if self.error_code is None:
                raise ValueError("rejected handoff requires an error code")
            if self.server_safety is not None:
                raise ValueError("rejected handoff cannot carry server safety")
        return self


_MAPPING_PHASES = {"safety_review", "agent_draft", "review_facts", "awaiting_approval"}
_REQUIRED_GROUPS = {"sensation", "intensity", "temporal", "functional_impact"}
_UNKNOWN_SENSATION_NAMESPACE = UUID("2c4e8f55-7ab3-4b35-aada-3734c7610f71")


def adapt_ios_signal_intake(
    payload: IOSSignalIntakeDraft | Mapping[str, Any],
    *,
    expected_session_id: UUID,
    expected_draft_revision: int,
    server_safety: SafetyEvaluation | None = None,
) -> IOSSignalIntakeAdapterResult:
    """Parse and gate an iOS draft without creating a formal resource.

    ``server_safety`` must be produced by the current Application Service
    invocation.  A client claim is never used as permission to call an Agent.
    """

    try:
        draft = payload if isinstance(payload, IOSSignalIntakeDraft) else IOSSignalIntakeDraft.model_validate(payload)
    except ValidationError:
        return _rejected(expected_session_id, expected_draft_revision, "INTAKE_INVALID_PAYLOAD", "not_run")

    client_status = draft.safety.status
    try:
        _validate_for_mapping(
            draft,
            expected_session_id=expected_session_id,
            expected_draft_revision=expected_draft_revision,
        )
    except IOSSignalIntakeAdapterError as exc:
        return _rejected(draft.session_id, draft.draft_revision, exc.code, client_status)

    if server_safety is None:
        return IOSSignalIntakeAdapterResult(
            session_id=draft.session_id,
            draft_revision=draft.draft_revision,
            status="needs_safety_precheck",
            client_safety_status=client_status,
        )

    if server_safety.status == "unavailable" or server_safety.rule_outcome == "unavailable":
        return IOSSignalIntakeAdapterResult(
            session_id=draft.session_id,
            draft_revision=draft.draft_revision,
            status="offline_only",
            client_safety_status=client_status,
            server_safety_tier=server_safety.tier,
        )

    if (
        server_safety.status != "complete"
        or server_safety.unresolved_safety
        or server_safety.tier != "R3"
        or server_safety.scenario_support != "supported"
        or not server_safety.ordinary_agent_allowed
    ):
        return IOSSignalIntakeAdapterResult(
            session_id=draft.session_id,
            draft_revision=draft.draft_revision,
            status="safety_action_required",
            client_safety_status=client_status,
            server_safety_tier=server_safety.tier,
        )

    try:
        assessment_draft = _to_assessment_draft(draft)
    except IOSSignalIntakeAdapterError as exc:
        return _rejected(draft.session_id, draft.draft_revision, exc.code, client_status)

    return IOSSignalIntakeAdapterResult(
        session_id=draft.session_id,
        draft_revision=draft.draft_revision,
        status="ready_for_agent",
        client_safety_status=client_status,
        server_safety_tier=server_safety.tier,
        assessment_draft=assessment_draft,
    )


def _validate_for_mapping(
    draft: IOSSignalIntakeDraft,
    *,
    expected_session_id: UUID,
    expected_draft_revision: int,
) -> None:
    if draft.session_id != expected_session_id:
        raise IOSSignalIntakeAdapterError("INTAKE_SESSION_MISMATCH")
    if draft.draft_revision != expected_draft_revision:
        raise IOSSignalIntakeAdapterError("INTAKE_REVISION_MISMATCH")
    if draft.phase not in _MAPPING_PHASES:
        raise IOSSignalIntakeAdapterError("INTAKE_PHASE_NOT_SUBMITTABLE")
    if not draft.locations:
        raise IOSSignalIntakeAdapterError("INTAKE_LOCATION_REQUIRED")
    if len({location.marker_id for location in draft.locations}) != len(draft.locations):
        raise IOSSignalIntakeAdapterError("INTAKE_LOCATION_DUPLICATE")
    if any(not location.mapping.reviewed_by_user for location in draft.locations):
        raise IOSSignalIntakeAdapterError("INTAKE_LOCATION_NOT_REVIEWED")
    location_ids = {location.marker_id for location in draft.locations}
    for sensation in draft.facts.sensations:
        if (
            not sensation.location_marker_ids
            or len(set(sensation.location_marker_ids)) != len(sensation.location_marker_ids)
            or not set(sensation.location_marker_ids).issubset(location_ids)
        ):
            raise IOSSignalIntakeAdapterError("INTAKE_SENSATION_LOCATION_MISMATCH")
    if not _REQUIRED_GROUPS.issubset(set(draft.reviewed_groups)):
        raise IOSSignalIntakeAdapterError("INTAKE_REQUIRED_GROUP_NOT_REVIEWED")
    if "sensation" not in draft.unknown_groups and not draft.facts.sensations:
        raise IOSSignalIntakeAdapterError("INTAKE_SENSATION_REQUIRED")
    if "intensity" not in draft.unknown_groups and draft.facts.intensity is None:
        raise IOSSignalIntakeAdapterError("INTAKE_INTENSITY_REQUIRED")
    if "temporal" not in draft.unknown_groups and draft.facts.temporal is None:
        raise IOSSignalIntakeAdapterError("INTAKE_TEMPORAL_REQUIRED")
    if "functional_impact" not in draft.unknown_groups and not draft.facts.functional_impacts:
        raise IOSSignalIntakeAdapterError("INTAKE_FUNCTIONAL_IMPACT_REQUIRED")
    for source in _iter_fact_sources(draft):
        if source == "system":
            raise IOSSignalIntakeAdapterError("INTAKE_SYSTEM_FACT_SOURCE_FORBIDDEN")
        if source == "profile":
            # P1D has no server-issued Profile source reference.  Accepting a
            # client-controlled enum would turn it into an unaudited read.
            raise IOSSignalIntakeAdapterError("INTAKE_PROFILE_SOURCE_REF_REQUIRED")


def _iter_fact_sources(draft: IOSSignalIntakeDraft) -> list[IOSFactSource]:
    sources: list[IOSFactSource] = []
    sources.extend(item.source for item in draft.facts.sensations)
    if draft.facts.intensity is not None:
        sources.append(draft.facts.intensity.source)
    if draft.facts.temporal is not None:
        sources.append(draft.facts.temporal.source)
    sources.extend(item.source for item in draft.facts.aggravating_factors)
    sources.extend(item.source for item in draft.facts.relieving_factors)
    sources.extend(item.source for item in draft.facts.functional_impacts)
    sources.extend(item.source for item in draft.facts.background_facts)
    return sources


def _to_assessment_draft(draft: IOSSignalIntakeDraft) -> AssessmentDraft:
    marker_ids = {location.marker_id for location in draft.locations}
    intensity_source = _source_ref(draft, draft.facts.intensity.source, "intensity") if draft.facts.intensity else None

    sensations = [
        Sensation(
            sensation_id=item.sensation_id,
            code=item.code,
            user_label=item.user_label,
            intensities=[
                Intensity(
                    context=draft.facts.intensity.context,
                    value=draft.facts.intensity.value,
                    source=intensity_source,
                )
            ]
            if draft.facts.intensity is not None
            else [],
            location_marker_ids=list(item.location_marker_ids),
            source=_source_ref(draft, item.source, f"sensation:{item.sensation_id}"),
        )
        for item in draft.facts.sensations
    ]
    if not sensations:
        if "sensation" not in draft.unknown_groups:
            raise IOSSignalIntakeAdapterError("INTAKE_SENSATION_REQUIRED")
        unknown_id = uuid5(_UNKNOWN_SENSATION_NAMESPACE, str(draft.session_id))
        sensations.append(
            Sensation(
                sensation_id=unknown_id,
                code="unknown",
                intensities=[],
                location_marker_ids=[location.marker_id for location in draft.locations],
                source=_source_ref(draft, "user", "sensation:unknown"),
            )
        )

    temporal = draft.facts.temporal
    if temporal is None:
        if "temporal" not in draft.unknown_groups:
            raise IOSSignalIntakeAdapterError("INTAKE_TEMPORAL_REQUIRED")
        temporal_model = TemporalPattern(
            onset_mode="unknown",
            course="unknown",
            frequency="unknown",
            source=_source_ref(draft, "user", "temporal:unknown"),
        )
    else:
        temporal_model = TemporalPattern(
            onset_mode=temporal.onset_mode,
            course=temporal.course,
            frequency="unknown",
            user_text=temporal.user_text,
            source=_source_ref(draft, temporal.source, "temporal"),
        )

    aggravating = [
        AggravatingFactor(
            factor_id=item.factor_id,
            category="other",
            label=item.label,
            reported_effect=item.effect,
            source=_source_ref(draft, item.source, f"aggravating:{item.factor_id}"),
        )
        for item in draft.facts.aggravating_factors
        if item.effect in {"worse", "uncertain"}
    ]
    if len(aggravating) != len(draft.facts.aggravating_factors):
        raise IOSSignalIntakeAdapterError("INTAKE_AGGRAVATING_EFFECT_MISMATCH")

    relieving = [
        RelievingFactor(
            factor_id=item.factor_id,
            category="other",
            label=item.label,
            reported_effect=item.effect,
            source=_source_ref(draft, item.source, f"relieving:{item.factor_id}"),
        )
        for item in draft.facts.relieving_factors
        if item.effect in {"better", "uncertain"}
    ]
    if len(relieving) != len(draft.facts.relieving_factors):
        raise IOSSignalIntakeAdapterError("INTAKE_RELIEVING_EFFECT_MISMATCH")

    functional = [
        FunctionalImpact(
            domain=item.domain,
            severity=item.severity,
            user_text=item.user_text,
            source=_source_ref(draft, item.source, f"impact:{item.impact_id}"),
        )
        for item in draft.facts.functional_impacts
    ]
    background = [
        BackgroundFact(
            fact_id=item.fact_id,
            category=item.category,
            value=item.value,
            status="user_confirmed" if item.source == "user" and item.status == "reviewed" else "candidate",
            source=_source_ref(draft, item.source, f"background:{item.fact_id}"),
            observed_at=ApproximateDateTime(precision="unknown", user_text="时间未提供"),
        )
        for item in draft.facts.background_facts
    ]

    return AssessmentDraft(
        locations=list(draft.locations),
        sensations=sensations,
        temporal=temporal_model,
        trend="unknown",
        aggravating_factors=aggravating,
        relieving_factors=relieving,
        functional_impacts=functional,
        background_facts=background,
    )


def _source_ref(draft: IOSSignalIntakeDraft, source: IOSFactSource, suffix: str) -> SourceRef:
    if source == "profile":
        raise IOSSignalIntakeAdapterError("INTAKE_PROFILE_SOURCE_REF_REQUIRED")
    if source == "system":
        raise IOSSignalIntakeAdapterError("INTAKE_SYSTEM_FACT_SOURCE_FORBIDDEN")
    source_type = "user_report" if source == "user" else "agent_inference"
    observed_at = draft.updated_at
    if observed_at.tzinfo is None:
        observed_at = observed_at.replace(tzinfo=timezone.utc)
    return SourceRef(
        type=source_type,
        source_id=f"ios-signal-intake:{draft.session_id}:{suffix}",
        observed_at=observed_at.astimezone(timezone.utc),
    )


def _rejected(session_id: UUID, revision: int, error_code: str, client_status: IOSSafetyStatus) -> IOSSignalIntakeAdapterResult:
    return IOSSignalIntakeAdapterResult(
        session_id=session_id,
        draft_revision=revision,
        status="rejected",
        client_safety_status=client_status,
        error_code=error_code,
    )
