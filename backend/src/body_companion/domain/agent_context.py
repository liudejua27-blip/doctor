"""Typed, consent-scoped context that an AssessmentAgent may read.

This module deliberately models a *projection* rather than a repository.  A
production application must construct these objects after authentication,
consent and purpose checks, then discard them after the run.  The Agent never
receives a generic mapping, database handle, raw document or access token.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Literal
from uuid import UUID, uuid4

from pydantic import BaseModel, ConfigDict, Field, model_validator


AgentReadScope = Literal[
    "body_profile_read",
    "current_episode_read",
    "historical_events_read",
    "verified_content_read",
]
AgentPurpose = Literal["assessment", "trend_review", "report_draft"]
ContextSourceType = Literal["body_profile", "confirmed_event", "verified_content"]
EpisodeStatus = Literal["open", "monitoring", "resolved", "closed"]
EpisodeReadScope = Literal["current_episode_read", "historical_events_read"]
WorkPattern = Literal["desk", "mixed", "physical", "unknown"]
Trend = Literal["improving", "stable", "worsening", "fluctuating", "unknown"]

_PROFILE_DATA_KEYS = {
    "activity_types",
    "training_frequency_per_week",
    "work_pattern",
    "preferred_language",
    "timezone",
}
_EVENT_DATA_KEYS = {
    "occurred_at",
    "region_ids",
    "sensation_codes",
    "trend",
    "functional_impact_codes",
}
_GUIDANCE_DATA_KEYS = {"rendered_text"}


def _meaningful(value: Any) -> bool:
    """Treat empty/default unknown values as absence for allowlist validation."""

    return value not in (None, "", (), [], "unknown")


class ContextAuthorizationError(PermissionError):
    """A context cannot disclose a source under the current grant set."""


class ContextModel(BaseModel):
    model_config = ConfigDict(extra="forbid", validate_assignment=True)


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


class AgentConsentGrant(ContextModel):
    subject_user_id: UUID
    scope: AgentReadScope
    consent_receipt_id: UUID
    purpose: AgentPurpose
    granted_at: datetime
    expires_at: datetime | None = None
    revoked_at: datetime | None = None

    @model_validator(mode="after")
    def validate_lifecycle(self) -> "AgentConsentGrant":
        granted = _as_utc(self.granted_at)
        if self.expires_at is not None and _as_utc(self.expires_at) <= granted:
            raise ValueError("consent expiry must be after grant time")
        if self.revoked_at is not None and _as_utc(self.revoked_at) < granted:
            raise ValueError("consent revocation cannot precede grant time")
        return self

    def is_active(self, *, now: datetime | None = None) -> bool:
        current = _as_utc(now or datetime.now(timezone.utc))
        if self.revoked_at is not None and _as_utc(self.revoked_at) <= current:
            return False
        return self.expires_at is None or current < _as_utc(self.expires_at)


class AgentSourceRef(ContextModel):
    source_id: str = Field(min_length=1, max_length=240)
    source_type: ContextSourceType
    revision: int = Field(ge=1)
    observed_at: datetime | None = None
    updated_at: datetime | None = None
    field_keys: tuple[str, ...] = Field(min_length=1, max_length=20)

    @model_validator(mode="after")
    def validate_field_keys(self) -> "AgentSourceRef":
        if len(set(self.field_keys)) != len(self.field_keys):
            raise ValueError("source field_keys must be unique")
        return self


class BodyProfileContext(ContextModel):
    owner_user_id: UUID
    profile_revision: int = Field(ge=1)
    activity_types: tuple[str, ...] = Field(default=(), max_length=12)
    training_frequency_per_week: int | None = Field(default=None, ge=0, le=21)
    work_pattern: WorkPattern = "unknown"
    preferred_language: str | None = Field(default=None, min_length=2, max_length=20)
    timezone: str | None = Field(default=None, min_length=1, max_length=64)
    sources: tuple[AgentSourceRef, ...] = Field(min_length=1, max_length=8)

    @model_validator(mode="after")
    def validate_allowlist(self) -> "BodyProfileContext":
        allowed = {key for source in self.sources for key in source.field_keys}
        for source in self.sources:
            if source.source_type != "body_profile":
                raise ValueError("profile sources must be body_profile sources")
            if not set(source.field_keys).issubset(_PROFILE_DATA_KEYS):
                raise ValueError("profile source contains an unknown field allowlist entry")
        values = {
            "activity_types": self.activity_types,
            "training_frequency_per_week": self.training_frequency_per_week,
            "work_pattern": self.work_pattern,
            "preferred_language": self.preferred_language,
            "timezone": self.timezone,
        }
        if any(_meaningful(value) and key not in allowed for key, value in values.items()):
            raise ValueError("profile contains a value outside the source field allowlist")
        return self

    def redacted_projection(self) -> dict[str, Any]:
        payload = self.model_dump(mode="json", exclude_none=True)
        allowed = {key for source in self.sources for key in source.field_keys}
        for key in _PROFILE_DATA_KEYS - allowed:
            payload.pop(key, None)
        return payload


class ConfirmedEventSummary(ContextModel):
    event_id: UUID
    episode_id: UUID
    owner_user_id: UUID
    resource_revision: int = Field(ge=1)
    occurred_at: datetime | None = None
    region_ids: tuple[str, ...] = Field(min_length=1, max_length=20)
    sensation_codes: tuple[str, ...] = Field(min_length=1, max_length=20)
    trend: Trend
    functional_impact_codes: tuple[str, ...] = Field(default=(), max_length=20)
    source: AgentSourceRef

    @model_validator(mode="after")
    def validate_source(self) -> "ConfirmedEventSummary":
        if self.source.source_type != "confirmed_event":
            raise ValueError("event summary source must be a confirmed_event source")
        if not set(self.source.field_keys).issubset(_EVENT_DATA_KEYS):
            raise ValueError("event source contains an unknown field allowlist entry")
        values = {
            "occurred_at": self.occurred_at,
            "region_ids": self.region_ids,
            "sensation_codes": self.sensation_codes,
            "trend": self.trend,
            "functional_impact_codes": self.functional_impact_codes,
        }
        if any(_meaningful(value) and key not in self.source.field_keys for key, value in values.items()):
            raise ValueError("event contains a value outside the source field allowlist")
        return self

    def redacted_projection(self) -> dict[str, Any]:
        payload = self.model_dump(mode="json", exclude_none=True)
        allowed = set(self.source.field_keys)
        for key in _EVENT_DATA_KEYS - allowed:
            payload.pop(key, None)
        return payload


class EpisodeContext(ContextModel):
    owner_user_id: UUID
    episode_id: UUID
    episode_revision: int = Field(ge=1)
    status: EpisodeStatus
    scope: EpisodeReadScope
    events: tuple[ConfirmedEventSummary, ...] = Field(default=(), max_length=30)
    source: AgentSourceRef

    @model_validator(mode="after")
    def validate_event_ownership(self) -> "EpisodeContext":
        for event in self.events:
            if event.owner_user_id != self.owner_user_id or event.episode_id != self.episode_id:
                raise ValueError("event summary must belong to the Episode owner and target")
        if self.source.source_type != "confirmed_event":
            raise ValueError("Episode source must be a confirmed_event source")
        if not set(self.source.field_keys).issubset(_EVENT_DATA_KEYS):
            raise ValueError("Episode source contains an unknown field allowlist entry")
        return self

    def redacted_projection(self) -> dict[str, Any]:
        payload = self.model_dump(mode="json", exclude_none=True)
        payload["events"] = [event.redacted_projection() for event in self.events]
        return payload


class VerifiedGuidanceContext(ContextModel):
    content_id: str = Field(min_length=1, max_length=160)
    content_release_id: str = Field(min_length=1, max_length=80)
    locale: str = Field(min_length=2, max_length=20)
    purpose: AgentPurpose
    rendered_text: str | None = Field(default=None, max_length=2000)
    source: AgentSourceRef

    @model_validator(mode="after")
    def validate_source(self) -> "VerifiedGuidanceContext":
        if self.source.source_type != "verified_content":
            raise ValueError("guidance source must be a verified_content source")
        if not set(self.source.field_keys).issubset(_GUIDANCE_DATA_KEYS):
            raise ValueError("guidance source contains an unknown field allowlist entry")
        if _meaningful(self.rendered_text) and "rendered_text" not in self.source.field_keys:
            raise ValueError("guidance text is outside the source field allowlist")
        return self

    def redacted_projection(self) -> dict[str, Any]:
        payload = self.model_dump(mode="json", exclude_none=True)
        if "rendered_text" not in self.source.field_keys:
            payload.pop("rendered_text", None)
        return payload


class AgentReadContext(ContextModel):
    context_id: UUID = Field(default_factory=uuid4)
    authenticated_user_id: UUID
    purpose: AgentPurpose
    grants: tuple[AgentConsentGrant, ...] = Field(default=(), max_length=8)
    profile: BodyProfileContext | None = None
    episode: EpisodeContext | None = None
    guidance: VerifiedGuidanceContext | None = None
    redaction_policy_version: str = Field(min_length=1, max_length=40)

    @model_validator(mode="after")
    def validate_bindings(self) -> "AgentReadContext":
        scopes: set[AgentReadScope] = set()
        for grant in self.grants:
            if grant.subject_user_id != self.authenticated_user_id:
                raise ValueError("consent grant subject must match authenticated user")
            if grant.purpose != self.purpose:
                raise ValueError("consent grant purpose must match context purpose")
            if grant.scope in scopes:
                raise ValueError("duplicate consent scope is not allowed")
            scopes.add(grant.scope)

        if self.profile is not None:
            if self.profile.owner_user_id != self.authenticated_user_id:
                raise ValueError("profile owner must match authenticated user")
            if "body_profile_read" not in scopes:
                raise ValueError("profile requires body_profile_read grant")
            if any(source.source_type != "body_profile" for source in self.profile.sources):
                raise ValueError("profile sources must be body_profile sources")

        if self.episode is not None:
            if self.episode.owner_user_id != self.authenticated_user_id:
                raise ValueError("Episode owner must match authenticated user")
            if self.episode.scope not in scopes:
                raise ValueError("Episode requires a matching read grant")

        if self.guidance is not None:
            if self.guidance.purpose != self.purpose or "verified_content_read" not in scopes:
                raise ValueError("guidance requires a matching purpose and grant")

        return self

    @classmethod
    def empty(cls, user_id: UUID, *, purpose: AgentPurpose = "assessment") -> "AgentReadContext":
        return cls(authenticated_user_id=user_id, purpose=purpose, redaction_policy_version="p3-redaction-1")

    def _grant(self, scope: AgentReadScope, *, now: datetime | None = None) -> AgentConsentGrant:
        for grant in self.grants:
            if grant.scope == scope and grant.is_active(now=now):
                return grant
        raise ContextAuthorizationError("agent data scope is not active")

    def require_scope(self, scope: AgentReadScope, *, now: datetime | None = None) -> AgentConsentGrant:
        """Re-check a scope immediately before a tool projection is returned."""

        return self._grant(scope, now=now)

    def projection(self, scope: AgentReadScope, *, now: datetime | None = None) -> dict[str, Any]:
        grant = self._grant(scope, now=now)
        projection: dict[str, Any]
        if scope == "body_profile_read":
            if self.profile is None:
                raise ContextAuthorizationError("profile projection is unavailable")
            projection = self.profile.redacted_projection()
        elif scope in {"current_episode_read", "historical_events_read"}:
            if self.episode is None or self.episode.scope != scope:
                raise ContextAuthorizationError("Episode projection is unavailable for this scope")
            projection = self.episode.redacted_projection()
        else:
            if self.guidance is None:
                raise ContextAuthorizationError("verified guidance projection is unavailable")
            projection = self.guidance.redacted_projection()

        return {
            "context_id": str(self.context_id),
            "purpose": self.purpose,
            "scope": scope,
            "consent_receipt_id": str(grant.consent_receipt_id),
            "redaction_policy_version": self.redaction_policy_version,
            "projection": projection,
        }

    def source_ids(self, scope: AgentReadScope) -> tuple[str, ...]:
        if scope == "body_profile_read" and self.profile is not None:
            return tuple(source.source_id for source in self.profile.sources)
        if scope in {"current_episode_read", "historical_events_read"} and self.episode is not None:
            return (self.episode.source.source_id, *(event.source.source_id for event in self.episode.events))
        if scope == "verified_content_read" and self.guidance is not None:
            return (self.guidance.source.source_id,)
        return ()


@dataclass
class AgentReadAudit:
    """In-memory, redacted evidence of what a single Agent run read."""

    successful_reads: list[dict[str, Any]] = field(default_factory=list)
    denied_scopes: list[str] = field(default_factory=list)

    def record_success(self, *, scope: AgentReadScope, source_ids: tuple[str, ...], revision: int | None = None) -> None:
        self.successful_reads.append(
            {
                "scope": scope,
                "source_ids": list(source_ids),
                "revision": revision,
            }
        )

    def record_denied(self, scope: AgentReadScope) -> None:
        self.denied_scopes.append(scope)

    @property
    def source_ids(self) -> tuple[str, ...]:
        values: list[str] = []
        for read in self.successful_reads:
            values.extend(read["source_ids"])
        return tuple(dict.fromkeys(values))

    def summary(self) -> dict[str, Any]:
        return {
            "successful_reads": [dict(read) for read in self.successful_reads],
            "denied_scopes": list(self.denied_scopes),
        }
