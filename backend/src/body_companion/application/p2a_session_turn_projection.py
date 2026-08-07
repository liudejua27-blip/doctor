"""Application boundary for the P2A typed Session/Turn projection prototype."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from uuid import UUID

from ..domain.agent_turn_application import AgentTurnApplicationResult
from ..domain.session_turn_projection import (
    P2ASessionTurnLedger,
    SessionProjection,
    SessionTurnProjectionConflict,
    SessionTurnProjectionResponse,
)


P2A_FEATURE_FLAG = "P2A_SESSION_TURN_PROJECTION_PROTOTYPE"


@dataclass(frozen=True)
class P2ASessionStartResponse:
    session: SessionProjection
    replayed: bool = False


@dataclass(frozen=True)
class P2ATurnApplicationRequest:
    owner_user_id: UUID
    result: AgentTurnApplicationResult
    expected_revision: int
    idempotency_key: str
    now: datetime | None = None


class P2ASessionTurnProjectionService:
    """Feature-flagged internal service; no public API or durable repository."""

    def __init__(self, *, enabled: bool = False, ledger: P2ASessionTurnLedger | None = None) -> None:
        self.enabled = enabled
        self.ledger = ledger or P2ASessionTurnLedger()

    def start_session(
        self,
        *,
        owner_user_id: UUID,
        idempotency_key: str,
        session_id: UUID | None = None,
        now: datetime | None = None,
    ) -> P2ASessionStartResponse:
        self._ensure_enabled()
        if session_id is None:
            raise SessionTurnProjectionConflict(
                "P2A_SESSION_ID_REQUIRED", "the prototype caller must bind a server-generated Session ID"
            )
        created = self.ledger.create_session(
            owner_user_id=owner_user_id,
            idempotency_key=idempotency_key,
            session_id=session_id,
            now=now,
        )
        return P2ASessionStartResponse(session=created.session, replayed=created.replayed)

    def apply(self, request: P2ATurnApplicationRequest) -> SessionTurnProjectionResponse:
        self._ensure_enabled()
        return self.ledger.apply(
            owner_user_id=request.owner_user_id,
            result=request.result,
            expected_revision=request.expected_revision,
            idempotency_key=request.idempotency_key,
            now=request.now,
        )

    def get_session(self, *, owner_user_id: UUID, session_id: UUID) -> SessionProjection:
        self._ensure_enabled()
        return self.ledger.get_session(owner_user_id=owner_user_id, session_id=session_id)

    def _ensure_enabled(self) -> None:
        if not self.enabled:
            raise SessionTurnProjectionConflict("P2A_DISABLED", "P2A Session/Turn projection is disabled")
