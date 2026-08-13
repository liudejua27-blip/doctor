"""Deterministic safety gate.

This module contains the reducer and permission boundary, not clinical rules.
Production rule definitions must be supplied by an approved, versioned content
bundle. An empty/unavailable catalog therefore fails closed.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
import re
from typing import Callable, Iterable

from .types import RuleHit, SafetyAnswer, SafetyEvaluation, SafetyTier, utc_now


TIER_RANK: dict[str, int] = {"R3": 0, "R2": 1, "R1": 2, "R0": 3}
IDENTIFIER_PATTERN = re.compile(r"^[A-Za-z0-9._-]{1,120}$")
ACTION_PATTERN = re.compile(r"^[A-Z0-9._-]{1,120}$")


@dataclass(frozen=True)
class SafetyContext:
    """Minimal input visible to a deterministic rule evaluator."""

    user_text: str
    answers: tuple[SafetyAnswer, ...]
    source_fact_ids: tuple[str, ...] = ()


@dataclass(frozen=True)
class RuleDefinition:
    rule_id: str
    required_question_id: str | None
    evaluate: Callable[[SafetyContext], RuleHit]
    required_action_code: str
    content_id: str
    content_release_id: str
    display_message: str


@dataclass(frozen=True)
class RuleCatalog:
    """Versioned rule catalog descriptor.

    `available=False` is the safe default until clinical review produces a
    real bundle. Test code may inject deterministic rules explicitly.
    """

    version: str
    rules: tuple[RuleDefinition, ...] = ()
    available: bool = False
    scenario_supported: bool = True


class SafetyEngine:
    def __init__(self, catalog: RuleCatalog):
        self.catalog = catalog

    def evaluate(
        self,
        *,
        user_text: str,
        answers: Iterable[SafetyAnswer] = (),
        source_fact_ids: Iterable[str] = (),
        evaluated_at: datetime | None = None,
    ) -> SafetyEvaluation:
        timestamp = evaluated_at or utc_now()
        try:
            answer_tuple = tuple(
                SafetyAnswer.model_validate(
                    answer.model_dump(mode="python") if isinstance(answer, SafetyAnswer) else answer
                )
                for answer in answers
            )
            source_id_tuple = tuple(source_fact_ids)
        except Exception:
            return self._unavailable((), timestamp)

        if (
            not isinstance(user_text, str)
            or any(not isinstance(source_id, str) or not source_id.strip() for source_id in source_id_tuple)
            or not self._catalog_is_executable()
        ):
            return self._unavailable(answer_tuple, timestamp)

        rule_ids = [definition.rule_id for definition in self.catalog.rules]
        if len(set(rule_ids)) != len(rule_ids):
            return self._unavailable(answer_tuple, timestamp)

        context = SafetyContext(user_text=user_text, answers=answer_tuple, source_fact_ids=source_id_tuple)
        hits: list[RuleHit] = []
        try:
            for definition in self.catalog.rules:
                raw_hit = definition.evaluate(context)
                if not isinstance(raw_hit, RuleHit):
                    return self._unavailable(answer_tuple, timestamp)
                # A Pydantic instance can be manufactured with model_construct
                # or become stale across a schema boundary. Re-validate its
                # serialized fields before it can participate in permission
                # reduction.
                hit = RuleHit.model_validate(raw_hit.model_dump(mode="python"))
                if hit.rule_id != definition.rule_id:
                    return self._unavailable(answer_tuple, timestamp)
                if hit.result == "matched" and (
                    hit.tier is None
                    or not hit.evidence_refs
                    or any(not evidence_ref.strip() for evidence_ref in hit.evidence_refs)
                ):
                    return self._unavailable(answer_tuple, timestamp)
                if hit.result != "matched" and hit.tier is not None:
                    return self._unavailable(answer_tuple, timestamp)
                hits.append(hit)
        except Exception:
            # A broken rule is equivalent to an unavailable rule set. Never
            # continue with a partial result or expose health input/exception
            # details through the response or ordinary logs.
            return self._unavailable(answer_tuple, timestamp)
        matched = [hit for hit in hits if hit.result == "matched"]
        unresolved = [hit for hit in hits if hit.result == "undetermined"]
        highest = self._highest_tier(matched)
        triggered_ids = self._unique(hit.rule_id for hit in matched)
        required_question_ids = self._required_questions(unresolved)

        if unresolved:
            if matched:
                outcome = "triggered"
                tier: SafetyTier = highest or "undetermined"
            else:
                outcome = "unresolved"
                tier = "undetermined"
            status = "incomplete"
            ordinary_allowed = False
            if highest in {"R0", "R1"}:
                # Lower-priority uncertainty may remain visible in the typed
                # gate, but it can never replace an already-determined urgent
                # action. AssessmentService routes R0/R1 before questions.
                action, content_id, release_id, message = self._action_for(matched)
            else:
                action = "SAFETY_CLARIFICATION_REQUIRED"
                content_id = "prototype.safety.clarification"
                release_id = "prototype.none"
                message = "还需要确认安全相关信息；本样机不会把未解决信息当作安全。"
        elif matched:
            outcome = "triggered"
            tier = highest or "undetermined"
            status = "complete"
            ordinary_allowed = False
            action, content_id, release_id, message = self._action_for(matched)
            return SafetyEvaluation(
                status=status,
                tier=tier,
                rule_outcome=outcome,
                triggered_rule_ids=triggered_ids,
                required_question_ids=[],
                rule_set_version=self.catalog.version,
                all_current_rules_executed=True,
                scenario_support="supported" if self.catalog.scenario_supported else "unsupported",
                unresolved_safety=False,
                ordinary_agent_allowed=False,
                answers=list(answer_tuple),
                rule_hits=hits,
                required_action_code=action,
                content_id=content_id,
                content_release_id=release_id,
                display_message=message,
                evaluated_at=timestamp,
            )
        else:
            outcome = "no_rule_triggered"
            tier = "R3"
            status = "complete"
            ordinary_allowed = self.catalog.scenario_supported
            action = None
            content_id = None
            release_id = None
            message = None

        return SafetyEvaluation(
            status=status,
            tier=tier,
            rule_outcome=outcome,
            triggered_rule_ids=triggered_ids,
            required_question_ids=required_question_ids,
            rule_set_version=self.catalog.version,
            all_current_rules_executed=not unresolved,
            scenario_support="supported" if self.catalog.scenario_supported else "unsupported",
            unresolved_safety=bool(unresolved),
            ordinary_agent_allowed=ordinary_allowed,
            answers=list(answer_tuple),
            rule_hits=hits,
            required_action_code=action,
            content_id=content_id,
            content_release_id=release_id,
            display_message=message,
            evaluated_at=timestamp,
        )

    def _catalog_is_executable(self) -> bool:
        catalog = self.catalog
        if not isinstance(catalog, RuleCatalog):
            return False
        if type(catalog.available) is not bool or catalog.available is not True:
            return False
        if type(catalog.scenario_supported) is not bool:
            return False
        if (
            not isinstance(catalog.version, str)
            or not 1 <= len(catalog.version) <= 64
            or IDENTIFIER_PATTERN.fullmatch(catalog.version) is None
        ):
            return False
        if not isinstance(catalog.rules, tuple) or not 1 <= len(catalog.rules) <= 50:
            return False

        for definition in catalog.rules:
            if not isinstance(definition, RuleDefinition):
                return False
            if not isinstance(definition.rule_id, str) or IDENTIFIER_PATTERN.fullmatch(definition.rule_id) is None:
                return False
            if definition.required_question_id is not None and (
                not isinstance(definition.required_question_id, str)
                or IDENTIFIER_PATTERN.fullmatch(definition.required_question_id) is None
            ):
                return False
            if not callable(definition.evaluate):
                return False
            if (
                not isinstance(definition.required_action_code, str)
                or ACTION_PATTERN.fullmatch(definition.required_action_code) is None
                or not isinstance(definition.content_id, str)
                or not 1 <= len(definition.content_id) <= 160
                or not definition.content_id.strip()
                or not isinstance(definition.content_release_id, str)
                or not 1 <= len(definition.content_release_id) <= 64
                or not definition.content_release_id.strip()
                or not isinstance(definition.display_message, str)
                or not 1 <= len(definition.display_message) <= 2000
                or not definition.display_message.strip()
            ):
                return False
        return True

    def _unavailable(
        self,
        answers: tuple[SafetyAnswer, ...],
        timestamp: datetime,
    ) -> SafetyEvaluation:
        version = getattr(self.catalog, "version", None)
        safe_version = (
            version
            if isinstance(version, str)
            and 1 <= len(version) <= 64
            and IDENTIFIER_PATTERN.fullmatch(version) is not None
            else "unknown"
        )
        scenario_supported = getattr(self.catalog, "scenario_supported", False)
        return SafetyEvaluation(
            status="unavailable",
            tier="undetermined",
            rule_outcome="unavailable",
            triggered_rule_ids=[],
            required_question_ids=[],
            rule_set_version=safe_version,
            all_current_rules_executed=False,
            scenario_support="supported" if scenario_supported is True else "unsupported",
            unresolved_safety=True,
            ordinary_agent_allowed=False,
            answers=list(answers),
            rule_hits=[],
            required_action_code="SAFETY_RULES_UNAVAILABLE",
            content_id="prototype.safety.unavailable",
            content_release_id="prototype.none",
            display_message="安全规则暂不可用；本样机不会继续普通分析。",
            evaluated_at=timestamp,
        )

    def _highest_tier(self, hits: Iterable[RuleHit]) -> SafetyTier | None:
        tiers = [hit.tier for hit in hits if hit.tier is not None]
        return max(tiers, key=lambda tier: TIER_RANK[tier]) if tiers else None  # type: ignore[arg-type]

    def _required_questions(self, hits: Iterable[RuleHit]) -> list[str]:
        ids: list[str] = []
        hits = list(hits)
        if not hits:
            return ids
        by_rule = {definition.rule_id: definition for definition in self.catalog.rules}
        for hit in hits:
            definition = by_rule.get(hit.rule_id)
            if definition and definition.required_question_id and definition.required_question_id not in ids:
                ids.append(definition.required_question_id)
        return ids or ["safety.review_required"]

    def _action_for(self, hits: Iterable[RuleHit]) -> tuple[str, str, str, str]:
        by_id = {definition.rule_id: definition for definition in self.catalog.rules}
        highest = max(
            (by_id[hit.rule_id] for hit in hits if hit.rule_id in by_id),
            key=lambda definition: TIER_RANK[next(hit.tier for hit in hits if hit.rule_id == definition.rule_id)],
        )
        return (
            highest.required_action_code,
            highest.content_id,
            highest.content_release_id,
            highest.display_message,
        )

    @staticmethod
    def _unique(values: Iterable[str]) -> list[str]:
        return list(dict.fromkeys(values))
