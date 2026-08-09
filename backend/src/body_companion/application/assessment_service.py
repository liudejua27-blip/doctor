"""Application orchestration for the P1-B assessment slice."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Any, Iterable
from uuid import UUID, uuid4

from ..agents.assessment_agent import AgentDependencies, AgentExecutionError, AssessmentAgentRunner, ToolAuthorizationError
from ..domain.agent_context import AgentReadContext
from ..domain.policy import PolicyValidator, PolicyViolation
from ..domain.safety import SafetyEngine
from ..domain.types import (
    AgentCandidate,
    AgentQuestion,
    AssessmentDraft,
    AskQuestionCandidate,
    DraftCandidate,
    SafetyEnvelope,
    SafetyEvaluation,
    UserTurnInput,
    utc_now,
)


@dataclass(frozen=True)
class AssessmentRequest:
    session_id: UUID
    turn_id: UUID
    user_id: UUID
    sequence: int
    revision: int
    turn_input: UserTurnInput
    source_fact_ids: tuple[str, ...] = ()
    authorized_scopes: frozenset[str] = frozenset()
    agent_context: AgentReadContext | None = None


@dataclass(frozen=True)
class AssessmentOutcome:
    session_id: UUID
    turn_id: UUID
    status: str
    state: str
    evaluation: SafetyEvaluation
    envelope: SafetyEnvelope
    candidate: AgentCandidate | None
    error_code: str | None
    agent_turn: dict[str, Any]


class AssessmentService:
    """Runs safety, then the single Agent, then deterministic policy checks."""

    def __init__(
        self,
        safety_engine: SafetyEngine,
        agent_runner: AssessmentAgentRunner | None = None,
        *,
        policy_validator: PolicyValidator | None = None,
        agent_version: str = "p1b-agent-1",
        prompt_version: str = "p1b-prompt-1",
        ontology_version: str = "body-ontology-pending-review",
    ) -> None:
        self.safety_engine = safety_engine
        self.agent_runner = agent_runner
        self.policy_validator = policy_validator or PolicyValidator()
        self.agent_version = agent_version
        self.prompt_version = prompt_version
        self.ontology_version = ontology_version

    def assess(
        self,
        request: AssessmentRequest,
        *,
        safety_answers: Iterable[Any] = (),
    ) -> AssessmentOutcome:
        user_text = request.turn_input.text or ""
        evaluation = self.safety_engine.evaluate(
            user_text=user_text,
            answers=safety_answers,
            source_fact_ids=request.source_fact_ids,
        )

        if evaluation.tier in {"R0", "R1"}:
            return self._escalation_outcome(request, evaluation)
        if evaluation.status == "incomplete":
            return self._safety_question_outcome(request, evaluation)
        if evaluation.status == "unavailable":
            return self._failure_outcome(request, evaluation, error_code="SAFETY_SERVICE_UNAVAILABLE")
        if evaluation.scenario_support == "unsupported":
            return self._failure_outcome(request, evaluation, error_code="UNSUPPORTED_SCENARIO")
        if not evaluation.ordinary_agent_allowed:
            return self._failure_outcome(request, evaluation, error_code="AGENT_NOT_ALLOWED")
        if self.agent_runner is None:
            return self._failure_outcome(request, evaluation, error_code="MODEL_UNAVAILABLE", mode="manual")

        try:
            dependencies = AgentDependencies(
                authenticated_user_id=request.user_id,
                authorized_scopes=request.authorized_scopes,
                context=request.agent_context or AgentReadContext.empty(request.user_id),
            )
            candidate = self.agent_runner.run_sync(user_text, deps=dependencies)
            candidate = self.policy_validator.validate(
                candidate,
                location_marker_ids=[location.marker_id for location in (request.turn_input.locations or [])],
            )
        except (AgentExecutionError, PolicyViolation, ToolAuthorizationError, ValueError):
            return self._failure_outcome(request, evaluation, error_code="AGENT_OUTPUT_INVALID")

        source_ids = tuple(dict.fromkeys((*request.source_fact_ids, *dependencies.read_audit.source_ids)))
        return self._candidate_outcome(request, evaluation, candidate, source_ids=source_ids)

    def _candidate_outcome(
        self,
        request: AssessmentRequest,
        evaluation: SafetyEvaluation,
        candidate: AgentCandidate,
        *,
        source_ids: Iterable[str] | None = None,
    ) -> AssessmentOutcome:
        envelope = self._envelope(evaluation, mode="normal", source_ids=source_ids or request.source_fact_ids)
        if isinstance(candidate, AskQuestionCandidate):
            status = "awaiting_user"
            state = "awaiting_user"
            allowed = ["answer_question", "save_unconfirmed_draft"]
            output = candidate.model_dump(mode="json", exclude_none=True)
        else:
            status = "draft_ready"
            state = "awaiting_confirmation"
            allowed = ["review_draft", "confirm_facts", "edit_draft", "save_unconfirmed_draft"]
            output = candidate.model_dump(mode="json", exclude_none=True)
            envelope = self._envelope(
                evaluation,
                mode="normal",
                source_ids=source_ids or request.source_fact_ids,
                unconfirmed=[
                    {"item_id": "draft.body_signal", "category": "body_signal", "display_text": "待用户确认的身体信号草稿"}
                ],
            )

        turn = self._turn(
            request,
            evaluation,
            status=status,
            state=state,
            output=output,
            output_origin="agent",
            envelope=envelope,
            allowed_actions=allowed,
            include_model_versions=True,
        )
        return AssessmentOutcome(
            request.session_id,
            request.turn_id,
            status,
            state,
            evaluation,
            envelope,
            candidate,
            None,
            turn,
        )

    def _escalation_outcome(self, request: AssessmentRequest, evaluation: SafetyEvaluation) -> AssessmentOutcome:
        tier = evaluation.tier
        mode = "emergency" if tier == "R0" else "urgent"
        output = {
            "kind": "escalation",
            "tier": tier,
            "trigger_categories": evaluation.triggered_rule_ids or ["prototype.rule"],
            "required_action_code": evaluation.required_action_code or "PROFESSIONAL_HELP_REQUIRED",
            "content_id": evaluation.content_id or "prototype.action.unconfigured",
            "content_release_id": evaluation.content_release_id or "prototype.none",
            "display_message": evaluation.display_message or "请查看审核后的安全行动入口；本样机不提供普通分析。",
            "ordinary_advice_suppressed": True,
            "rule_set_version": evaluation.rule_set_version,
            "record_review_available": False,
        }
        envelope = self._envelope(evaluation, mode=mode, source_ids=request.source_fact_ids)
        allowed = ["get_emergency_help"] if tier == "R0" else ["get_professional_help"]
        turn = self._turn(
            request,
            evaluation,
            status="escalated",
            state="escalated",
            output=output,
            output_origin="application",
            envelope=envelope,
            allowed_actions=allowed,
            include_model_versions=False,
        )
        return AssessmentOutcome(
            request.session_id,
            request.turn_id,
            "escalated",
            "escalated",
            evaluation,
            envelope,
            None,
            None,
            turn,
        )

    def _safety_question_outcome(self, request: AssessmentRequest, evaluation: SafetyEvaluation) -> AssessmentOutcome:
        questions = [
            AgentQuestion(
                question_id=question_id,
                category="safety",
                prompt="请回答已配置的安全核对问题（样机占位，不代表临床问法）。",
                answer_type="boolean",
                required=True,
                why_asked="安全信息尚未完成，不能直接进入普通分析。",
            )
            for question_id in evaluation.required_question_ids
        ]
        output = AskQuestionCandidate(
            questions=questions,
            context_summary="安全信息尚未完成；请先完成必要核对。",
        ).model_dump(mode="json", exclude_none=True)
        envelope = self._envelope(evaluation, mode="degraded", source_ids=request.source_fact_ids)
        turn = self._turn(
            request,
            evaluation,
            status="awaiting_user",
            state="awaiting_user",
            output=output,
            output_origin="application",
            envelope=envelope,
            allowed_actions=["answer_question", "save_unconfirmed_draft"],
            include_model_versions=False,
        )
        return AssessmentOutcome(
            request.session_id,
            request.turn_id,
            "awaiting_user",
            "awaiting_user",
            evaluation,
            envelope,
            None,
            None,
            turn,
        )

    def _failure_outcome(
        self,
        request: AssessmentRequest,
        evaluation: SafetyEvaluation,
        *,
        error_code: str,
        mode: str = "degraded",
    ) -> AssessmentOutcome:
        fallback = "retry_later" if error_code in {"MODEL_UNAVAILABLE", "AGENT_OUTPUT_INVALID"} else "show_professional_help"
        output = {
            "kind": "safe_failure",
            "display_message": "当前无法完成普通分析；已保留输入并提供安全回退入口。",
            "input_preserved": True,
            "safety_fallback": fallback,
        }
        envelope = self._envelope(evaluation, mode=mode, source_ids=request.source_fact_ids)
        actions = ["retry", "save_unconfirmed_draft"] if fallback == "retry_later" else ["get_professional_help"]
        turn = self._turn(
            request,
            evaluation,
            status="failed",
            state="failed",
            output=output,
            output_origin="application",
            envelope=envelope,
            allowed_actions=actions,
            include_model_versions=False,
        )
        return AssessmentOutcome(
            request.session_id,
            request.turn_id,
            "failed",
            "failed",
            evaluation,
            envelope,
            None,
            error_code,
            turn,
        )

    def _envelope(
        self,
        evaluation: SafetyEvaluation,
        *,
        mode: str,
        source_ids: Iterable[str],
        unconfirmed: list[dict[str, str]] | None = None,
    ) -> SafetyEnvelope:
        return SafetyEnvelope(
            mode=mode,  # type: ignore[arg-type]
            confirmed_facts=[],
            unconfirmed_items=unconfirmed or [],
            safety={
                "tier": evaluation.tier,
                "rule_outcome": evaluation.rule_outcome,
                "triggered_rule_ids": evaluation.triggered_rule_ids,
            },
            possible_contributors=[],
            next_steps=[],
            data_sources_used=list(dict.fromkeys(source_ids)),
            uncertainty_statement_id="content.uncertainty.not_a_diagnosis",
            ai_identity_label_id="content.ai_assisted",
            safetyBaselineId="P1B-PROTOTYPE-NOT-RELEASED",
        )

    def _turn(
        self,
        request: AssessmentRequest,
        evaluation: SafetyEvaluation,
        *,
        status: str,
        state: str,
        output: dict[str, Any],
        output_origin: str,
        envelope: SafetyEnvelope,
        allowed_actions: list[str],
        include_model_versions: bool,
    ) -> dict[str, Any]:
        now = utc_now()
        versions: dict[str, Any] = {
            "pydantic_ai_version": "2.23.0",
            "agent_version": self.agent_version,
            "output_schema_version": "1.0",
            "ontology_version": self.ontology_version,
            "rule_set_version": evaluation.rule_set_version,
        }
        if include_model_versions:
            versions.update({"prompt_version": self.prompt_version, "provider": "injected", "model_name": "prototype"})

        gate = {
            "status": evaluation.status,
            "tier": evaluation.tier,
            "rule_outcome": evaluation.rule_outcome,
            "triggered_rule_ids": evaluation.triggered_rule_ids,
            "required_question_ids": evaluation.required_question_ids,
            "rule_set_version": evaluation.rule_set_version,
            "all_current_rules_executed": evaluation.all_current_rules_executed,
            "scenario_support": evaluation.scenario_support,
            "unresolved_safety": evaluation.unresolved_safety,
            "ordinary_agent_allowed": evaluation.ordinary_agent_allowed,
            "evaluated_at": evaluation.evaluated_at.isoformat(),
        }
        return {
            "schema_version": "1.0",
            "session_id": str(request.session_id),
            "turn_id": str(request.turn_id),
            "sequence": request.sequence,
            "revision": request.revision,
            "workflow": "assessment",
            "status": status,
            "state": state,
            "input": request.turn_input.model_dump(mode="json", exclude_none=True),
            "deterministic_safety_gate": gate,
            "output": output,
            "output_origin": output_origin,
            "safety_envelope": envelope.model_dump(mode="json", exclude_none=True),
            "allowed_actions": allowed_actions,
            "versions": versions,
            "request_id": str(uuid4()),
            "created_at": now.isoformat(),
            "updated_at": now.isoformat(),
        }
