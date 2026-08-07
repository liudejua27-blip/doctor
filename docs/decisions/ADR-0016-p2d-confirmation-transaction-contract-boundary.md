# ADR-0016：P2D 确认事务写集与提交读回契约边界

| 属性 | 值 |
|---|---|
| ADR ID | ADR-0016 |
| 状态 | Accepted for P2D contract prototype; production repository blocked |
| 日期 | 2026-08-06 |
| 负责人 | 后端/API 负责人 + 数据架构负责人 |
| 关联功能 | FEAT-P2D-CONFIRMATION-TRANSACTION-CONTRACT-SLICE |
| 关联规范 | API-01 §4～§7.7、DATA-01 §5～§6、ARCH-01 §7～§10、PRIV-01、ADR-0005、ADR-0013、ADR-0014、ADR-0015 |

## 背景

P2A/P2B/P2C 已分别建立 typed Session/Turn、pending ApprovalIntent 和 terminal approve/deny 结果，但当前每一层仍以进程内 ledger/store 为边界。旧 HTTP adapter 还会直接修改 `dict` Session，再调用 Approval store，无法作为正式事务的证明：中途崩溃可能留下孤立 Event、Approval 或 lifecycle Turn；成功响应也可能不是从权威存储 read-back 得到。

正式 `decideApproval` 需要一个明确的 repository contract，但数据库、认证、Consent、审计和过期策略尚未冻结。本 ADR 先固定可测试的语义和写集，不越级选择具体数据库或宣称持久化完成。

## 决策

新增默认关闭的内部 P2D contract boundary，未来正式实现必须提供等价的：

```text
prepare(typed request) -> plan | conflict
commit(plan)           -> receipt | conflict
read_back(scope)       -> authoritative receipt
```

并遵守以下决定：

1. `prepare` 重新验证 P2B/P2C source、owner/session/approval identity、`awaiting_approval` 当前状态、revision、digest、终态和有限 write set；失败发生在任何副作用之前。
2. `commit` 必须以数据库事务或等价全有/全无机制同时处理 Session revision/state/latest lifecycle Turn、Approval terminal status/revision、必要的 Event/Episode 绑定和脱敏 Audit metadata；不能由客户端或 Agent 分步调用。
3. `read_back` 必须从权威存储验证 Session/Approval/Turn/result refs 与 plan 的 digest、revision 和状态等式；不能把内存 plan 直接作为 completed 响应。
4. `executed` 只允许一个 Event result ref；`denied`/`invalidated`/`failed` 不允许 Event/Episode ref。Session post revision 恰为当前 `awaiting_approval` revision + 1。
5. 幂等作用域绑定 owner/session/approval/operation/key；同摘要重放原 canonical receipt，应用响应外层标 `replayed=true`，不同摘要冲突；终态快照变化不应阻断已记录 key 的安全重放；终态不能重新执行 Event。未完成请求必须有明确 in-progress/可重试语义。
6. P2D prototype 只生成/验证 metadata-only plan/receipt，不接 PostgreSQL、不改 P2A/P2B/P2C store、不新增公开 API；P2C prototype Event ref 不被解释为 P2D 正式提交。

## 取舍与替代方案

- **直接把 P2C 结果返回给 iOS**：拒绝。它是 prospective projection，缺少正式 Session/Approval/Turn 同事务和 read-back。
- **先写 Event，再补 Session/Approval/Turn**：拒绝。会留下孤立正式资源，违反 ADR-0005 和 `SAFE-INV-06`。
- **在 P2D 选择 PostgreSQL/ORM/隔离级别**：暂不采用。该决定依赖容量、迁移、隐私、部署和跨区要求，必须由 REL-01 GATE-05 另行冻结。
- **让 Agent 或 iOS 直接调用 repository**：拒绝。写权限属于服务端 Application/Repository，Agent 只能返回未确认候选。
- **用 receipt 代替 Event**：拒绝。receipt 只描述事务结果元数据；正式 completed 必须由 read-back 证明 Event 存在。

## 不变量与后果

- P2B/P2C prospective revision 只作为正式事务的输入关系；P2D 不推进 P2A ledger。
- 任何 partial write、重复 Event、跨用户成功、旧 revision 成功或 read-back 不一致都阻断 committed 结果。
- Receipt 不携带用户身份、候选正文、raw input、Safety answers、Prompt、Provider 响应或健康摘要；日志只保留脱敏 ID/错误码/状态/revision/计数。
- 正面：未来数据库、API 和 iOS 恢复可以围绕同一事务写集与 read-back 契约演进，避免复制旧 HTTP adapter 的未类型化副作用。
- 代价：当前只能验证 contract/fake repository；真实事务、锁、审计、Consent、expiry/tombstone 和跨实例恢复仍未实现，P2D 不能进入生产。

## 验证、停止与回滚

- 验证：`TEST-P2D`、`confirmation-transaction-receipt.schema.json`、P2/P2A/P2B/P2C 全量回归、Schema/privacy/link/OpenAPI 无新增 route 检查。
- 停止：任何部分提交、重复 Event、跨 owner 成功、stale revision 成功、read-back 不一致却返回 committed、receipt 泄露健康正文。
- 回滚：关闭 `P2D_CONFIRMATION_TRANSACTION_CONTRACT_PROTOTYPE`，调用方回到 P4 未确认草稿和安全入口；不删除正式历史。
- 本 ADR 不批准真实 Provider、临床规则、人体资产、数据库、认证、Consent、审计或医疗服务发布。
