"""Deterministic validation after a PydanticAI run."""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
from typing import Any, Iterable

from pydantic import BaseModel

from .types import AssessmentDraft, AskQuestionCandidate, AgentCandidate, DraftCandidate


FORBIDDEN_KEYS = {
    "diagnosis",
    "differential_diagnosis",
    "disease_probability",
    "ruled_out_conditions",
    "prescription",
    "medication_dose",
    "treatment_plan",
    "event_id",
    "user_id",
    "lifecycle",
    "confirmation",
    "safety_assessment",
    "action_plan",
    "safetyBaselineId",
}

FORBIDDEN_TERMS = (
    "diagnosis",
    "differential diagnosis",
    "disease probability",
    "prescription",
    "medication dose",
    "treatment plan",
    "诊断",
    "鉴别诊断",
    "疾病概率",
    "排除疾病",
    "处方",
    "药物剂量",
    "治疗方案",
    "治愈",
)


class PolicyViolation(ValueError):
    """Raised when candidate output crosses a deterministic policy boundary."""


@dataclass(frozen=True)
class PolicyValidator:
    version: str = "p1b-policy-1"

    def validate(self, candidate: AgentCandidate, *, location_marker_ids: Iterable[str]) -> AgentCandidate:
        marker_ids = {str(marker_id) for marker_id in location_marker_ids}
        payload = candidate.model_dump(mode="json", exclude_none=True)
        self._reject_forbidden_keys(payload)
        self._reject_forbidden_terms(payload)

        if isinstance(candidate, AskQuestionCandidate):
            if any(question.category == "safety" for question in candidate.questions):
                raise PolicyViolation("Agent cannot create safety questions")
            return candidate

        if isinstance(candidate, DraftCandidate):
            self._validate_draft(candidate.event_draft, marker_ids)
            expected_digest = digest_for(candidate.event_draft)
            if candidate.draft_digest != expected_digest:
                raise PolicyViolation("draft digest does not match the typed draft")
            return candidate

        raise PolicyViolation("unknown candidate type")

    def _validate_draft(self, draft: AssessmentDraft, marker_ids: set[str]) -> None:
        draft_ids = {str(location.marker_id) for location in draft.locations}
        if not draft_ids:
            raise PolicyViolation("draft must contain at least one location")
        if marker_ids and not draft_ids.issubset(marker_ids):
            raise PolicyViolation("Agent introduced a location marker not present in the input")
        for sensation in draft.sensations:
            if not set(map(str, sensation.location_marker_ids)).issubset(draft_ids):
                raise PolicyViolation("sensation references an unknown marker")
        for background in draft.background_facts:
            if background.status != "candidate" and background.source.type == "agent_inference":
                raise PolicyViolation("Agent inference cannot be a confirmed background fact")

    def _reject_forbidden_keys(self, value: Any) -> None:
        if isinstance(value, dict):
            for key, child in value.items():
                if key in FORBIDDEN_KEYS:
                    raise PolicyViolation(f"forbidden output field: {key}")
                self._reject_forbidden_keys(child)
        elif isinstance(value, list):
            for child in value:
                self._reject_forbidden_keys(child)

    def _reject_forbidden_terms(self, value: Any) -> None:
        if isinstance(value, str):
            normalized = value.casefold()
            if any(term.casefold() in normalized for term in FORBIDDEN_TERMS):
                raise PolicyViolation("output contains a prohibited medical claim")
        elif isinstance(value, dict):
            for child in value.values():
                self._reject_forbidden_terms(child)
        elif isinstance(value, list):
            for child in value:
                self._reject_forbidden_terms(child)


def digest_for(value: BaseModel) -> str:
    """Return the canonical digest used for optimistic draft confirmation."""

    canonical = json.dumps(
        value.model_dump(mode="json", exclude_none=True),
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return "sha256:" + hashlib.sha256(canonical).hexdigest()
