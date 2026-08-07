"""Typed result boundary for the P1G P1F-to-Agent handoff.

The result intentionally contains only an unconfirmed Agent candidate or a
fixed, content-free fallback.  It never carries identity, raw prompt text,
provider details, hidden reasoning, or formal resource references.
"""

from __future__ import annotations

from typing import Literal
from uuid import UUID

from pydantic import Field, model_validator

from .ios_signal_intake import IOSApplicationHandoffStatus, IOSSignalIntakeApplicationHandoff
from .types import AgentCandidate, StrictModel


P1GAgentResultStatus = Literal[
    "agent_completed",
    "agent_output_rejected",
    "agent_unavailable",
    "safety_action_required",
    "offline_only",
    "rejected",
]


class P1GAgentHandoffResult(StrictModel):
    """Internal P1G result; a candidate is never a confirmed body fact."""

    schema_version: Literal["1.0"] = "1.0"
    session_id: UUID
    draft_revision: int = Field(ge=1)
    status: P1GAgentResultStatus
    handoff_status: IOSApplicationHandoffStatus
    candidate: AgentCandidate | None = None
    agent_source_ids: list[str] = Field(default_factory=list, max_length=100)
    agent_version: str | None = Field(default=None, min_length=1, max_length=64)
    prompt_version: str | None = Field(default=None, min_length=1, max_length=64)
    error_code: str | None = Field(default=None, pattern=r"^[A-Z0-9._-]{1,120}$")

    @model_validator(mode="after")
    def validate_result_shape(self) -> "P1GAgentHandoffResult":
        if self.status == "agent_completed":
            if self.handoff_status != "ready_for_agent" or self.candidate is None:
                raise ValueError("completed Agent result requires a ready handoff and candidate")
            if self.agent_version is None or self.prompt_version is None:
                raise ValueError("completed Agent result requires version metadata")
            if self.error_code is not None:
                raise ValueError("completed Agent result cannot carry an error")
        elif self.candidate is not None:
            raise ValueError("non-completed Agent result cannot carry a candidate")

        if self.status == "safety_action_required" and self.handoff_status != "safety_action_required":
            raise ValueError("safety result must preserve P1F safety status")
        if self.status == "offline_only" and self.handoff_status != "offline_only":
            raise ValueError("offline result must preserve P1F offline status")
        if self.status == "rejected":
            if self.handoff_status != "rejected" or self.error_code is None:
                raise ValueError("rejected result requires the rejected handoff and fixed error")
        if self.status in {"agent_output_rejected", "agent_unavailable"} and self.error_code is None:
            raise ValueError("Agent failure result requires a fixed error code")
        if self.status != "agent_completed" and self.status not in {"agent_output_rejected", "agent_unavailable"}:
            if self.agent_version is not None or self.prompt_version is not None:
                raise ValueError("non-Agent result cannot carry model metadata")
        return self


def result_from_p1f(handoff: IOSSignalIntakeApplicationHandoff) -> P1GAgentHandoffResult:
    """Map a non-ready P1F result without allowing an Agent call."""

    if handoff.status == "ready_for_agent":
        # A model-constructed or otherwise incomplete ready envelope is not an
        # Agent permission.  Keep the P1G result internally consistent and fail
        # closed instead of echoing a forged ready status.
        return P1GAgentHandoffResult(
            session_id=handoff.session_id,
            draft_revision=handoff.draft_revision,
            status="rejected",
            handoff_status="rejected",
            error_code="P1F_NOT_AGENT_READY",
        )
    if handoff.status == "safety_action_required":
        status: P1GAgentResultStatus = "safety_action_required"
    elif handoff.status == "offline_only":
        status = "offline_only"
    else:
        status = "rejected"
    return P1GAgentHandoffResult(
        session_id=handoff.session_id,
        draft_revision=handoff.draft_revision,
        status=status,
        handoff_status=handoff.status,
        error_code=handoff.error_code if status == "rejected" else handoff.error_code,
    )
