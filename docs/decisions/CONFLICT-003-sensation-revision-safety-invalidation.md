# CONFLICT-003：P1D 感觉修订与安全失效边界

| 属性 | 值 |
|---|---|
| 记录 ID | CONFLICT-003 |
| 状态 | Open / 已采用保守 P0 临时行为 |
| 日期 | 2026-08-09 |
| 责任角色 | 产品负责人、临床安全负责人、iOS 负责人、后端负责人、QA 负责人（均待 GOV-01 实名指定） |
| 决策截止 | GATE-03 临床安全基线前：明确高风险事实修订的服务端 retained action、revision 与重检语义 |
| 证据关闭门禁 | GATE-07 前：服务端 revision、旧 digest/ApprovalIntent 失效、锁定安全测试和同一 SafetyBaseline 完成前，本记录保持 Open |
| 影响范围 | P1D iOS 草稿状态、P1E/P1F 安全交接、P2B/P2C 审批前置、UX-01、IOS-01、DATA-01、SAFE-01、QA-01 |
| 变更级别 | A：安全结果、普通 Agent 与审批失效边界 |

## 冲突

现有 P1D Core 曾只在**位置**集合变化时清空本地安全快照并退回事实收集；感觉的新增、删除、位置关联变化、`other` 标签变化或“感觉未知”切换只撤销感觉复核。这样用户可在 `no_rule_triggered` 的普通路径、事实复核或审批准备中改变安全相关事实，却继续复用旧安全、普通 Agent 或审批资格。

这与以下真源冲突：

- [UX-01](../02_UX_AND_USER_FLOWS.md) 要求修订后完整重跑安全，旧审批不可继续；
- [DATA-01](../06_DOMAIN_DATA_MODEL.md) 要求修订产生新 revision，旧 draft/Intent 原子失效；
- [SAFE-01](../09_SAFETY_AND_CLINICAL_CONTENT.md) 要求新的安全信号暂停普通流程，并且 R0/R1 的原安全行动不能因修订消失；
- [PRIV-01](../10_PRIVACY_SECURITY_COMPLIANCE.md) 要求安全相关事实修改触发规则重算。

P1D 当前没有服务端 `retained_safety_action`、权威 Session revision 或 ApprovalIntent，因此不能把已升级的 R0/R1/R2/`undetermined` 安全快照简单清零后继续编辑；那会隐藏原安全行动，或在后续遗漏中把旧 R2 重新当作审批许可。本记录只收敛感觉编辑；位置、程度、时间、因素、功能影响和背景等非感觉语义事实的高风险修订仍是独立发布阻断，见 [CONFLICT-004](CONFLICT-004-p1d-non-sensation-revision-safety-boundary.md)。

## 保守临时行为

在服务端修订闭环与独立 retained action 可用前，所有 P1D 新实现和测试采用以下规则：

1. **语义感觉变更**是新增/删除感觉、改变感觉—位置关联、修改规范化后的 `other` 标签，或在具体感觉与全组感觉未知之间切换；完全相同的重复提交是 no-op，不增加本地 `SignalIntakeDraft.draft_revision`、不失效。这里的本地编辑版本不是服务端 `DraftRevision`，不创建 Session/Turn 或 ApprovalIntent。
2. 对 `not_run`、`unavailable` 或 `no_rule_triggered` 的本地草稿，任何语义感觉变更必须原子撤销旧安全、普通 Agent 和审批下游资格，保留未确认事实与草稿 ID，递增本地 `SignalIntakeDraft.draft_revision` 后退回 `collecting_facts`；用户必须重新进入确定性安全检查。`NoRuleTriggered` 绝不显示为“安全”。
3. 对 `r0`、`r1`、`r2`、`undetermined` 或 `safety_action`，P1D Core 必须拒绝直接感觉变更，SwiftUI 必须禁用相应控件并说明“当前安全行动优先”。不得只依赖 UI 禁用，也不得清掉、降级或隐藏旧安全行动。
4. “更多感觉”只是已有稳定 `SignalSensationCode` 的本地结构化入口；它不新增安全规则、不自动提升/降低等级、不推断病因或组织，也不生成动作、营养、药物或普通 AI 建议。
5. 未来允许高风险事实修订时，必须走既有 typed 服务端 draft-revision/post-escalation revision 边界：保留独立 `retained_safety_action`、创建新 revision、使旧 digest/ApprovalIntent 失效、重新运行确定性规则；不得由 P1D 本地状态机替代。

## 关闭条件

仅在以下全部条件满足后才可关闭：

- 产品、临床安全、iOS、后端和 QA 已书面确认高风险事实修订的保留行动与用户纠正路径；
- 服务端 revision 契约绑定 `retained_safety_action`、当前 SafetyBaseline、draft digest 和 ApprovalIntent 失效语义；
- P1D/P1E/P1F/P2B/P2C、OpenAPI/Schema、UX/安全文案和锁定测试使用同一规则；
- R0/R1/R2/`undetermined` 修订、规则不可用、旧 digest/intent 重放和无副作用均有同一 SafetyBaseline 证据；
- TRACE-01 与发布门禁可追溯到具名签字和真实设备/端到端验证。

## 关联

- [UX-01](../02_UX_AND_USER_FLOWS.md)
- [IOS-01](../04_IOS_ARCHITECTURE.md)
- [DATA-01](../06_DOMAIN_DATA_MODEL.md)
- [SAFE-01](../09_SAFETY_AND_CLINICAL_CONTENT.md)
- [PRIV-01](../10_PRIVACY_SECURITY_COMPLIANCE.md)
- [QA-01](../11_TEST_AND_EVALUATION.md)
- [ADR-0007](ADR-0007-ios-typed-signal-intake-boundary.md)
- [ADR-0008](ADR-0008-ios-signal-intake-server-adapter-boundary.md)
