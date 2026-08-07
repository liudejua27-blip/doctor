"""PydanticAI adapter for the single AssessmentAgent.

The adapter owns model interaction only. It has no database handle and no tool
that can create a confirmed event, send a report, schedule a reminder, or
query another user.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Mapping
from uuid import UUID

from pydantic import TypeAdapter
from pydantic_ai import Agent, RunContext

from ..domain.agent_context import (
    AgentReadAudit,
    AgentReadContext,
    AgentReadScope,
    ContextAuthorizationError,
)
from ..domain.types import AgentCandidate


class AgentExecutionError(RuntimeError):
    """Provider, output, or execution failure without sensitive details."""


class ToolAuthorizationError(PermissionError):
    """Raised when a tool is outside the current consent capability."""


@dataclass(frozen=True)
class AgentDependencies:
    authenticated_user_id: UUID
    authorized_scopes: frozenset[str] = frozenset()
    context: AgentReadContext | None = None
    read_audit: AgentReadAudit = field(default_factory=AgentReadAudit, compare=False)

    def __post_init__(self) -> None:
        if self.context is not None and self.context.authenticated_user_id != self.authenticated_user_id:
            raise ToolAuthorizationError("agent context is bound to a different user")
        if self.context is not None and self.authorized_scopes:
            context_scopes = {grant.scope for grant in self.context.grants}
            if not set(self.authorized_scopes).issubset(context_scopes):
                raise ToolAuthorizationError("authorized scope set is broader than the typed context")

    def require(self, scope: str) -> None:
        typed_scope = scope  # keep the public error path stable for API callers
        if self.context is None:
            if scope not in self.authorized_scopes:
                self.read_audit.record_denied(scope)  # type: ignore[arg-type]
                raise ToolAuthorizationError("requested data scope is not authorized")
            raise ToolAuthorizationError("typed AgentReadContext is required for an authorized read")
        try:
            self.context.require_scope(typed_scope)
        except (ContextAuthorizationError, ValueError) as exc:
            self.read_audit.record_denied(scope)  # type: ignore[arg-type]
            raise ToolAuthorizationError("requested data scope is not authorized") from exc

    def read_confirmed_events(self) -> Mapping[str, Any]:
        self.require("current_episode_read")
        assert self.context is not None
        projection = self.context.projection("current_episode_read")
        self.read_audit.record_success(
            scope="current_episode_read",
            source_ids=self.context.source_ids("current_episode_read"),
            revision=projection["projection"].get("episode_revision"),
        )
        return projection

    def read_current_episode(self) -> Mapping[str, Any]:
        """Compatibility alias for the pre-contract prototype name."""

        return self.read_confirmed_events()

    def read_historical_events(self) -> Mapping[str, Any]:
        """Read only the current user's explicitly authorized historical summaries."""

        self.require("historical_events_read")
        assert self.context is not None
        projection = self.context.projection("historical_events_read")
        self.read_audit.record_success(
            scope="historical_events_read",
            source_ids=self.context.source_ids("historical_events_read"),
            revision=projection["projection"].get("episode_revision"),
        )
        return projection

    def read_profile_snapshot(self) -> Mapping[str, Any]:
        self.require("body_profile_read")
        assert self.context is not None
        projection = self.context.projection("body_profile_read")
        self.read_audit.record_success(
            scope="body_profile_read",
            source_ids=self.context.source_ids("body_profile_read"),
            revision=projection["projection"].get("profile_revision"),
        )
        return projection

    def read_profile(self) -> Mapping[str, Any]:
        """Compatibility alias for the pre-contract prototype name."""

        return self.read_profile_snapshot()

    def read_verified_guidance(self) -> Mapping[str, Any]:
        self.require("verified_content_read")
        assert self.context is not None
        projection = self.context.projection("verified_content_read")
        self.read_audit.record_success(
            scope="verified_content_read",
            source_ids=self.context.source_ids("verified_content_read"),
            revision=projection["projection"].get("source", {}).get("revision"),
        )
        return projection


AGENT_SYSTEM_PROMPT = """
你是 AI Body Companion 的 AssessmentAgent。你只把用户输入整理成强类型的未确认身体信号草稿，或提出一个非安全的结构化追问。

必须遵守：
- 不诊断、不输出疾病概率、不排除严重疾病、不处方、不调整用药、不承诺治疗或治愈。
- 位置只表示用户主观指出的区域附近，不表示受损组织。
- 只使用输入和授权工具返回的最小资料；不要猜测缺失字段。
- SafetyEngine 已在你之前运行；你不能创建、修改或删除安全问题，也不能降低安全等级。
- 不要输出正式事件、用户 ID、生命周期、确认、行动计划、SafetyBaseline 或报告/提醒/分享动作。
- 只输出 AgentCandidate 的强类型结构。
""".strip()


def build_assessment_agent(model: Any, *, agent_version: str = "p1b-agent-1") -> Agent:
    """Build one PydanticAI Agent with only consent-checked read tools.

    A model must be supplied explicitly. There is intentionally no default
    provider selection in this prototype.
    """

    if model is None:
        raise ValueError("a model must be explicitly injected; provider selection is an OPEN item")

    agent = Agent(
        model=model,
        name="AssessmentAgent",
        deps_type=AgentDependencies,
        output_type=AgentCandidate,
        system_prompt=AGENT_SYSTEM_PROMPT,
        retries=1,
        metadata={"agent_version": agent_version, "include_content": False},
    )

    @agent.tool(name="read_confirmed_events")
    def read_confirmed_events(ctx: RunContext[AgentDependencies]) -> Mapping[str, Any]:
        """Read the current user's already-authorized confirmed Episode summary only."""

        return ctx.deps.read_confirmed_events()

    @agent.tool(name="read_historical_events")
    def read_historical_events(ctx: RunContext[AgentDependencies]) -> Mapping[str, Any]:
        """Read explicitly authorized summaries from the current user's history only."""

        return ctx.deps.read_historical_events()

    @agent.tool(name="read_profile_snapshot")
    def read_profile_snapshot(ctx: RunContext[AgentDependencies]) -> Mapping[str, Any]:
        """Read a minimal current-user profile snapshot when explicitly authorized."""

        return ctx.deps.read_profile_snapshot()

    @agent.tool(name="retrieve_verified_guidance")
    def retrieve_verified_guidance(ctx: RunContext[AgentDependencies]) -> Mapping[str, Any]:
        """Read already-published content identifiers; never invent guidance."""

        return ctx.deps.read_verified_guidance()

    return agent


class AssessmentAgentRunner:
    def __init__(self, model: Any, *, agent_version: str = "p1b-agent-1") -> None:
        self.agent_version = agent_version
        self.agent = build_assessment_agent(model, agent_version=agent_version)

    def run_sync(self, user_prompt: str, *, deps: AgentDependencies) -> AgentCandidate:
        if not user_prompt.strip():
            raise AgentExecutionError("empty user input")
        try:
            result = self.agent.run_sync(user_prompt, deps=deps)
            return TypeAdapter(AgentCandidate).validate_python(result.output)
        except AgentExecutionError:
            raise
        except Exception as exc:  # noqa: BLE001 - do not expose provider internals
            raise AgentExecutionError("typed Agent execution failed") from exc
