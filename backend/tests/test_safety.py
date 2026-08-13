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


def test_available_but_empty_catalog_is_fail_closed() -> None:
    result = SafetyEngine(RuleCatalog(version="rules.empty", available=True, rules=())).evaluate(
        user_text="synthetic"
    )
    assert result.status == "unavailable"
    assert result.tier == "undetermined"
    assert result.rule_outcome == "unavailable"
    assert result.all_current_rules_executed is False
    assert result.unresolved_safety is True
    assert result.ordinary_agent_allowed is False


def test_duplicate_rule_ids_fail_closed_before_any_rule_runs() -> None:
    calls = 0

    def evaluate(_ctx: SafetyContext) -> RuleHit:
        nonlocal calls
        calls += 1
        return hit("rule.duplicate", "not_matched")

    definition = RuleDefinition(
        rule_id="rule.duplicate",
        required_question_id=None,
        evaluate=evaluate,
        required_action_code="PROTOTYPE_ACTION",
        content_id="prototype.action.unconfigured",
        content_release_id="prototype.none",
        display_message="synthetic",
    )
    result = SafetyEngine(
        RuleCatalog(version="rules.duplicate", available=True, rules=(definition, definition))
    ).evaluate(user_text="synthetic")

    assert result.status == "unavailable"
    assert result.ordinary_agent_allowed is False
    assert result.rule_hits == []
    assert calls == 0


def test_rule_exception_fails_closed_without_partial_hits() -> None:
    def broken_rule(_ctx: SafetyContext) -> RuleHit:
        raise RuntimeError("synthetic rule failure")

    definition = RuleDefinition(
        rule_id="rule.broken",
        required_question_id=None,
        evaluate=broken_rule,
        required_action_code="PROTOTYPE_ACTION",
        content_id="prototype.action.unconfigured",
        content_release_id="prototype.none",
        display_message="synthetic",
    )
    result = SafetyEngine(
        RuleCatalog(version="rules.broken", available=True, rules=(definition,))
    ).evaluate(user_text="synthetic private text")

    assert result.status == "unavailable"
    assert result.tier == "undetermined"
    assert result.rule_hits == []
    assert result.ordinary_agent_allowed is False
    assert "synthetic private text" not in (result.display_message or "")


def test_mismatched_hit_identity_and_matched_without_tier_fail_closed() -> None:
    mismatched = RuleDefinition(
        rule_id="rule.expected",
        required_question_id=None,
        evaluate=lambda _ctx: hit("rule.other", "not_matched"),
        required_action_code="PROTOTYPE_ACTION",
        content_id="prototype.action.unconfigured",
        content_release_id="prototype.none",
        display_message="synthetic",
    )
    missing_tier = rule("rule.no_tier", "matched", None)

    for definition in (mismatched, missing_tier):
        result = SafetyEngine(
            RuleCatalog(version="rules.invalid", available=True, rules=(definition,))
        ).evaluate(user_text="synthetic")
        assert result.status == "unavailable"
        assert result.rule_hits == []
        assert result.ordinary_agent_allowed is False


def test_malformed_catalog_controls_and_definitions_return_fixed_unavailable() -> None:
    valid = rule("rule.valid", "not_matched", None)
    blank_action_content = RuleDefinition(
        rule_id="rule.blank",
        required_question_id=None,
        evaluate=lambda _ctx: hit("rule.blank", "not_matched"),
        required_action_code="PROTOTYPE_ACTION",
        content_id="prototype.action",
        content_release_id="prototype.none",
        display_message=" ",
    )
    malformed_catalogs = (
        RuleCatalog(version="rules.invalid", available="false", rules=(valid,)),  # type: ignore[arg-type]
        RuleCatalog(version="rules.invalid", available=True, scenario_supported=1, rules=(valid,)),  # type: ignore[arg-type]
        RuleCatalog(version="x" * 65, available=True, rules=(valid,)),
        RuleCatalog(version=" ", available=True, rules=(valid,)),
        RuleCatalog(version="rules.invalid", available=True, rules=(blank_action_content,)),
        RuleCatalog(version="rules.invalid", available=True, rules=(object(),)),  # type: ignore[arg-type]
    )

    for catalog in malformed_catalogs:
        result = SafetyEngine(catalog).evaluate(user_text="synthetic private text")
        assert result.status == "unavailable"
        assert result.tier == "undetermined"
        assert result.rule_set_version in {"rules.invalid", "unknown"}
        assert result.rule_hits == []
        assert result.ordinary_agent_allowed is False
        assert "synthetic private text" not in (result.display_message or "")


def test_constructed_or_semantically_invalid_hits_fail_closed() -> None:
    invalid_hits = (
        RuleHit.model_construct(rule_id="rule.invalid", result="corrupt_result", tier=None, evidence_refs=[]),
        RuleHit.model_construct(rule_id="rule.invalid", result="matched", tier="R0", evidence_refs=[]),
        RuleHit.model_construct(rule_id="rule.invalid", result="not_matched", tier="R0", evidence_refs=[]),
    )

    for invalid_hit in invalid_hits:
        definition = RuleDefinition(
            rule_id="rule.invalid",
            required_question_id=None,
            evaluate=lambda _ctx, invalid_hit=invalid_hit: invalid_hit,
            required_action_code="PROTOTYPE_ACTION",
            content_id="prototype.action.unconfigured",
            content_release_id="prototype.none",
            display_message="synthetic",
        )
        result = SafetyEngine(
            RuleCatalog(version="rules.invalid", available=True, rules=(definition,))
        ).evaluate(user_text="synthetic")
        assert result.status == "unavailable"
        assert result.rule_hits == []
        assert result.ordinary_agent_allowed is False


def test_r0_action_wins_over_lower_priority_unresolved_rule() -> None:
    catalog = RuleCatalog(
        version="rules.priority",
        available=True,
        rules=(
            RuleDefinition(
                rule_id="rule.r0",
                required_question_id=None,
                evaluate=lambda _ctx: RuleHit(
                    rule_id="rule.r0",
                    result="matched",
                    tier="R0",
                    evidence_refs=["input.synthetic"],
                ),
                required_action_code="PROTOTYPE_R0",
                content_id="prototype.r0",
                content_release_id="prototype.release.r0",
                display_message="prototype urgent action",
            ),
            rule("rule.maybe", "undetermined", None, "safety.lower_priority"),
        ),
    )

    result = SafetyEngine(catalog).evaluate(user_text="synthetic")

    assert result.status == "incomplete"
    assert result.tier == "R0"
    assert result.rule_outcome == "triggered"
    assert result.required_question_ids == ["safety.lower_priority"]
    assert result.required_action_code == "PROTOTYPE_R0"
    assert result.content_id == "prototype.r0"
    assert result.content_release_id == "prototype.release.r0"
    assert result.display_message == "prototype urgent action"
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
