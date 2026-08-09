# CONFLICT-002：普通问题选择权与 PydanticAI 职责

| 属性 | 值 |
|---|---|
| 记录 ID | CONFLICT-002 |
| 状态 | Open / 已采用保守临时行为 |
| 日期 | 2026-08-09 |
| 责任角色 | 产品负责人、临床安全负责人、Agent 工程负责人、后端负责人、iOS 负责人、QA 负责人（均待 GOV-01 实名指定） |
| 决策截止 | ADR-0019 批准前：以书面 ADR 明确 Application Service 的普通题选择权与 PydanticAI 限界 |
| 证据关闭门禁 | GATE-07 前：契约、实现、锁定测试与同一 SafetyBaseline 证据完成前，本记录保持 Open |
| 影响范围 | AGENT-01、FEAT-COMP-01、TEST-COMP-01、AgentTurn/QuestionPlan 契约、P1I 实现候选 |
| 变更级别 | A：普通健康追问的选择权、模型边界与安全可审计性 |

## 冲突

AGENT-01 早期文字曾把“普通追问选择”列为 Agent 职责。ADR-0019、AGENT-01 §5.5 与 FEAT-COMP-01 §5.2 则要求 Application Service 的版本化 `QuestionPolicy` 先生成至多一个 `QuestionPlan`，模型只能在已下发计划范围内理解回答、形成未确认候选或做不改变含义的受限表达。

当前 PydanticAI 样机的 `AskQuestionCandidate` 仍可表达 1–20 个普通问题，`PolicyValidator` 目前只阻止模型创建安全题。这说明当前样机并不满足未来 P1I 的单题计划边界；它是原型能力差距，不能被解释为产品已经允许模型自由选题。

## 保守临时行为

在本冲突完成正式评审前：

1. 不实现或启用 P1I、`QuestionPlan`、普通目录、情境化普通追问或相关跨端字段；GATE-02 前不得借内部样机绕过该限制。
2. 所有新的目标实现一律以 Application Service 为普通问题 ID、顺序、答案契约、完成条件、失效和下一状态的唯一权威；PydanticAI 不得自由选题、改序、批量提问、创建安全题、决定结束、读取额外资料或生成行动。
3. 任一无法获得有效计划的情况都不允许模型补写问题；保留结构化记录、未确认草稿以及已有安全/手动/降级路径。
4. R0、R1、R2、`undetermined`、未解决安全、未覆盖、`manual` 或 `degraded` 始终没有普通 QuestionPlan 或普通 PydanticAI 对话。
5. 当前可多题 PydanticAI 原型只能按 BASELINE-01 的边界用于合成、非生产验证；不得对用户或发布材料声称它已实现“结合训练/工作情况的一次一问智能分析”。

## 正式解决与关闭条件

本记录有两个不同的时间点：上表“决策截止”要求在 ADR-0019 批准前形成受审查的目标权责，但**不**代表本记录已经关闭；只有上表“证据关闭门禁”满足以下全部条件时，才可把状态改为 Closed。任何一个阶段未完成均继续采用本文件的保守临时行为。

仅在全部条件成立后才可关闭本记录：

- GOV-01 的 GATE-02 已由具名责任人有效关闭；
- ADR-0019 已批准，且明确替代/协调受影响的 Agent 责任表述；
- P1I-OPEN-001～006 已由相应负责人关闭，尤其是目录治理、预算/完成门槛、tie-break、分类和失效语义；
- DATA-01、API-01、OpenAPI、JSON Schema、AGENT-01、FEAT-COMP-01 和 TEST-COMP-01 已通过正式变更同步表达计划 ID/版本、答案、失效、兼容与拒绝行为；
- 实现证明同一 canonical 输入确定性地产生同一计划；每轮仅一题；当前 `plan_instance_id` 只成功接受一次，精确幂等重放不重复产生候选；旧题/跨会话/版本失效答案被拒绝；PydanticAI 无法越权；R0–R2 与所有非普通路径均无普通题；
- QA 将锁定测试、临床/隐私审批和同一 SafetyBaseline 追踪到 TRACE-01。

在关闭前，以本文件“保守临时行为”为准；任何旧文案、样机测试或 Prompt 均不得降低该要求。

## 关联

- [ADR-0019：情境化行动建议与沟通摘要边界](ADR-0019-contextual-guidance-and-communication-summary.md)
- [AGENT-01](../05_AGENT_ARCHITECTURE.md)
- [FEAT-COMP-01](../25_CONVERSATIONAL_RECOVERY_COMPANION.md)
- [TEST-COMP-01](../26_CONVERSATIONAL_RECOVERY_COMPANION_TEST_PLAN.md)
- [GOV-01](../27_GATE_02_RESPONSIBILITY_AND_PRODUCT_BOUNDARY.md)
