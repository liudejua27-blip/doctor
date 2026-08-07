"""Typed transient result for the P1H Agent Turn Application boundary.

P1H is deliberately smaller than the persisted/public ``AgentTurn`` model.
It carries a P1G candidate or a fixed failure while keeping session ordering,
revision and predecessor metadata explicit.  It never carries identity, raw
input, prompts or formal resource references.
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import Field, model_validator

from .agent_handoff import P1GAgentResultStatus, P1GAgentHandoffResult
from .ios_signal_intake import IOSApplicationHandoffStatus
from .types import AgentCandidate, StrictModel, utc_now


AgentTurnApplicationState = Literal[
    "awaiting_user",
    "awaiting_confirmation",
    "safety_action_required",
    "offline_only",
    "failed",
    "rejected",
]


class AgentTurnApplicationResult(StrictModel):
    """The stable, content-minimal P1H result stored in the transient ledger."""

    schema_version: Literal["1.0"] = "1.0"
    session_id: UUID
    turn_id: UUID
    sequence: int = Field(ge=1)
    draft_revision: int = Field(ge=1)
    in_reply_to_turn_id: UUID | None = None
    status: Literal["accepted", "rejected"]
    state: AgentTurnApplicationState
    handoff_status: IOSApplicationHandoffStatus
    agent_result_status: P1GAgentResultStatus
    candidate: AgentCandidate | None = None
    agent_source_ids: list[str] = Field(default_factory=list, max_length=100)
    agent_version: str | None = Field(default=None, min_length=1, max_length=64)
    prompt_version: str | None = Field(default=None, min_length=1, max_length=64)
    error_code: str | None = Field(default=None, pattern=r"^[A-Z0-9._-]{1,120}$")
    created_at: datetime = Field(default_factory=utc_now)

    @model_validator(mode="after")
    def validate_result_shape(self) -> "AgentTurnApplicationResult":
        if self.status == "rejected":
            if self.state != "rejected" or self.handoff_status != "rejected":
                raise ValueError("rejected P1H result must use rejected state and handoff")
            if self.agent_result_status != "rejected" or self.error_code is None:
                raise ValueError("rejected P1H result requires rejected Agent status and error")
            if self.candidate is not None or self.agent_version is not None or self.prompt_version is not None:
                raise ValueError("rejected P1H result cannot carry Agent output")
            return self

        if self.error_code is not None and self.agent_result_status == "agent_completed":
            raise ValueError("completed P1H result cannot carry an error")
        if self.agent_result_status == "agent_completed":
            if self.handoff_status != "ready_for_agent" or self.candidate is None:
                raise ValueError("completed P1H result requires a ready handoff and candidate")
            if self.agent_version is None or self.prompt_version is None:
                raise ValueError("completed P1H result requires Agent version metadata")
            expected_state = "awaiting_user" if self.candidate.kind == "ask_question" else "awaiting_confirmation"
            if self.state != expected_state:
                raise ValueError("P1H state does not match candidate kind")
        elif self.agent_result_status in {"agent_output_rejected", "agent_unavailable"}:
            if self.handoff_status != "ready_for_agent" or self.state != "failed" or self.error_code is None:
                raise ValueError("Agent failure P1H result has an invalid state")
            if self.candidate is not None or self.agent_version is not None or self.prompt_version is not None:
                raise ValueError("Agent failure P1H result cannot carry output metadata")
        elif self.agent_result_status == "safety_action_required":
            if self.handoff_status != "safety_action_required" or self.state != "safety_action_required":
                raise ValueError("safety P1H result must preserve the P1F safety state")
            if self.candidate is not None or self.agent_version is not None or self.prompt_version is not None:
                raise ValueError("safety P1H result cannot carry Agent metadata")
        elif self.agent_result_status == "offline_only":
            if self.handoff_status != "offline_only" or self.state != "offline_only":
                raise ValueError("offline P1H result must preserve the P1F offline state")
            if self.candidate is not None or self.agent_version is not None or self.prompt_version is not None:
                raise ValueError("offline P1H result cannot carry Agent metadata")
        else:
            raise ValueError("accepted P1H result cannot carry rejected Agent status")
        return self


def result_from_p1g(
    *,
    p1g: P1GAgentHandoffResult,
    turn_id: UUID,
    sequence: int,
    in_reply_to_turn_id: UUID | None,
) -> AgentTurnApplicationResult:
    """Map the P1G result without widening its trust or output surface."""

    if p1g.status == "agent_completed":
        assert p1g.candidate is not None
        state: AgentTurnApplicationState = (
            "awaiting_user" if p1g.candidate.kind == "ask_question" else "awaiting_confirmation"
        )
        return AgentTurnApplicationResult(
            session_id=p1g.session_id,
            turn_id=turn_id,
            sequence=sequence,
            draft_revision=p1g.draft_revision,
            in_reply_to_turn_id=in_reply_to_turn_id,
            status="accepted",
            state=state,
            handoff_status=p1g.handoff_status,
            agent_result_status=p1g.status,
            candidate=p1g.candidate,
            agent_source_ids=p1g.agent_source_ids,
            agent_version=p1g.agent_version,
            prompt_version=p1g.prompt_version,
        )

    if p1g.status == "safety_action_required":
        state = "safety_action_required"
    elif p1g.status == "offline_only":
        state = "offline_only"
    elif p1g.status in {"agent_output_rejected", "agent_unavailable"}:
        state = "failed"
    else:
        return AgentTurnApplicationResult(
            session_id=p1g.session_id,
            turn_id=turn_id,
            sequence=sequence,
            draft_revision=p1g.draft_revision,
            in_reply_to_turn_id=in_reply_to_turn_id,
            status="rejected",
            state="rejected",
            handoff_status="rejected",
            agent_result_status="rejected",
            error_code=p1g.error_code or "P1F_NOT_AGENT_READY",
        )

    return AgentTurnApplicationResult(
        session_id=p1g.session_id,
        turn_id=turn_id,
        sequence=sequence,
        draft_revision=p1g.draft_revision,
        in_reply_to_turn_id=in_reply_to_turn_id,
        status="accepted",
        state=state,
        handoff_status=p1g.handoff_status,
        agent_result_status=p1g.status,
        agent_source_ids=p1g.agent_source_ids,
        error_code=p1g.error_code,
    )


def rejected_result(
    *,
    session_id: UUID,
    turn_id: UUID,
    sequence: int,
    draft_revision: int,
    in_reply_to_turn_id: UUID | None,
    error_code: str,
) -> AgentTurnApplicationResult:
    return AgentTurnApplicationResult(
        session_id=session_id,
        turn_id=turn_id,
        sequence=max(sequence, 1),
        draft_revision=max(draft_revision, 1),
        in_reply_to_turn_id=in_reply_to_turn_id,
        status="rejected",
        state="rejected",
        handoff_status="rejected",
        agent_result_status="rejected",
        error_code=error_code,
    )
