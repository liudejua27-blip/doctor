from __future__ import annotations

from datetime import datetime, timezone

from body_companion.domain.safety import RuleCatalog, RuleDefinition, SafetyContext, SafetyEngine
from body_companion.domain.types import RuleHit


def hit(rule_id: str, result: str, tier: str | None = None) -> RuleHit:
    return RuleHit(rule_id=rule_id, result=result, tier=tier, evidence_refs=["input.text"] if result == "matched" else [])


def rule(rule_id: str, result: str, tier: str | None, question: str | None = None) -> RuleDefinition:
    return RuleDefinition(
        rule_id=rule_id,
        required_question_id=question,
        evaluate=lambda _ctx: hit(rule_id, result, tier),
        required_action_code="PROTOTYPE_ACTION",
        content_id="prototype.action.unconfigured",
        content_release_id="prototype.none",
        display_message="样机规则命中；本内容未获生产审核。",
    )


def test_unavailable_catalog_is_fail_closed() -> None:
    result = SafetyEngine(RuleCatalog(version="rules.none", available=False)).evaluate(user_text="我不舒服")
    assert result.status == "unavailable"
    assert result.tier == "undetermined"
    assert result.rule_outcome == "unavailable"
    assert result.ordinary_agent_allowed is False


def test_highest_tier_wins_and_never_allows_agent() -> None:
    catalog = RuleCatalog(
        version="rules.test",
        available=True,
        rules=(rule("rule.r2", "matched", "R2"), rule("rule.r0", "matched", "R0")),
    )
    result = SafetyEngine(catalog).evaluate(user_text="synthetic")
    assert result.tier == "R0"
    assert result.rule_outcome == "triggered"
    assert result.triggered_rule_ids == ["rule.r2", "rule.r0"]
    assert result.ordinary_agent_allowed is False


def test_unresolved_rule_requires_questions_and_cannot_be_normal() -> None:
    catalog = RuleCatalog(
        version="rules.test",
        available=True,
        rules=(rule("rule.maybe", "undetermined", None, "safety.synthetic_question"),),
    )
    result = SafetyEngine(catalog).evaluate(user_text="synthetic")
    assert result.status == "incomplete"
    assert result.rule_outcome == "unresolved"
    assert result.tier == "undetermined"
    assert result.required_question_ids == ["safety.synthetic_question"]
    assert result.ordinary_agent_allowed is False


def test_complete_no_rule_triggered_is_r3_not_safe() -> None:
    catalog = RuleCatalog(version="rules.test", available=True, rules=(rule("rule.no", "not_matched", None),))
    result = SafetyEngine(catalog).evaluate(user_text="synthetic")
    assert result.status == "complete"
    assert result.tier == "R3"
    assert result.rule_outcome == "no_rule_triggered"
    assert result.ordinary_agent_allowed is True
