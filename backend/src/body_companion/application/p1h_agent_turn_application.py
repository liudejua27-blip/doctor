"""P1H transient Agent Turn Application service.

The service is intentionally an internal prototype.  It binds P1F/P1G output
to a monotonic Turn sequence and a process-local idempotency ledger, but it
does not persist messages or create any formal health resource.
"""

from __future__ import annotations

from dataclasses import dataclass, field
import hashlib
import json
import re
from threading import RLock
from uuid import UUID, uuid4

from pydantic import ValidationError

from ..agents.assessment_agent import AssessmentAgentRunner
from ..domain.agent_context import AgentReadContext
from ..domain.agent_handoff import P1GAgentHandoffResult, result_from_p1f
from ..domain.agent_turn_application import (
    AgentTurnApplicationResult,
    rejected_result,
    result_from_p1g,
)
from ..domain.ios_signal_intake import IOSSignalIntakeApplicationHandoff
from ..domain.policy import PolicyValidator
from .p1g_agent_handoff import P1GAgentHandoffRequest, P1GAgentHandoffService


P1H_FEATURE_FLAG = "P1H_AGENT_TURN_APPLICATION_PROTOTYPE"
_IDEMPOTENCY_KEY = re.compile(r"^[\x21-\x7e]{8,128}$")


@dataclass(frozen=True)
class AgentTurnApplicationRequest:
    """Trusted internal input after API/session ownership checks."""

    session_id: UUID
    turn_id: UUID
    sequence: int
    draft_revision: int
    handoff: IOSSignalIntakeApplicationHandoff
    authenticated_user_id: UUID
    idempotency_key: str
    in_reply_to_turn_id: UUID | None = None
    authorized_scopes: frozenset[str] = frozenset()
    agent_context: AgentReadContext | None = None
    request_id: UUID = field(default_factory=uuid4, compare=False)


@dataclass(frozen=True)
class AgentTurnApplicationResponse:
    """Result plus transport-only replay metadata.

    ``replayed`` is deliberately outside ``AgentTurnApplicationResult`` so a
    replay has byte-for-byte stable result content and timestamp.
    """

    result: AgentTurnApplicationResult
    replayed: bool = False


@dataclass(frozen=True)
class _LedgerEntry:
    owner_user_id: UUID
    request_digest: str
    result: AgentTurnApplicationResult


@dataclass
class _SessionLedger:
    owner_user_id: UUID
    last: _LedgerEntry | None = None
    by_key: dict[str, _LedgerEntry] = field(default_factory=dict)
    by_turn_sequence: dict[tuple[UUID, int], _LedgerEntry] = field(default_factory=dict)


