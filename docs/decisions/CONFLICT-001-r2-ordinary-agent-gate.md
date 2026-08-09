# CONFLICT-001：R2 普通 Agent 门禁语义

| 属性 | 值 |
|---|---|
| 记录 ID | CONFLICT-001 |
| 状态 | Open / 已采用保守临时行为 |
| 日期 | 2026-08-09 |
| 责任角色 | 产品负责人、临床安全负责人、AI 工程负责人、后端负责人 |
| 最晚门禁 | ADR-0019 批准前，且不得晚于 GATE-03 临床安全基线 |
| 影响范围 | SafetyGate、P1E/P1F/P1G 内部交接、iOS 草稿状态、AgentTurn 契约、FEAT-COMP-01 |

## 冲突

以下历史 ADR 曾把“完整、支持场景的 R2/R3”描述为可以进入普通 Agent 或 `ready_for_agent` 的范围：

- [ADR-0002](ADR-0002-agent-and-safety-boundary.md)；
- [ADR-0009](ADR-0009-reference-project-adoption-and-native-boundary.md)；
- [ADR-0010](ADR-0010-p1f-application-handoff-boundary.md)。

当前产品与安全规格明确：R2 表示应尽快获得专业评估，不应用普通 AI 对话、普通自我管理或行动内容替代专业帮助；只有 R3 可进入普通 Agent。参见 [ADR-0019](ADR-0019-contextual-guidance-and-communication-summary.md)、[SAFE-01](../09_SAFETY_AND_CLINICAL_CONTENT.md) 和 [AGENT-01](../05_AGENT_ARCHITECTURE.md)。

## 保守临时行为

在该冲突完成正式评审前，所有新实现与契约验证采用下列更保守规则：

1. `ordinary_agent_allowed=true` 只允许 `complete + supported + tier=R3 + unresolved_safety=false`；
2. R2 不得产生 `ready_for_agent`、不调用 PydanticAI、不得显示普通行动、动作或营养内容；
3. R2 可以沿既有独立确认边界进行固定专业评估准备、事实复核或沟通准备，但不能把这些能力标为普通 Agent；
4. 不修改历史 ADR 的原文或追溯性；正式解决必须通过已批准的替代决策和兼容性说明完成。

## 关闭条件

- 产品、临床安全、AI、后端确认 R2 专业评估准备的允许输出与停止条件；
- 正式 ADR 明确替代 ADR-0002/0009/0010 中受影响的 R2 普通 Agent 条款；
- API/Schema、Python/Swift validator、P1F/P1G 回归和锁定安全用例均使用同一规则；
- TRACE-01、QA-01 和发布 SafetyBaseline 中存在可追溯证据。
