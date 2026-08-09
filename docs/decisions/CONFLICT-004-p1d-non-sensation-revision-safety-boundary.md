# CONFLICT-004：P1D 非感觉事实修订与安全行动保留

| 属性 | 值 |
|---|---|
| 记录 ID | CONFLICT-004 |
| 状态 | Open / 当前仅内部原型，受影响能力不得外部发布 |
| 日期 | 2026-08-09 |
| 责任角色 | 产品负责人、临床安全负责人、iOS 负责人、后端负责人、QA 负责人（均待 GOV-01 实名指定） |
| 决策截止 | GATE-03 临床安全基线前：明确高风险位置与其他事实修订的 retained action、revision 和重检语义 |
| 证据关闭门禁 | GATE-07 前：服务端 revision、旧 digest/ApprovalIntent 失效、锁定安全测试和同一 SafetyBaseline 完成前，本记录保持 Open |
| 影响范围 | P1D 位置、程度、时间、因素、功能影响、背景等编辑；P1E/P1F 安全交接；P2B/P2C 审批前置；UX-01、IOS-01、DATA-01、SAFE-01、QA-01 |
| 变更级别 | A：安全行动保留、普通 Agent 与审批失效边界 |

## 冲突

当前 P1D Core 对位置集合变化会清空本地安全快照并退回事实收集；程度、时间、因素、功能影响和背景等其他事实编辑也没有权威的服务端 revision 或独立的 `retained_safety_action`。若该行为发生在 R0/R1/R2/`undetermined` 或已进入安全行动之后，现有本地模型无法区分“当前新评估”与“必须继续置顶的旧安全行动”，可能隐藏原行动或让后续流程误用过期状态。

这与以下真源冲突：

- [UX-01](../02_UX_AND_USER_FLOWS.md) 要求修订后完整重跑安全，并在信息不足或不可用时保留原 R0/R1 CTA；
- [DATA-01](../06_DOMAIN_DATA_MODEL.md) 要求服务端 revision 使旧 digest/ApprovalIntent 原子失效；
- [SAFE-01](../09_SAFETY_AND_CLINICAL_CONTENT.md) 要求新的安全信号暂停普通流程，原安全行动不得因修订消失；
- [PRIV-01](../10_PRIVACY_SECURITY_COMPLIANCE.md) 要求修改安全相关事实后触发规则重算。

本记录不改变 [CONFLICT-003](CONFLICT-003-sensation-revision-safety-invalidation.md) 已定义的感觉修订 P0 修复；它记录其余事实类型仍未关闭的风险。

## 保守临时行为

在服务端修订闭环与独立 retained action 可用前：

1. 任何允许高风险安全行动后继续修改位置、程度、时间、因素、功能影响或背景的 P1D 流程都不得被标记为可外部测试、可发布或已满足安全门禁。
2. 当前 Swift Package 只能作为内部 Simulator 原型；现有位置/非感觉编辑行为不构成“安全行动已保留”或“可安全修订”的证明。
3. 新实现不得以清空当前 `SignalSafetyState`、保留旧 tier、客户端缓存或 UI 隐藏来模拟 retained action；不得将旧 R2 重新用作审批许可。
4. 未来开放此类修订时，必须走服务端 typed draft-revision/post-escalation revision：保留独立 `retained_safety_action`、创建新服务端 revision、使旧 digest/ApprovalIntent 失效、重新运行确定性规则；规则不可用时仍保留原升级行动。

## 关闭条件

仅在以下全部条件满足后才可关闭：

- 产品、临床安全、iOS、后端和 QA 已书面确认每类安全相关事实修订的用户纠正路径；
- 服务端 revision 契约绑定 `retained_safety_action`、当前 SafetyBaseline、draft digest 和 ApprovalIntent 失效语义；
- P1D/P1E/P1F/P2B/P2C、OpenAPI/Schema、UX/安全文案和锁定测试使用同一规则；
- R0/R1/R2/`undetermined`、规则不可用、旧 digest/intent 重放和无副作用均有同一 SafetyBaseline 证据；
- TRACE-01 与发布门禁可追溯到具名签字和真实设备/端到端验证。

## 关联

- [CONFLICT-003](CONFLICT-003-sensation-revision-safety-invalidation.md)
- [UX-01](../02_UX_AND_USER_FLOWS.md)
- [IOS-01](../04_IOS_ARCHITECTURE.md)
- [DATA-01](../06_DOMAIN_DATA_MODEL.md)
- [SAFE-01](../09_SAFETY_AND_CLINICAL_CONTENT.md)
- [PRIV-01](../10_PRIVACY_SECURITY_COMPLIANCE.md)
- [QA-01](../11_TEST_AND_EVALUATION.md)
- [ADR-0007](ADR-0007-ios-typed-signal-intake-boundary.md)
- [ADR-0008](ADR-0008-ios-signal-intake-server-adapter-boundary.md)
