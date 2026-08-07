# ADR-0014：P2B ConfirmationIntent 应用边界

| 属性 | 值 |
|---|---|
| ADR ID | ADR-0014 |
| 状态 | Accepted for prototype; production implementation blocked |
| 日期 | 2026-08-06 |
| 负责人 | 后端/API + 隐私安全负责人 |
| 关联功能 | FEAT-P2B-CONFIRMATION-INTENT-APPLICATION-SLICE |
| 关联规范 | ARCH-01 §8、DATA-01 §9、API-01 §7.6、ADR-0002、ADR-0005、ADR-0013 |

## 背景

P2A 只产生 `awaiting_confirmation` 的 typed draft projection；P2 `PrototypeApprovalStore` 虽然能创建 pending ApprovalIntent，但 HTTP prototype 直接从未类型化字典读取候选、Safety、raw input 和 Session 状态，无法证明未来 `requestDraftConfirmation` 的复验顺序、结果脱敏和同一 Turn 不重复创建意图。

## 决策

新增 P2B 内部应用服务：

1. 接受并重新验证 P2A `SessionTurnProjectionResult`；只有 `awaiting_confirmation + draft_ready` 可进入。
2. 从服务端传入的 `SafetyEvaluation`、`UserTurnInput` 和版本元数据构建 ApprovalIntent；客户端只提供 ConfirmationRequest 的复核/选择字段。
3. 严格检查 owner/session/turn/revision/draft digest/八组 reviewed fields/Safety gate/EpisodeSelection，再创建 `pending/revision=1` 的内存 ApprovalIntent。
4. 返回一个无 raw/candidate 正文的 `ConfirmationIntentApplicationResult` 和 `approval_required` application projection；该 projection 是后续正式事务的输入，不是 P2A ledger 的持久状态。
5. 使用 owner+Session+operation+Idempotency-Key 摘要 ledger 防止重复 Intent；同一 Session/Turn 的不同 key 也拒绝第二个 Intent。
6. 在幂等摘要或 Store 写入前重建验证 `ConfirmationRequest`、`SafetyEvaluation`、`UserTurnInput`，拒绝 `model_construct`/字典伪造；Session 过期、时区无效和服务端安全门失败均 fail closed。
7. P2B 不调用 Agent/Safety，不执行 approve，不写 Event/Episode，不新增公开 API，不替代认证/Consent/DB/审计；已完成且支持的 R2 gate 可以进入事实保存准备，即使 `ordinary_agent_allowed=false`，因为本边界不运行普通 Agent。

## 选择理由

- 将“用户事实复核”与“第二次动作批准”继续分离，符合 SAFE-INV-06 和 ADR-0002。
- 在正式 Session/Approval/Event 事务之前先固定跨对象等式和脱敏结果，避免直接把 HTTP 字典提升为 API 契约。
- 保留 P2 `PrototypeApprovalStore` 作为隔离的审批状态样机，同时让新应用服务承担唯一的 typed 入口。

## 禁止事项

- 不接受客户端完整 `BodySignalEvent`、Agent 摘要或客户端 Safety 等级作为权威。
- 不从区域、感觉、Episode 缓存或 Agent 文案自动选择目标 Episode。
- 不把 pending ApprovalIntent、`awaiting_approval` projection 或 HTTP 201 当成 Event 已保存。
- 不把 P2B 内存幂等当作跨进程持久化；进程重启后不能恢复旧健康正文。

## 后果

正面：P2A→Confirmation 的输入、验证顺序、幂等和隐私结果拥有独立 Feature/Schema/TEST/ADR；未来正式事务可以替换 repository 而不让 Agent 获得写权限。

代价：当前仍存在 P2A projection、P2B intent ledger 和旧 HTTP adapter 三个 prototype 层；P2B 的拟推进 Session revision 尚未落库，不能支持跨设备恢复或公开 confirmations。`server_raw_input`/Safety 与精确 P2A Turn 的来源、保留和删除证明也仍是 REL-01 GATE-05。

## 验证与回滚

- 验证：[TEST-P2B-CONFIRMATION-INTENT-APPLICATION-SLICE](../18_IMPLEMENTED_PROTOTYPE_BASELINE.md)、`confirmation-intent-application-result.schema.json`、P1/P2/P2A 全量回归。
- 停止条件：R0/R1 意图、重复 Intent、越权、stale digest、candidate/raw 泄露或 EventStore 副作用。
- 回滚：关闭 `P2B_CONFIRMATION_INTENT_APPLICATION_PROTOTYPE`，回到 P2A draft review；不删除正式历史。
