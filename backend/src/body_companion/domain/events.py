"""P2 confirmed Event/Episode projection for an isolated prototype.

The store is deliberately in-memory.  It proves the domain and transaction
boundary after a second approval without pretending to be the production
PostgreSQL repository, auth layer, or audit log.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime
import hashlib
import json
from threading import RLock
from typing import Any, Iterable, Literal, Mapping
from uuid import UUID

from pydantic import Field, model_validator

from .confirmation import ConfirmationConflict
from .policy import digest_for
from .types import (
    AggravatingFactor,
    ApproximateDateTime,
    AssessmentDraft,
    BackgroundFact,
    BodyLocation,
    DraftCandidate,
    EpisodeSelection,
    FunctionalImpact,
    RelievingFactor,
    SafetyAnswer,
    SafetyEvaluation,
    Sensation,
    SourceRef,
    StrictModel,
    TemporalPattern,
    UserTurnInput,
    utc_now,
)


class EventRawInput(StrictModel):
    modality: Literal["text", "voice_transcript", "body_map", "mixed"]
    text: str | None = Field(default=None, min_length=1, max_length=8000)
    language: str = Field(pattern=r"^[a-z]{2,3}(?:-[A-Z]{2})?$")
    source_ref: str | None = Field(default=None, max_length=240)
    transcript_confirmed_by_user: bool | None = None
    captured_at: datetime

    @model_validator(mode="after")
    def validate_modality(self) -> "EventRawInput":
        if self.modality == "text" and not self.text:
            raise ValueError("text raw input requires text")
        if self.modality == "voice_transcript" and (not self.text or self.transcript_confirmed_by_user is not True):
            raise ValueError("voice transcript must be user-confirmed")
        if self.modality == "body_map" and (self.text or self.source_ref or self.transcript_confirmed_by_user is not None):
            raise ValueError("body-map raw input cannot carry text or transcript fields")
        if self.modality == "mixed" and not self.text:
            raise ValueError("mixed raw input requires text")
        return self


class EventSafetyAnswer(StrictModel):
    question_id: str = Field(pattern=r"^[A-Za-z0-9._-]{1,120}$")
    answer_type: Literal["boolean", "single_choice", "multiple_choice"]
    answer_state: Literal["answered", "uncertain", "not_answered"]
    boolean_value: bool | None = None
    choice_values: list[str] | None = Field(default=None, max_length=20)
    user_text: str | None = Field(default=None, min_length=1, max_length=1000)
    answered_at: datetime
    source: SourceRef


class EventRuleHit(StrictModel):
    rule_id: str = Field(pattern=r"^[A-Za-z0-9._-]{1,120}$")
    result: Literal["matched", "not_matched", "undetermined"]
    tier: Literal["R0", "R1", "R2", "R3", "undetermined"]
    evidence_refs: list[str] = Field(default_factory=list, max_length=20)


class EventSafetyAssessment(StrictModel):
    status: Literal["complete", "incomplete", "unavailable"]
    tier: Literal["R0", "R1", "R2", "R3", "undetermined"]
    rule_outcome: Literal["triggered", "no_rule_triggered", "unresolved", "unavailable"]
    all_current_rules_executed: bool
    triggered_rule_ids: list[str] = Field(default_factory=list, max_length=100)
    rule_set_version: str = Field(min_length=1, max_length=64)
    answers: list[EventSafetyAnswer] = Field(default_factory=list, max_length=100)
    rule_hits: list[EventRuleHit] = Field(default_factory=list, max_length=100)
    required_action_code: str = Field(pattern=r"^[A-Z0-9._-]{1,120}$")
    processing_mode: Literal["emergency", "urgent", "normal", "manual", "unsupported", "degraded"]
    model_suggested_escalation: Literal["R0", "R1", "R2", "none"] | None = None
    evaluated_at: datetime

    @model_validator(mode="after")
    def validate_gate(self) -> "EventSafetyAssessment":
        if self.status == "complete" and not self.all_current_rules_executed:
            raise ValueError("complete event safety must execute all current rules")
        if self.status in {"incomplete", "unavailable"} and self.all_current_rules_executed:
            raise ValueError("incomplete/unavailable event safety cannot claim complete execution")
        if self.rule_outcome == "no_rule_triggered" and (
            self.status != "complete" or self.tier != "R3" or self.triggered_rule_ids
        ):
            raise ValueError("NoRuleTriggered requires complete R3 with no triggered IDs")
        if self.tier == "R0" and self.processing_mode != "emergency":
            raise ValueError("R0 event safety must use emergency mode")
        if self.tier == "R1" and self.processing_mode != "urgent":
            raise ValueError("R1 event safety must use urgent mode")
        if self.tier == "undetermined" and self.processing_mode != "degraded":
            raise ValueError("undetermined event safety must use degraded mode")
        if self.processing_mode == "normal" and (self.status != "complete" or self.tier not in {"R2", "R3"}):
            raise ValueError("normal confirmed event requires complete R2/R3 safety")
        return self


class EventActionItem(StrictModel):
    content_id: str = Field(min_length=1, max_length=160)
    category: Literal["urgent_help", "professional_review", "observation", "load_adjustment", "check_in"]
    display_text: str = Field(min_length=1, max_length=1000)
    reason: str | None = Field(default=None, max_length=500)


class EventActionPlan(StrictModel):
    tier: Literal["R0", "R1", "R2", "R3", "undetermined"]
    content_release_id: str = Field(min_length=1, max_length=64)
    items: list[EventActionItem] = Field(default_factory=list, max_length=20)
    escalation_conditions: list[EventActionItem] = Field(default_factory=list, max_length=20)
    check_in_at: datetime | None = None


class EventAIRuntime(StrictModel):
    used: bool
    purpose: Literal["event_structuring_and_explanation"] = "event_structuring_and_explanation"
    not_used_reason: Literal[
        "user_declined_cloud_ai",
        "provider_unavailable",
        "scenario_unsupported",
        "safety_suppressed",
        "not_needed",
    ] | None = None
    agent_version: str | None = Field(default=None, min_length=1, max_length=64)
    prompt_version: str | None = Field(default=None, min_length=1, max_length=64)
    provider: str | None = Field(default=None, min_length=1, max_length=80)
    model_name: str | None = Field(default=None, min_length=1, max_length=160)
    model_version: str | None = Field(default=None, min_length=1, max_length=160)

    @model_validator(mode="after")
    def validate_runtime(self) -> "EventAIRuntime":
        runtime_fields = (self.agent_version, self.prompt_version, self.provider, self.model_name, self.model_version)
        if self.used:
            if not all(runtime_fields) or self.not_used_reason is not None:
                raise ValueError("used AI runtime requires complete provider metadata")
        elif any(runtime_fields) or self.not_used_reason is None:
            raise ValueError("unused AI runtime requires a reason and no provider metadata")
        return self


class EventProvenance(StrictModel):
    sources: list[SourceRef] = Field(min_length=1, max_length=100)
    ontology_version: str = Field(min_length=1, max_length=64)
    rule_set_version: str = Field(min_length=1, max_length=64)
    content_release_id: str | None = Field(default=None, min_length=1, max_length=64)
    ai_runtime: EventAIRuntime
    output_schema_version: Literal["1.0"] = "1.0"
    safetyBaselineId: str = Field(pattern=r"^[A-Za-z0-9._:-]{1,120}$")


class EventConfirmation(StrictModel):
    approval_id: UUID
    confirmed_by: Literal["authenticated_user"] = "authenticated_user"
    confirmed_at: datetime
    intent_digest: str = Field(pattern=r"^sha256:[a-f0-9]{64}$")
    reviewed_fields: list[str] = Field(min_length=8, max_length=8)

    @model_validator(mode="after")
    def validate_reviewed_fields(self) -> "EventConfirmation":
        expected = {
            "locations",
            "sensations",
            "temporal",
            "trend",
            "aggravating_factors",
            "relieving_factors",
            "functional_impacts",
            "background_facts",
        }
        if set(self.reviewed_fields) != expected:
            raise ValueError("confirmed event must review all eight fact groups exactly once")
        return self


class PrototypeEpisode(StrictModel):
    episode_id: UUID
    user_id: UUID
    title: str = Field(min_length=1, max_length=200)
    primary_region_id: str = Field(pattern=r"^body\.[a-z0-9_]+(?:\.[a-z0-9_]+)+$")
    status: Literal["open", "monitoring", "resolved", "closed"] = "open"
    started_on: date
    revision: int = Field(ge=1)
    latest_event_id: UUID | None = None
    recurrence_of_episode_id: UUID | None = None
    next_check_in_at: datetime | None = None
    last_check_in_at: datetime | None = None
    created_at: datetime
    updated_at: datetime


class BodySignalEvent(StrictModel):
    schema_version: Literal["1.0"] = "1.0"
    event_id: UUID
    user_id: UUID
    episode_id: UUID | None = None
    session_id: UUID | None = None
    source_turn_id: UUID | None = None
    lifecycle: Literal["draft", "discarded", "confirmed", "superseded", "voided"]
    resource_revision: int = Field(ge=1)
    correction_sequence: int = Field(ge=1)
    supersedes_event_id: UUID | None = None
    superseded_by_event_id: UUID | None = None
    raw_input: EventRawInput
    locations: list[BodyLocation] = Field(min_length=1, max_length=20)
    sensations: list[Sensation] = Field(min_length=1, max_length=20)
    temporal: TemporalPattern
    trend: Literal["improving", "stable", "worsening", "fluctuating", "unknown"]
    aggravating_factors: list[AggravatingFactor] = Field(default_factory=list, max_length=30)
    relieving_factors: list[RelievingFactor] = Field(default_factory=list, max_length=30)
    functional_impacts: list[FunctionalImpact] = Field(default_factory=list, max_length=30)
    background_facts: list[BackgroundFact] = Field(default_factory=list, max_length=50)
    safety_assessment: EventSafetyAssessment
    action_plan: EventActionPlan
    provenance: EventProvenance
    confirmation: EventConfirmation | None = None
    occurred_at: ApproximateDateTime
    recorded_at: datetime
    timezone: str | None = Field(default=None, min_length=1, max_length=64)
    content_digest: str | None = Field(default=None, pattern=r"^sha256:[a-f0-9]{64}$")
    created_at: datetime

    @model_validator(mode="after")
    def validate_event_invariants(self) -> "BodySignalEvent":
        marker_ids = {location.marker_id for location in self.locations}
        for sensation in self.sensations:
            if not set(sensation.location_marker_ids).issubset(marker_ids):
                raise ValueError("sensation references a marker outside the event locations")
        if self.lifecycle in {"confirmed", "superseded", "voided"}:
            if self.episode_id is None or self.confirmation is None or self.content_digest is None:
                raise ValueError("formal event requires episode, confirmation and content digest")
            if self.supersedes_event_id is None and self.correction_sequence != 1:
                raise ValueError("first confirmed event must have correction_sequence=1")
            if any(not location.mapping.reviewed_by_user for location in self.locations):
                raise ValueError("formal event locations must be user reviewed")
            if any(fact.status != "user_confirmed" for fact in self.background_facts):
                raise ValueError("formal event background facts must be user confirmed")
        else:
            if self.confirmation is not None or self.content_digest is not None:
                raise ValueError("draft/discarded event cannot carry confirmation or content digest")
        if self.safety_assessment.processing_mode == "degraded" and self.lifecycle not in {"draft", "discarded"}:
            raise ValueError("degraded safety cannot create a formal event")
        if self.safety_assessment.tier in {"R0", "R1", "undetermined"} and self.provenance.ai_runtime.used:
            raise ValueError("high-risk or undetermined event cannot carry AI runtime")
        return self

    def canonical_payload(self) -> dict[str, Any]:
        payload = self.model_dump(mode="json", exclude_none=True)
        payload.pop("content_digest", None)
        return payload


@dataclass(frozen=True)
class CommittedEvent:
    event: BodySignalEvent
    episode: PrototypeEpisode


class PrototypeEventStore:
    """Atomic in-memory Event/Episode repository for P2 tests."""

    def __init__(self, *, safety_baseline_id: str = "P1B-PROTOTYPE-NOT-RELEASED") -> None:
        self.safety_baseline_id = safety_baseline_id
        self._events: dict[UUID, BodySignalEvent] = {}
        self._episodes: dict[UUID, PrototypeEpisode] = {}
        self._event_by_approval: dict[UUID, UUID] = {}
        self._owners_by_event: dict[UUID, UUID] = {}
        self._owners_by_episode: dict[UUID, UUID] = {}
        self._lock = RLock()

    def seed_episode(
        self,
        *,
        owner_id: UUID,
        region_id: str,
        status: Literal["open", "monitoring", "resolved", "closed"] = "open",
        started_on: date,
        title: str = "身体信号记录",
        episode_id: UUID | None = None,
    ) -> PrototypeEpisode:
        now = utc_now()
        episode = PrototypeEpisode(
            episode_id=episode_id or UUID(int=0),
            user_id=owner_id,
            title=title,
            primary_region_id=region_id,
            status=status,
            started_on=started_on,
            revision=1,
            created_at=now,
            updated_at=now,
        )
        with self._lock:
            if episode.episode_id.int == 0:
                from uuid import uuid4

                episode = episode.model_copy(update={"episode_id": uuid4()})
            if episode.episode_id in self._episodes:
                raise ConfirmationConflict("EPISODE_ALREADY_EXISTS", "episode already exists")
            self._episodes[episode.episode_id] = episode
            self._owners_by_episode[episode.episode_id] = owner_id
        return episode

    def commit_confirmed(
        self,
        *,
        owner_id: UUID,
        approval_id: UUID,
        event_id: UUID,
        session_id: UUID,
        source_turn_id: UUID,
        candidate: DraftCandidate,
        safety: SafetyEvaluation,
        raw_input: UserTurnInput,
        episode_selection: EpisodeSelection,
        intent_digest: str,
        reviewed_fields: Iterable[str],
        agent_versions: Mapping[str, Any],
        now: datetime,
    ) -> UUID:
        with self._lock:
            replay_event_id = self._event_by_approval.get(approval_id)
            if replay_event_id is not None:
                return replay_event_id
            if digest_for(candidate.event_draft) != candidate.draft_digest:
                raise ConfirmationConflict("DRAFT_DIGEST_MISMATCH", "typed draft digest is stale")
            if safety.status != "complete" or safety.tier not in {"R2", "R3"} or safety.unresolved_safety:
                raise ConfirmationConflict("SAFETY_GATE_BLOCKED", "formal event requires complete R2/R3 safety")

            confirmed_draft = _confirmed_projection(candidate.event_draft)
            episode = self._resolve_episode(
                owner_id=owner_id,
                selection=episode_selection,
                region_id=confirmed_draft.locations[0].region_id,
                now=now,
            )
            try:
                event = _build_event(
                    event_id=event_id,
                    owner_id=owner_id,
                    episode=episode,
                    session_id=session_id,
                    source_turn_id=source_turn_id,
                    draft=confirmed_draft,
                    safety=safety,
                    raw_input=raw_input,
                    approval_id=approval_id,
                    intent_digest=intent_digest,
                    reviewed_fields=reviewed_fields,
                    agent_versions=agent_versions,
                    safety_baseline_id=self.safety_baseline_id,
                    now=now,
                )
            except ConfirmationConflict:
                raise
            except Exception as exc:  # noqa: BLE001 - keep domain details out of HTTP
                raise ConfirmationConflict("EVENT_VALIDATION_FAILED", "confirmed event failed domain validation") from exc
            # All validation has completed.  Commit the two aggregates together.
            is_new_episode = episode.episode_id not in self._episodes
            next_episode = episode.model_copy(
                update={
                    "status": (
                        "open"
                        if episode_selection.mode == "reopen_existing" or episode.status == "monitoring"
                        else episode.status
                    ),
                    # Creating a new aggregate and linking its first Event is
                    # one commit at revision 1; appending to an existing
                    # aggregate advances its optimistic version.
                    "revision": episode.revision if is_new_episode else episode.revision + 1,
                    "latest_event_id": event.event_id,
                    "updated_at": now,
                }
            )
            self._events[event.event_id] = event
            self._episodes[next_episode.episode_id] = next_episode
            self._owners_by_event[event.event_id] = owner_id
            self._owners_by_episode[next_episode.episode_id] = owner_id
            self._event_by_approval[approval_id] = event.event_id
            return event.event_id

    def get_event(self, *, owner_id: UUID, event_id: UUID) -> BodySignalEvent:
        with self._lock:
            event = self._events.get(event_id)
            if event is None or self._owners_by_event.get(event_id) != owner_id:
                raise ConfirmationConflict("RESOURCE_NOT_FOUND", "event not found")
            return event

    def get_episode(self, *, owner_id: UUID, episode_id: UUID) -> PrototypeEpisode:
        with self._lock:
            episode = self._episodes.get(episode_id)
            if episode is None or self._owners_by_episode.get(episode_id) != owner_id:
                raise ConfirmationConflict("RESOURCE_NOT_FOUND", "episode not found")
            return episode

    def count_events(self, *, owner_id: UUID) -> int:
        with self._lock:
            return sum(1 for event_id, owner in self._owners_by_event.items() if owner == owner_id and event_id in self._events)

    def event_refs_for_episode(self, *, owner_id: UUID, episode_id: UUID) -> list[dict[str, Any]]:
        with self._lock:
            episode = self._episodes.get(episode_id)
            if episode is None or self._owners_by_episode.get(episode_id) != owner_id:
                raise ConfirmationConflict("RESOURCE_NOT_FOUND", "episode not found")
            events = [
                event
                for event in self._events.values()
                if event.episode_id == episode_id and self._owners_by_event.get(event.event_id) == owner_id
            ]
            events.sort(key=lambda event: (event.recorded_at, event.event_id), reverse=True)
            return [
                {
                    "event_id": str(event.event_id),
                    "lifecycle": event.lifecycle,
                    "resource_revision": event.resource_revision,
                    "correction_sequence": event.correction_sequence,
                    "content_digest": event.content_digest,
                    "occurred_at": event.occurred_at.model_dump(mode="json", exclude_none=True),
                    "recorded_at": event.recorded_at.isoformat(),
                }
                for event in events
            ]

    def _resolve_episode(
        self,
        *,
        owner_id: UUID,
        selection: EpisodeSelection,
        region_id: str,
        now: datetime,
    ) -> PrototypeEpisode:
        if selection.mode == "create_new":
            from uuid import uuid4

            return PrototypeEpisode(
                episode_id=uuid4(),
                user_id=owner_id,
                title=selection.title or "身体信号记录",
                primary_region_id=region_id,
                status="open",
                started_on=selection.started_on,  # validated by EpisodeSelection
                revision=1,
                created_at=now,
                updated_at=now,
            )
        if selection.episode_id is None or selection.expected_revision is None:
            raise ConfirmationConflict("EPISODE_SELECTION_INVALID", "existing Episode selection is incomplete")
        episode = self._episodes.get(selection.episode_id)
        if episode is None or self._owners_by_episode.get(episode.episode_id) != owner_id:
            raise ConfirmationConflict("EPISODE_NOT_FOUND", "episode not found")
        if episode.revision != selection.expected_revision:
            raise ConfirmationConflict("EPISODE_REVISION_MISMATCH", "episode revision changed")
        if selection.mode == "join_existing" and episode.status not in {"open", "monitoring"}:
            raise ConfirmationConflict("EPISODE_NOT_REOPENABLE", "joining a resolved/closed Episode requires explicit reopen")
        if selection.mode == "reopen_existing" and episode.status not in {"resolved", "closed"}:
            raise ConfirmationConflict("EPISODE_SELECTION_INVALID", "reopen_existing requires resolved or closed Episode")
        return episode


def _confirmed_projection(draft: AssessmentDraft) -> AssessmentDraft:
    locations = [
        location.model_copy(update={"mapping": location.mapping.model_copy(update={"reviewed_by_user": True})})
        for location in draft.locations
    ]
    backgrounds = [fact.model_copy(update={"status": "user_confirmed"}) for fact in draft.background_facts]
    return draft.model_copy(update={"locations": locations, "background_facts": backgrounds})


def _build_event(
    *,
    event_id: UUID,
    owner_id: UUID,
    episode: PrototypeEpisode,
    session_id: UUID,
    source_turn_id: UUID,
    draft: AssessmentDraft,
    safety: SafetyEvaluation,
    raw_input: UserTurnInput,
    approval_id: UUID,
    intent_digest: str,
    reviewed_fields: Iterable[str],
    agent_versions: Mapping[str, Any],
    safety_baseline_id: str,
    now: datetime,
) -> BodySignalEvent:
    raw = EventRawInput(
        modality=raw_input.modality if raw_input.modality != "structured_answer" else "mixed",
        text=raw_input.text,
        language=raw_input.language or "und",
        captured_at=raw_input.submitted_at,
    )
    event_safety = _safety_projection(safety)
    runtime = EventAIRuntime(
        used=True,
        agent_version=str(agent_versions.get("agent_version", "p1b-agent-1")),
        prompt_version=str(agent_versions.get("prompt_version", "p1b-prompt-1")),
        provider=str(agent_versions.get("provider", "injected")),
        model_name=str(agent_versions.get("model_name", "prototype")),
        model_version=str(agent_versions.get("model_version", "prototype")),
    )
    action_plan = EventActionPlan(
        tier=safety.tier,
        content_release_id="prototype.none",
        items=[
            EventActionItem(
                content_id="prototype.none",
                category="observation",
                display_text="样机未提供审核后的行动内容；此记录不构成医疗建议。",
            )
        ],
        escalation_conditions=[],
    )
    provenance = EventProvenance(
        sources=[SourceRef(type="user_report", source_id=str(source_turn_id))],
        ontology_version=draft.locations[0].ontology_version,
        rule_set_version=safety.rule_set_version,
        content_release_id="prototype.none",
        ai_runtime=runtime,
        safetyBaselineId=safety_baseline_id,
    )
    onset = draft.temporal.onset or ApproximateDateTime(precision="unknown", user_text="用户未提供开始时间")
    # Build once without the derived digest, then validate the final payload
    # again after the server computes the canonical digest.  ``model_construct``
    # is intentionally confined to this two-step derivation and never escapes
    # as an unvalidated event.
    draft_event = BodySignalEvent.model_construct(
        event_id=event_id,
        user_id=owner_id,
        episode_id=episode.episode_id,
        session_id=session_id,
        source_turn_id=source_turn_id,
        lifecycle="confirmed",
        resource_revision=1,
        correction_sequence=1,
        raw_input=raw,
        locations=draft.locations,
        sensations=draft.sensations,
        temporal=draft.temporal,
        trend=draft.trend,
        aggravating_factors=draft.aggravating_factors,
        relieving_factors=draft.relieving_factors,
        functional_impacts=draft.functional_impacts,
        background_facts=draft.background_facts,
        safety_assessment=event_safety,
        action_plan=action_plan,
        provenance=provenance,
        confirmation=EventConfirmation(
            approval_id=approval_id,
            confirmed_at=now,
            intent_digest=intent_digest,
            reviewed_fields=list(reviewed_fields),
        ),
        occurred_at=onset,
        recorded_at=now,
        timezone="UTC",
        created_at=now,
    )
    payload = draft_event.model_dump(mode="json", exclude_none=True)
    payload["content_digest"] = _digest_dict(draft_event.canonical_payload())
    return BodySignalEvent.model_validate(payload)


def _safety_projection(safety: SafetyEvaluation) -> EventSafetyAssessment:
    answers = [
        EventSafetyAnswer(
            question_id=answer.question_id,
            answer_type=answer.answer_type,
            answer_state={"answered": "answered", "unknown": "uncertain", "declined": "not_answered"}[answer.answer_state],
            boolean_value=answer.boolean_value,
            choice_values=answer.choice_values,
            user_text=answer.raw_text,
            answered_at=answer.answered_at,
            source=SourceRef(type="user_report", source_id=f"safety:{answer.question_id}"),
        )
        for answer in safety.answers
    ]
    hits = [
        EventRuleHit(
            rule_id=hit.rule_id,
            result=hit.result,
            tier=hit.tier or ("R3" if hit.result == "not_matched" else "undetermined"),
            evidence_refs=hit.evidence_refs,
        )
        for hit in safety.rule_hits
    ]
    mode: Literal["emergency", "urgent", "normal", "manual", "unsupported", "degraded"] = "normal"
    if safety.tier == "R0":
        mode = "emergency"
    elif safety.tier == "R1":
        mode = "urgent"
    elif safety.tier == "undetermined":
        mode = "degraded"
    return EventSafetyAssessment(
        status=safety.status,
        tier=safety.tier,
        rule_outcome=safety.rule_outcome,
        all_current_rules_executed=safety.all_current_rules_executed,
        triggered_rule_ids=safety.triggered_rule_ids,
        rule_set_version=safety.rule_set_version,
        answers=answers,
        rule_hits=hits,
        required_action_code=safety.required_action_code or "PROTOTYPE_NONE",
        processing_mode=mode,
        evaluated_at=safety.evaluated_at,
    )


def _digest_dict(value: dict[str, Any]) -> str:
    canonical = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return "sha256:" + hashlib.sha256(canonical).hexdigest()
