# ADR-0013：P2A Session/Turn 类型化投影边界

| 属性 | 值 |
|---|---|
| ADR ID | ADR-0013 |
| 状态 | Accepted for prototype; production implementation blocked |
| 日期 | 2026-08-06 |
| 负责人 | 后端/API + 数据架构负责人 |
| 关联功能 | FEAT-P2A-SESSION-TURN-PROJECTION-SLICE |
| 关联规范 | ARCH-01 §8、AGENT-01 §4/§7、DATA-01 §8、API-01 §4/§5、ADR-0012 |

## 背景

P1H 的进程内 ledger 已证明单次 Agent 结果的 sequence、draft revision、前驱和幂等规则，但它不是 Session 聚合，也不提供可被后续 Confirmation/Approval 恢复的类型化业务投影。当前 P2 HTTP adapter 用 `PrototypeSession.latest_turn: dict` 直接保存这些状态，无法成为数据库 schema、契约测试或正式公开 API 的安全前置。

## 决策

新增一个独立的 P2A 内部边界：

1. Application Service 只接受已通过 P1H `AgentTurnApplicationResult` 校验的结果；P1H rejected 结果不得写入。
2. `P2ASessionTurnLedger` 以服务端 owner index、`RLock`、typed `SessionProjection`/`TurnProjection` 和 request digest 保存最小状态。
3. Session revision 在一次成功投影中只递增 1；Turn revision 与新的 Session revision 相等；前驱、sequence、draft revision 由 ledger 原子校验。
4. 只有 `awaiting_user` 可以继续；`awaiting_confirmation` 必须进入 P2 事实确认，安全/离线/失败必须进入各自回退。
5. 稳定结果不暴露 owner、原始输入、Prompt、隐藏推理、访问令牌或正式资源引用；candidate 仍是未确认数据。
6. P2A 不拥有 Agent、安全、Consent、认证、Approval、Event、Episode、数据库或公开 HTTP API；P2 HTTP adapter 暂时保持隔离并标注为遗留样机。

## 选择理由

- **先建类型化内部边界，再接数据库/公开 API**：可让契约、状态和隐私字段先固定，避免把当前 HTTP 字典结构升级为事实标准。
- **不把 P1H ledger 直接扩成正式 Session**：P1H 的职责是 Agent 调用前后的 transient CAS；混入 Approval/生命周期会违反 ADR-0012 的最小边界。
- **不直接改造 P2 Event Store**：Event/Episode 事务需要真实认证、Consent、数据库和审计另行评审；P2A 只提供其上游可恢复投影。

## 禁止事项

- 不能将 `owner_user_id` 放进 P2A 稳定结果或客户端可提交字段。
- 不能从 P2A 继续调用 Agent 来绕过新的 P1F Safety 评估。
- 不能把 `awaiting_confirmation` 伪装成 `completed`，不能生成 Approval/Event/Episode 引用。
- 不能把内存重放当作跨进程幂等、崩溃恢复或正式数据保留。

## 后果

正面：Session/Turn 的状态、revision、前驱和失败语义有独立 Schema 与测试；后续 DB repository、公开 API 和 iOS 恢复可以针对同一投影契约演进；P1H、P2 Confirmation 和 P4 草稿边界保持清晰。

代价：短期存在 P2A ledger 与旧 HTTP adapter 两套样机，必须通过 Feature Flag 和文档区分；P2A 重启丢失，不能支持真实用户；正式实现仍需迁移、加密、锁、审计、删除传播和跨实例幂等。

## 验证与回滚

- 验证：[TEST-P2A-SESSION-TURN-PROJECTION-SLICE](../18_IMPLEMENTED_PROTOTYPE_BASELINE.md)、`session-turn-projection-result.schema.json`、P1/P2/P3/P4 全量回归。
- 停止条件：跨用户成功、重复 revision、错误前驱成功、P1H rejected 占用序列、稳定结果泄露 owner/raw/formal ref。
- 回滚：关闭 `P2A_SESSION_TURN_PROJECTION_PROTOTYPE`，调用方回到 P1H transient/P4 未确认路径；不删除正式历史（本切片不创建正式历史）。
