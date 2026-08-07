"""Prototype HTTP adapter for the P1-B slice.

This exposes the safety/turn plus two-stage confirmation sample and uses an
explicit prototype header instead of pretending to implement production
OAuth/OIDC. The module must not be enabled outside an isolated development
environment.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any
from uuid import UUID, uuid4

from fastapi import FastAPI, Header, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field

from ..application.assessment_service import AssessmentRequest, AssessmentService
from ..domain.confirmation import (
    ApprovalDecisionRequest,
    ApprovalIntent,
    ConfirmationConflict,
    ConfirmationRequest,
    PrototypeApprovalStore,
)
from ..domain.events import PrototypeEventStore
from ..domain.types import DraftCandidate, SafetyAnswer, UserTurnInput


class StartSessionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    purpose: str = Field(default="body_signal_assessment", pattern="^body_signal_assessment$")


class SubmitTurnRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    turn_input: UserTurnInput
    safety_answers: list[SafetyAnswer] = Field(default_factory=list, max_length=50)
    expected_revision: int = Field(default=1, ge=1)


class PrototypeSession(BaseModel):
    model_config = ConfigDict(extra="forbid")
    session_id: UUID
    user_id: UUID
    purpose: str
    workflow: str = "assessment"
    episode_id: UUID | None = None
    source_event_id: UUID | None = None
    state: str = "created"
    revision: int = 1
    latest_turn_id: UUID | None = None
    allowed_actions: list[str] = Field(default_factory=lambda: ["submit_turn", "close_session"])
    created_at: datetime
    updated_at: datetime
    expires_at: datetime
    # Internal in-memory recovery state; excluded from AssessmentSession JSON.
    latest_turn: dict[str, Any] | None = Field(default=None, exclude=True)


def create_prototype_app(
    service: AssessmentService,
    *,
    event_store: PrototypeEventStore | None = None,
) -> FastAPI:
    app = FastAPI(
        title="AI Body Companion P1-B Prototype",
        version="0.1.0-prototype",
        description="Isolated Phase 1 sample; not a production health service.",
    )
    sessions: dict[UUID, PrototypeSession] = {}
    drafts: dict[UUID, DraftCandidate] = {}
    evaluations: dict[UUID, Any] = {}
    approval_turns: dict[UUID, dict[str, Any]] = {}
    approvals = PrototypeApprovalStore(event_writer=event_store)

    def prototype_user(raw: str | None) -> UUID:
        if not raw:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="prototype user header required")
        try:
            return UUID(raw)
        except ValueError as exc:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="invalid prototype user header") from exc

    @app.get("/health")
    def health() -> dict[str, str]:
        return {
            "status": "prototype",
            "feature_flag": "P2_CONFIRMED_EVENT_STORE_PROTOTYPE"
            if event_store is not None
            else "P1B_AGENT_SAFETY_PROTOTYPE",
        }

    @app.post("/v1/agent/sessions", status_code=status.HTTP_201_CREATED)
    def start_session(
        payload: StartSessionRequest,
        x_prototype_user_id: str | None = Header(default=None),
    ) -> PrototypeSession:
        user_id = prototype_user(x_prototype_user_id)
        now = datetime.now(timezone.utc)
        session = PrototypeSession(
            session_id=uuid4(),
            user_id=user_id,
            purpose=payload.purpose,
            created_at=now,
            updated_at=now,
            expires_at=now + timedelta(minutes=15),
        )
        sessions[session.session_id] = session
        return session

    @app.get("/v1/agent/sessions/{session_id}")
    def get_session(session_id: UUID, x_prototype_user_id: str | None = Header(default=None)) -> PrototypeSession:
        user_id = prototype_user(x_prototype_user_id)
        return _owned_session(sessions, session_id, user_id)

    @app.post("/v1/agent/sessions/{session_id}/turns")
    def submit_turn(
        session_id: UUID,
        payload: SubmitTurnRequest,
        x_prototype_user_id: str | None = Header(default=None),
    ) -> dict[str, Any]:
        user_id = prototype_user(x_prototype_user_id)
        session = _owned_session(sessions, session_id, user_id)
        if payload.expected_revision != session.revision:
            raise HTTPException(status_code=status.HTTP_412_PRECONDITION_FAILED, detail="revision mismatch")
        request = AssessmentRequest(
            session_id=session.session_id,
            turn_id=uuid4(),
            user_id=user_id,
            sequence=1 if session.latest_turn is None else int(session.latest_turn["sequence"]) + 1,
            revision=session.revision + 1,
            turn_input=payload.turn_input,
        )
        outcome = service.assess(request, safety_answers=payload.safety_answers)
        latest_turn = outcome.agent_turn
        next_state = outcome.state
        updated = session.model_copy(
            update={
                "state": next_state,
                "revision": session.revision + 1,
                "latest_turn_id": UUID(latest_turn["turn_id"]),
                "updated_at": datetime.now(timezone.utc),
                "latest_turn": latest_turn,
                "allowed_actions": _allowed_actions_for_state(next_state, outcome.evaluation.tier),
            }
        )
        sessions[session_id] = updated
        evaluations[session_id] = outcome.evaluation
        if isinstance(outcome.candidate, DraftCandidate):
            drafts[session_id] = outcome.candidate
        return {"session": updated.model_dump(mode="json"), "turn": latest_turn}

    @app.post("/v1/agent/sessions/{session_id}/confirmations", status_code=status.HTTP_201_CREATED)
    def request_confirmation(
        session_id: UUID,
        payload: ConfirmationRequest,
        x_prototype_user_id: str | None = Header(default=None),
    ) -> dict[str, Any]:
        user_id = prototype_user(x_prototype_user_id)
        session = _owned_session(sessions, session_id, user_id)
        candidate = drafts.get(session_id)
        evaluation = evaluations.get(session_id)
        latest_turn = session.latest_turn
        if candidate is None or evaluation is None or latest_turn is None:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="no confirmable draft")
        try:
            intent = approvals.create_intent(
                owner_id=user_id,
                session_id=session_id,
                current_revision=session.revision,
                candidate=candidate,
                source_turn_id=session.latest_turn_id or payload.turn_id,
                confirmation=payload,
                safety=evaluation,
                raw_input=UserTurnInput.model_validate(latest_turn["input"]),
                agent_versions=latest_turn.get("versions", {}),
            )
        except ConfirmationConflict as exc:
            raise _confirmation_http_error(exc) from exc

        approval_turn = _approval_turn(latest_turn, intent.approval, session.revision + 1)
        updated = session.model_copy(
            update={
                "state": "awaiting_approval",
                "revision": session.revision + 1,
                "latest_turn_id": UUID(approval_turn["turn_id"]),
                "updated_at": datetime.now(timezone.utc),
                "latest_turn": approval_turn,
                "allowed_actions": ["review_approval", "approve_action", "deny_action", "close_session"],
            }
        )
        sessions[session_id] = updated
        approval_turns[intent.approval.approval_id] = approval_turn
        return {
            "approval": intent.approval.model_dump(mode="json", exclude_none=True),
            "session": updated.model_dump(mode="json"),
            "latest_turn": approval_turn,
        }

    @app.get("/v1/approvals/{approval_id}")
    def get_approval(
        approval_id: UUID,
        x_prototype_user_id: str | None = Header(default=None),
    ) -> dict[str, Any]:
        user_id = prototype_user(x_prototype_user_id)
        try:
            intent = approvals.get(owner_id=user_id, approval_id=approval_id)
            decision_result = approvals.get_result(owner_id=user_id, approval_id=approval_id)
        except ConfirmationConflict as exc:
            raise _confirmation_http_error(exc) from exc
        return {
            "approval": intent.approval.model_dump(mode="json", exclude_none=True),
            "decision_result": decision_result.model_dump(mode="json", exclude_none=True)
            if decision_result is not None
            else None,
        }

    @app.post("/v1/approvals/{approval_id}/decisions")
    def decide_approval(
        approval_id: UUID,
        payload: ApprovalDecisionRequest,
        x_prototype_user_id: str | None = Header(default=None),
        idempotency_key: str | None = Header(default=None, alias="Idempotency-Key"),
    ) -> dict[str, Any]:
        user_id = prototype_user(x_prototype_user_id)
        if not idempotency_key:
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Idempotency-Key required")
        try:
            intent = approvals.get(owner_id=user_id, approval_id=approval_id)
        except ConfirmationConflict as exc:
            raise _confirmation_http_error(exc) from exc
        session = _owned_session(sessions, intent.approval.source_session_id, user_id)
        latest_turn = approval_turns.get(approval_id) or session.latest_turn or {}
        try:
            result = approvals.decide(
                owner_id=user_id,
                approval_id=approval_id,
                request=payload,
                idempotency_key=idempotency_key,
                # The confirmation intent is bound to the session revision
                # before the approval-required lifecycle increment.
                current_session_revision=session.revision - 1,
                session_snapshot=session.model_dump(mode="json"),
                latest_turn=latest_turn,
            )
        except ConfirmationConflict as exc:
            raise _confirmation_http_error(exc) from exc

        # Apply the terminal projection at most once. Replays return the
        # stored result and cannot create another event or increment revision.
        if session.state == "awaiting_approval":
            if result.status == "executed":
                next_state = "completed"
                actions = ["view_record", "start_new_session", "close_session"]
                terminal_turn = _completed_turn(latest_turn, result, session.revision + 1)
            elif result.status == "denied":
                next_state = "awaiting_confirmation"
                actions = ["review_draft", "confirm_facts", "edit_draft", "close_session"]
                terminal_turn = _denied_turn(latest_turn, result, drafts.get(session.session_id), session.revision + 1)
            else:
                next_state = "failed"
                actions = ["retry", "save_unconfirmed_draft", "close_session"]
                terminal_turn = _failed_decision_turn(latest_turn, result, session.revision + 1)
            event_episode_id = session.episode_id
            event_source_id = session.source_event_id
            if result.status == "executed" and event_store is not None and result.result_refs:
                event_id = result.result_refs[0].id
                committed_event = event_store.get_event(owner_id=user_id, event_id=event_id)
                event_episode_id = committed_event.episode_id
                event_source_id = committed_event.event_id
            updated = session.model_copy(
                update={
                    "state": next_state,
                    "revision": session.revision + 1,
                    "latest_turn_id": UUID(terminal_turn["turn_id"]),
                    "updated_at": datetime.now(timezone.utc),
                    "latest_turn": terminal_turn,
                    "allowed_actions": actions,
                    "episode_id": event_episode_id,
                    "source_event_id": event_source_id,
                }
            )
            sessions[session.session_id] = updated
            approval_turns[approval_id] = terminal_turn
            result = approvals.update_terminal_projection(
                owner_id=user_id,
                approval_id=approval_id,
                session_snapshot=updated.model_dump(mode="json"),
                latest_turn=terminal_turn,
            )
        return result.model_dump(mode="json", exclude_none=True)

    @app.get("/v1/body-signal-events/{event_id}")
    def get_event(event_id: UUID, x_prototype_user_id: str | None = Header(default=None)) -> dict[str, Any]:
        user_id = prototype_user(x_prototype_user_id)
        if event_store is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="event store disabled")
        try:
            event = event_store.get_event(owner_id=user_id, event_id=event_id)
        except ConfirmationConflict as exc:
            raise _confirmation_http_error(exc) from exc
        return event.model_dump(mode="json", exclude_none=True)

    @app.get("/v1/episodes/{episode_id}")
    def get_episode(episode_id: UUID, x_prototype_user_id: str | None = Header(default=None)) -> dict[str, Any]:
        user_id = prototype_user(x_prototype_user_id)
        if event_store is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="event store disabled")
        try:
            episode = event_store.get_episode(owner_id=user_id, episode_id=episode_id)
            event_refs = event_store.event_refs_for_episode(owner_id=user_id, episode_id=episode_id)
        except ConfirmationConflict as exc:
            raise _confirmation_http_error(exc) from exc
        return {
            **episode.model_dump(mode="json", exclude_none=False),
            "event_refs": event_refs,
            "page": {"next_cursor": None, "has_more": False},
        }

    return app


def create_p2_prototype_app(
    service: AssessmentService,
    *,
    event_store: PrototypeEventStore | None = None,
) -> FastAPI:
    """Opt-in P2 factory; production callers must not import this adapter."""

    return create_prototype_app(service, event_store=event_store or PrototypeEventStore())


def _owned_session(sessions: dict[UUID, PrototypeSession], session_id: UUID, user_id: UUID) -> PrototypeSession:
    session = sessions.get(session_id)
    if session is None or session.user_id != user_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="session not found")
    return session


def _allowed_actions_for_state(state: str, tier: str) -> list[str]:
    if state == "awaiting_user":
        return ["submit_turn", "save_unconfirmed_draft", "close_session"]
    if state == "awaiting_confirmation":
        return ["review_draft", "confirm_facts", "edit_draft", "save_unconfirmed_draft", "close_session"]
    if state == "escalated":
        return ["get_emergency_help" if tier == "R0" else "get_professional_help", "close_session"]
    if state == "failed":
        return ["retry", "save_unconfirmed_draft", "close_session"]
    return ["close_session"]


def _approval_turn(previous: dict[str, Any], approval: ApprovalIntent, revision: int) -> dict[str, Any]:
    now = datetime.now(timezone.utc).isoformat()
    return {
        **previous,
        "turn_id": str(uuid4()),
        "sequence": int(previous.get("sequence", 0)) + 1,
        "revision": revision,
        "status": "approval_required",
        "state": "awaiting_approval",
        "input": {
            "kind": "application_lifecycle",
            "event": "confirmation_created",
            "source_turn_id": previous["turn_id"],
            "approval_id": str(approval.approval_id),
            "approval_status": "pending",
            "occurred_at": now,
        },
        "output_origin": "application",
        "versions": _application_versions(previous.get("versions", {})),
        "output": {
            "kind": "approval_required",
            "approval_id": str(approval.approval_id),
            "action_type": "confirm_body_signal_event",
            "target_ref": {"type": "session", "id": str(approval.source_session_id)},
            "resource_revision": approval.resource_revision,
            "display_summary": approval.display_summary,
            "intent_digest": approval.intent_digest,
            "expires_at": approval.expires_at.isoformat(),
            "approval_revision": 1,
        },
        "allowed_actions": ["review_approval", "approve_action", "deny_action"],
        "created_at": now,
        "updated_at": now,
    }


def _completed_turn(previous: dict[str, Any], result: Any, revision: int) -> dict[str, Any]:
    now = datetime.now(timezone.utc).isoformat()
    return {
        **previous,
        "turn_id": str(uuid4()),
        "sequence": int(previous.get("sequence", 0)) + 1,
        "revision": revision,
        "status": "completed",
        "state": "completed",
        "input": {
            "kind": "application_lifecycle",
            "event": "approval_decided",
            "source_turn_id": previous["turn_id"],
            "approval_id": str(result.approval_id),
            "approval_status": "executed",
            "occurred_at": now,
        },
        "output_origin": "application",
        "versions": _application_versions(previous.get("versions", {})),
        "completed_at": now,
        "safety_envelope": {**previous.get("safety_envelope", {}), "unconfirmed_items": []},
        "output": {
            "kind": "completed",
            "summary": "身体记录已按你的第二次确认保存。",
            "result_refs": [ref.model_dump(mode="json") for ref in result.result_refs],
        },
        "allowed_actions": ["view_record", "start_new_session"],
        "created_at": now,
        "updated_at": now,
    }


def _denied_turn(previous: dict[str, Any], result: Any, candidate: DraftCandidate | None, revision: int) -> dict[str, Any]:
    now = datetime.now(timezone.utc).isoformat()
    output = candidate.model_dump(mode="json", exclude_none=True) if candidate is not None else {
        "kind": "draft_ready",
        "event_draft": {},
        "user_fact_summary": "原草稿仍待复核。",
        "uncertainties": ["draft_not_available"],
        "draft_digest": "sha256:" + "0" * 64,
    }
    return {
        **previous,
        "turn_id": str(uuid4()),
        "sequence": int(previous.get("sequence", 0)) + 1,
        "revision": revision,
        "status": "draft_ready",
        "state": "awaiting_confirmation",
        "input": {
            "kind": "application_lifecycle",
            "event": "approval_decided",
            "source_turn_id": previous["turn_id"],
            "approval_id": str(result.approval_id),
            "approval_status": "denied",
            "occurred_at": now,
        },
        "output_origin": "application",
        "versions": _application_versions(previous.get("versions", {})),
        "output": output,
        "allowed_actions": ["review_draft", "edit_draft", "confirm_facts", "save_unconfirmed_draft"],
        "created_at": now,
        "updated_at": now,
    }


def _failed_decision_turn(previous: dict[str, Any], result: Any, revision: int) -> dict[str, Any]:
    now = datetime.now(timezone.utc).isoformat()
    return {
        **previous,
        "turn_id": str(uuid4()),
        "sequence": int(previous.get("sequence", 0)) + 1,
        "revision": revision,
        "status": "failed",
        "state": "failed",
        "input": {
            "kind": "application_lifecycle",
            "event": "approval_decided",
            "source_turn_id": previous["turn_id"],
            "approval_id": str(result.approval_id),
            "approval_status": result.status,
            "occurred_at": now,
        },
        "output_origin": "application",
        "versions": _application_versions(previous.get("versions", {})),
        "output": {
            "kind": "safe_failure",
            "display_message": "审批上下文已失效；未创建正式身体记录。",
            "input_preserved": True,
            "safety_fallback": "retry_later",
        },
        "errors": [{"code": "INTERNAL_FAILURE", "retryable": False, "display_message": "approval context invalidated"}],
        "safety_envelope": {**previous.get("safety_envelope", {}), "mode": "degraded", "unconfirmed_items": []},
        "allowed_actions": ["retry", "save_unconfirmed_draft"],
        "created_at": now,
        "updated_at": now,
    }


def _confirmation_http_error(exc: ConfirmationConflict) -> HTTPException:
    mapping = {
        "RESOURCE_NOT_FOUND": status.HTTP_404_NOT_FOUND,
        "REVISION_MISMATCH": status.HTTP_412_PRECONDITION_FAILED,
        "DRAFT_DIGEST_MISMATCH": status.HTTP_412_PRECONDITION_FAILED,
        "APPROVAL_REVISION_MISMATCH": status.HTTP_412_PRECONDITION_FAILED,
        "IDEMPOTENCY_CONFLICT": status.HTTP_409_CONFLICT,
        "EVENT_WRITE_FAILED": status.HTTP_503_SERVICE_UNAVAILABLE,
        "EPISODE_NOT_FOUND": status.HTTP_404_NOT_FOUND,
        "EPISODE_SELECTION_INVALID": status.HTTP_409_CONFLICT,
        "EPISODE_NOT_REOPENABLE": status.HTTP_409_CONFLICT,
        "EPISODE_REVISION_MISMATCH": status.HTTP_412_PRECONDITION_FAILED,
        "EVENT_VALIDATION_FAILED": status.HTTP_422_UNPROCESSABLE_ENTITY,
    }
    return HTTPException(status_code=mapping.get(exc.code, status.HTTP_409_CONFLICT), detail=exc.code)


def _application_versions(versions: dict[str, Any]) -> dict[str, Any]:
    return {
        key: value
        for key, value in versions.items()
        if key not in {"prompt_version", "provider", "model_name"}
    }
