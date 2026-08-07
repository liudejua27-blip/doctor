"""P1F Application Service handoff for the iOS signal-intake projection.

This module owns the order ``P1E structural gate -> current SafetyEngine ->
P1E server-safety mapping``.  It deliberately stops before PydanticAI, formal
resources, repositories, or public HTTP routes.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from uuid import UUID, uuid4

from ..domain.ios_signal_intake import (
    IOSSignalIntakeAdapterResult,
    IOSSignalIntakeApplicationHandoff,
    IOSSignalIntakeDraft,
    IOSApplicationHandoffStatus,
    IOSServerSafetyProjection,
    adapt_ios_signal_intake,
)
from ..domain.safety import SafetyEngine
from ..domain.types import SafetyAnswer, SafetyEvaluation, utc_now


@dataclass(frozen=True)
class IOSSignalIntakeApplicationRequest:
    """Trusted internal request after the API/application owner check.

    The caller must bind the session owner and revision before constructing this
    value.  No user ID is carried into the handoff result.
    """

    draft: IOSSignalIntakeDraft
    expected_session_id: UUID
    expected_draft_revision: int
    safety_answers: tuple[SafetyAnswer, ...] = ()
    request_id: UUID = field(default_factory=uuid4, compare=False)


class IOSSignalIntakeApplicationService:
    """Run the P1F safety-first handoff without invoking an Agent."""

    def __init__(self, safety_engine: SafetyEngine) -> None:
        self.safety_engine = safety_engine

    def handoff(self, request: IOSSignalIntakeApplicationRequest) -> IOSSignalIntakeApplicationHandoff:
        if not isinstance(request.draft, IOSSignalIntakeDraft):
            return IOSSignalIntakeApplicationHandoff(
                session_id=request.expected_session_id,
                draft_revision=max(request.expected_draft_revision, 1),
                status="rejected",
                client_safety_status="not_run",
                error_code="INTAKE_INVALID_PAYLOAD",
            )

        draft = request.draft
        structural = adapt_ios_signal_intake(
            draft,
            expected_session_id=request.expected_session_id,
            expected_draft_revision=request.expected_draft_revision,
        )
        if structural.status == "rejected":
            return self._rejected_from_adapter(structural)
        if structural.status != "needs_safety_precheck":
            return self._rejected(
                draft,
                "INTAKE_UNEXPECTED_STRUCTURAL_STATUS",
            )

        try:
            evaluation = self.safety_engine.evaluate(
                # The full text is transient input to the deterministic rules;
                # it is never copied to a result, error, or ordinary log.
                user_text=draft.facts.raw_user_text or "",
                answers=request.safety_answers,
                source_fact_ids=(f"ios-signal-intake:{draft.session_id}:draft:{draft.draft_revision}",),
            )
        except Exception:  # noqa: BLE001 - fail closed without provider/rule details
            evaluation = self._unavailable_evaluation()
            return self._from_evaluation(
                draft,
                evaluation,
                status="offline_only",
                error_code="SAFETY_PRECHECK_UNAVAILABLE",
            )

        mapped = adapt_ios_signal_intake(
            draft,
            expected_session_id=request.expected_session_id,
            expected_draft_revision=request.expected_draft_revision,
            server_safety=evaluation,
        )
        return self._from_adapter_with_evaluation(mapped, evaluation, draft)

    def _from_adapter_with_evaluation(
        self,
        mapped: IOSSignalIntakeAdapterResult,
        evaluation: SafetyEvaluation,
        draft: IOSSignalIntakeDraft,
    ) -> IOSSignalIntakeApplicationHandoff:
        if mapped.status == "ready_for_agent" and mapped.assessment_draft is not None:
            return IOSSignalIntakeApplicationHandoff(
                session_id=draft.session_id,
                draft_revision=draft.draft_revision,
                status="ready_for_agent",
                client_safety_status=draft.safety.status,
                server_safety=IOSServerSafetyProjection.from_evaluation(evaluation),
                assessment_draft=mapped.assessment_draft,
            )
        if mapped.status == "offline_only":
            return self._from_evaluation(
                draft,
                evaluation,
                status="offline_only",
                error_code="SAFETY_PRECHECK_UNAVAILABLE",
            )
        if mapped.status == "safety_action_required":
            return self._from_evaluation(
                draft,
                evaluation,
                status="safety_action_required",
            )
        if mapped.status == "rejected":
            return self._rejected_from_adapter(mapped)
        return self._from_evaluation(
            draft,
            evaluation,
            status="offline_only",
            error_code="INTAKE_UNEXPECTED_ADAPTER_STATUS",
        )

    def _from_evaluation(
        self,
        draft: IOSSignalIntakeDraft,
        evaluation: SafetyEvaluation,
        *,
        status: IOSApplicationHandoffStatus,
        error_code: str | None = None,
    ) -> IOSSignalIntakeApplicationHandoff:
        return IOSSignalIntakeApplicationHandoff(
            session_id=draft.session_id,
            draft_revision=draft.draft_revision,
            status=status,
            client_safety_status=draft.safety.status,
            server_safety=IOSServerSafetyProjection.from_evaluation(evaluation),
            error_code=error_code,
        )

    @staticmethod
    def _rejected_from_adapter(result: IOSSignalIntakeAdapterResult) -> IOSSignalIntakeApplicationHandoff:
        return IOSSignalIntakeApplicationHandoff(
            session_id=result.session_id,
            draft_revision=result.draft_revision,
            status="rejected",
            client_safety_status=result.client_safety_status,
            error_code=result.error_code or "INTAKE_INVALID_PAYLOAD",
        )

    @staticmethod
    def _rejected(draft: IOSSignalIntakeDraft, error_code: str) -> IOSSignalIntakeApplicationHandoff:
        return IOSSignalIntakeApplicationHandoff(
            session_id=draft.session_id,
            draft_revision=draft.draft_revision,
            status="rejected",
            client_safety_status=draft.safety.status,
            error_code=error_code,
        )

    def _unavailable_evaluation(self) -> SafetyEvaluation:
        return SafetyEvaluation(
            status="unavailable",
            tier="undetermined",
            rule_outcome="unavailable",
            triggered_rule_ids=[],
            required_question_ids=[],
            rule_set_version=self.safety_engine.catalog.version or "unknown",
            all_current_rules_executed=False,
            scenario_support="supported" if self.safety_engine.catalog.scenario_supported else "unsupported",
            unresolved_safety=True,
            ordinary_agent_allowed=False,
            answers=[],
            rule_hits=[],
            required_action_code="SAFETY_PRECHECK_UNAVAILABLE",
            content_id="prototype.safety.unavailable",
            content_release_id="prototype.none",
            evaluated_at=utc_now(),
        )