class AgentTurnApplicationService:
    """Apply one P1F/P1G handoff to a transient, replay-safe Turn ledger."""

    def __init__(
        self,
        agent_runner: AssessmentAgentRunner | None,
        *,
        policy_validator: PolicyValidator | None = None,
        enabled: bool = False,
        p1g_enabled: bool = True,
        agent_version: str = "p1h-agent-1",
    ) -> None:
        self.enabled = enabled
        self.agent_runner = agent_runner
        self.agent_version = agent_version
        self.policy_validator = policy_validator or PolicyValidator()
        self.p1g = P1GAgentHandoffService(
            agent_runner,
            policy_validator=self.policy_validator,
            agent_version=agent_version,
            enabled=p1g_enabled,
        )
        self._lock = RLock()
        self._sessions: dict[UUID, _SessionLedger] = {}

    def apply(self, request: AgentTurnApplicationRequest) -> AgentTurnApplicationResponse:
        with self._lock:
            if not _IDEMPOTENCY_KEY.fullmatch(request.idempotency_key):
                return AgentTurnApplicationResponse(
                    rejected_result(
                        session_id=request.session_id,
                        turn_id=request.turn_id,
                        sequence=request.sequence,
                        draft_revision=request.draft_revision,
                        in_reply_to_turn_id=request.in_reply_to_turn_id,
                        error_code="P1H_INVALID_IDEMPOTENCY_KEY",
                    )
                )

            try:
                # Re-validate even when a caller passes a Pydantic object;
                # model_copy(update=...) intentionally bypasses assignment
                # validators and is not an Agent permission.
                handoff = IOSSignalIntakeApplicationHandoff.model_validate(
                    request.handoff.model_dump(mode="python")
                    if isinstance(request.handoff, IOSSignalIntakeApplicationHandoff)
                    else request.handoff
                )
            except (ValidationError, TypeError, ValueError):
                return AgentTurnApplicationResponse(
                    rejected_result(
                        session_id=request.session_id,
                        turn_id=request.turn_id,
                        sequence=request.sequence,
                        draft_revision=request.draft_revision,
                        in_reply_to_turn_id=request.in_reply_to_turn_id,
                        error_code="P1F_NOT_AGENT_READY",
                    )
                )

            if handoff.session_id != request.session_id:
                return AgentTurnApplicationResponse(
                    rejected_result(
                        session_id=request.session_id,
                        turn_id=request.turn_id,
                        sequence=request.sequence,
                        draft_revision=request.draft_revision,
                        in_reply_to_turn_id=request.in_reply_to_turn_id,
                        error_code="P1H_SESSION_MISMATCH",
                    )
                )
            if handoff.draft_revision != request.draft_revision:
                return AgentTurnApplicationResponse(
                    rejected_result(
                        session_id=request.session_id,
                        turn_id=request.turn_id,
                        sequence=request.sequence,
                        draft_revision=request.draft_revision,
                        in_reply_to_turn_id=request.in_reply_to_turn_id,
                        error_code="P1H_REVISION_MISMATCH",
                    )
                )

            ledger = self._sessions.get(request.session_id)
            if ledger is None:
                ledger = _SessionLedger(owner_user_id=request.authenticated_user_id)
                self._sessions[request.session_id] = ledger
            elif ledger.owner_user_id != request.authenticated_user_id:
                return AgentTurnApplicationResponse(
                    rejected_result(
                        session_id=request.session_id,
                        turn_id=request.turn_id,
                        sequence=request.sequence,
                        draft_revision=request.draft_revision,
                        in_reply_to_turn_id=request.in_reply_to_turn_id,
                        error_code="P1H_SESSION_OWNER_MISMATCH",
                    )
                )

            request_digest = self._request_digest(request, handoff)
            existing = ledger.by_key.get(request.idempotency_key)
            if existing is not None:
                if existing.request_digest == request_digest:
                    return AgentTurnApplicationResponse(existing.result, replayed=True)
                return AgentTurnApplicationResponse(
                    rejected_result(
                        session_id=request.session_id,
                        turn_id=request.turn_id,
                        sequence=request.sequence,
                        draft_revision=request.draft_revision,
                        in_reply_to_turn_id=request.in_reply_to_turn_id,
                        error_code="P1H_IDEMPOTENCY_KEY_REUSED",
                    )
                )

            if (request.turn_id, request.sequence) in ledger.by_turn_sequence:
                return AgentTurnApplicationResponse(
                    rejected_result(
                        session_id=request.session_id,
                        turn_id=request.turn_id,
                        sequence=request.sequence,
                        draft_revision=request.draft_revision,
                        in_reply_to_turn_id=request.in_reply_to_turn_id,
                        error_code="P1H_TURN_ALREADY_APPLIED",
                    )
                )

            preflight_error = self._preflight_error(request, ledger.last)
            if preflight_error is not None:
                return AgentTurnApplicationResponse(
                    rejected_result(
                        session_id=request.session_id,
                        turn_id=request.turn_id,
                        sequence=request.sequence,
                        draft_revision=request.draft_revision,
                        in_reply_to_turn_id=request.in_reply_to_turn_id,
                        error_code=preflight_error,
                    )
                )

            if not self.enabled:
                p1g = self._disabled_result(request, handoff)
            else:
                p1g = self.p1g.run(
                    P1GAgentHandoffRequest(
                        handoff=handoff,
                        authenticated_user_id=request.authenticated_user_id,
                        authorized_scopes=request.authorized_scopes,
                        agent_context=request.agent_context,
                        request_id=request.request_id,
                    )
                )
            result = result_from_p1g(
                p1g=p1g,
                turn_id=request.turn_id,
                sequence=request.sequence,
                in_reply_to_turn_id=request.in_reply_to_turn_id,
            )
            # A malformed/rejected P1F handoff is not an accepted Turn and
            # must not consume sequence, idempotency or continuation state.
            # The caller may correct the draft and retry through a fresh P1F
            # handoff without being blocked by the rejected attempt.
            if result.status == "rejected":
                return AgentTurnApplicationResponse(result)
            entry = _LedgerEntry(
                owner_user_id=request.authenticated_user_id,
                request_digest=request_digest,
                result=result,
            )
            ledger.by_key[request.idempotency_key] = entry
            ledger.by_turn_sequence[(request.turn_id, request.sequence)] = entry
            ledger.last = entry
            return AgentTurnApplicationResponse(result)

    def clear(self) -> None:
        """Clear the process-local ledger; production code must not call this as persistence."""

        with self._lock:
            self._sessions.clear()

    @property
    def ledger_entry_count(self) -> int:
        with self._lock:
            return sum(len(ledger.by_key) for ledger in self._sessions.values())

    @staticmethod
    def _preflight_error(
        request: AgentTurnApplicationRequest,
        last: _LedgerEntry | None,
    ) -> str | None:
        if last is None:
            if request.sequence != 1 or request.in_reply_to_turn_id is not None:
                return "P1H_PREDECESSOR_MISMATCH"
            return None

        if last.result.state != "awaiting_user":
            return "P1H_CONTINUATION_NOT_ALLOWED"
        if request.in_reply_to_turn_id != last.result.turn_id:
            return "P1H_PREDECESSOR_MISMATCH"
        if request.sequence != last.result.sequence + 1:
            return "P1H_SEQUENCE_MISMATCH"
        if request.draft_revision <= last.result.draft_revision:
            return "P1H_REVISION_MISMATCH"
        return None

    @staticmethod
    def _request_digest(
        request: AgentTurnApplicationRequest,
        handoff: IOSSignalIntakeApplicationHandoff,
    ) -> str:
        context = request.agent_context.model_dump(mode="json", exclude_none=True) if request.agent_context else None
        payload = {
            "session_id": str(request.session_id),
            "turn_id": str(request.turn_id),
            "sequence": request.sequence,
            "draft_revision": request.draft_revision,
            "in_reply_to_turn_id": str(request.in_reply_to_turn_id) if request.in_reply_to_turn_id else None,
            "handoff": handoff.model_dump(mode="json", exclude_none=True),
            "authenticated_user_id": str(request.authenticated_user_id),
            "authorized_scopes": sorted(request.authorized_scopes),
            "agent_context": context,
        }
        canonical = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
        return "sha256:" + hashlib.sha256(canonical).hexdigest()

    @staticmethod
    def _disabled_result(
        request: AgentTurnApplicationRequest,
        handoff: IOSSignalIntakeApplicationHandoff,
    ) -> P1GAgentHandoffResult:
        if handoff.status != "ready_for_agent":
            return result_from_p1f(handoff)
        return P1GAgentHandoffResult(
            session_id=request.session_id,
            draft_revision=request.draft_revision,
            status="agent_unavailable",
            handoff_status="ready_for_agent",
            error_code="P1H_DISABLED",
        )
