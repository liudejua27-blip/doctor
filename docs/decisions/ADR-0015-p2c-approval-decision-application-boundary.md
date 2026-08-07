# ADR-0015：P2C 第二次确认与终态投影应用边界

| 属性 | 值 |
|---|---|
| ADR ID | ADR-0015 |
| 状态 | Accepted for P2C prototype; production implementation blocked |
| 日期 | 2026-08-06 |
| 负责人 | 后端/API 负责人 + 数据架构负责人 |
| 关联功能 | FEAT-P2C-APPROVAL-DECISION-APPLICATION-SLICE |
| 关联规范 | API-01 §7.7、DATA-01 §3.7、SAFE-01、PRIV-01、ADR-0005、ADR-0014 |

## 背景

P2B 只把用户复核事实变成 pending `ApprovalIntent`，并故意不改 P2A Session/Turn。P2 的旧 prototype adapter 可以调用 `PrototypeApprovalStore.decide`，但输入包含未类型化的快照，无法独立证明 approve/deny 的来源绑定、过期顺序、结果脱敏和终态生命周期语义。直接把旧 adapter 视作生产确认接口会违反 DOC-00 的“文档先于代码”和 ADR-0002 的 Agent/Application 权限边界。

## 决策

新增一个默认关闭的、仅内部使用的 `P2CApprovalDecisionApplicationService`：

1. 以 `ConfirmationIntentApplicationResult`、typed `ApprovalDecisionRequest`、服务端当前 Session revision 和 owner binding 为唯一输入；所有 Pydantic 模型在 hash/store 前再次 `model_validate`。
2. 先验证 P2B result 与 store 中 Approval 的 immutable identity，再检查幂等、终态、expiry、Session revision、intent digest 和 Approval revision；不能从客户端接收 Event/Episode/安全/原话字段。
3. deny 调用原型 Approval store 并保证零 Event；approve 只能委托注入的 `PrototypeApprovalStore`/`PrototypeEventStore`，不直接给 Agent 或客户端写权限。
4. 结果用独立的 `ApprovalDecisionApplicationResult` Schema 表达 terminal Approval metadata、合法 result refs 和 prospective lifecycle projection；不把 P2A ledger 更新、数据库 commit 或公开 API 作为事实。
5. 同一 approval 的终态由进程内 map 复用；同 key 摘要冲突失败；不同 key 在终态后只返回第一次的结果，不重复执行 Event writer。

## 取舍与替代方案

- **直接复用旧 HTTP `/decisions`**：拒绝。它是隔离 prototype adapter，不提供 P2B typed source binding，不能成为正式应用边界。
- **让 P2B 直接 approve**：拒绝。会把事实复核和真正副作用合并，破坏用户第二次确认和最小权限。
- **让客户端提交完整 Event/Episode**：拒绝。客户端不能成为健康事实或资源 ID 的权威来源。
- **本切片直接接 PostgreSQL/OIDC/Consent**：拒绝。真实事务、认证和法律/隐私决策尚未冻结，必须有独立 Feature/Schema/TEST/ADR 和发布证据。
- **不返回 lifecycle projection**：暂不采用。没有脱敏的终态投影，iOS 无法验证 approve/deny 后的安全 UI 状态；但 projection 明确标为 prospective，不能伪装为已持久化。

## 不变量与后果

- P2B prospective `awaiting_approval` 的 P2A pre-revision 不变；首次 P2C 决定要求 `current_session_revision = previous_session_revision = approval.resource_revision`。
- approve 成功只允许一个 `event` result ref；deny/invalidated/failed 结果引用为空；重复决定不增加 Event/Episode 计数。
- 结果不含 raw/candidate/Safety answer/Prompt/user identity；日志只记录固定错误码和脱敏 ID。
- 正面：第二次确认有独立、可测试、可替换的 typed boundary；未来正式 repository 可替换 prototype store 而不授予 Agent 写权限。
- 代价：当前仍是进程内状态，重启丢失；P2C 无法证明分布式 CAS、正式 expiry/tombstone、认证/Consent、同事务 read-back 或公开 API 兼容。

## 验证、停止与回滚

- 验证：`TEST-P2C` 聚焦测试、P2/P2A/P2B 全量回归、结果 Schema/隐私扫描、无新增 OpenAPI route、`PrototypeEventStore` 副作用计数。
- 停止：任何跨用户成功、过期执行、二次 Event、P2A 隐式推进、结果泄露健康正文或 Event writer 部分写入。
- 回滚：关闭 `P2C_APPROVAL_DECISION_APPLICATION_PROTOTYPE`；调用方回到未确认草稿/手动安全入口，不删除正式历史（本切片不创建正式历史）。
- 本 ADR 不批准真实 Provider、临床内容、人体资产、生产数据库、认证、Consent 或医疗服务发布。
