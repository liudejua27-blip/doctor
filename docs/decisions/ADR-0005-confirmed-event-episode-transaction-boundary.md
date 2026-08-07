# ADR-0005：确认事件与 Episode 的事务边界

| 属性 | 值 |
|---|---|
| ADR ID | ADR-0005 |
| 状态 | Accepted for P2 prototype; production implementation blocked |
| 日期 | 2026-08-05 |
| 负责人 | 后端/数据架构负责人 |
| 关联功能 | FEAT-P2-CONFIRMED-EVENT-STORE-SLICE |
| 关联规范 | DATA-01 §5/§6、API-01 §7.5/§7.7～7.10、SAFE-01、PRIV-01 |

## 背景

P1 的 `PrototypeApprovalStore` 可以证明两阶段确认、Approval revision 和重放，但它只产生 `PrototypeEventReceipt`，没有证明正式事件必须同时属于当前用户的 Episode，也没有证明失败时不会留下孤立 Event 或错误的 Episode revision。

## 决策

第二次 `approve` 由 Application/Approval 层协调一个事务边界：

1. 从服务端保存的 Draft、原始输入、确定性 SafetyEvaluation、Agent 版本、用户确认收据和 `EpisodeSelection` 组装 Event；
2. 重新校验用户/Approval/Session/Draft/Episode 所有权、revision、digest、Safety gate、位置引用和确认状态；
3. 在同一事务中创建或更新 Episode，并写入 `lifecycle=confirmed` 的不可变 `BodySignalEvent`；
4. 只返回一个与真实 Event 副作用集合相等的 `result_ref`；
5. 幂等重放只读取首次结果，不再次创建 Event 或递增 Episode；
6. 当前 P2 只实现进程内 `RLock + PrototypeEventStore`。正式生产必须替换为带事务、约束、审计和恢复任务的持久化仓库，不能把样机实现直接部署。

## Episode 目标规则

- `create_new`：用户提供 `started_on`，服务端创建中性标题和 `revision=1` 的新 Episode；
- `join_existing`：只允许同用户 `open/monitoring`，必须匹配当前 revision；`monitoring` 因新 Event 转为 `open`；
- `reopen_existing`：只有用户明确选择时允许 `resolved/closed → open`；
- 服务端不能从部位、感觉、Agent 摘要或缓存自动选择或重开 Episode。

## 否决方案

- **客户端先写 Event，再由服务端补 Episode**：会产生越权、孤立 Event 和重复写入窗口，违反服务端权威。
- **只保存 Approval receipt，不建 Event**：无法验证 DATA-01 的正式 Event schema、报告输入和 Episode 归属。
- **按最后写入覆盖 Episode**：会丢失 revision 冲突，违反追加式历史和幂等约束。
- **把 Agent 工具直接授予写入权限**：破坏 ADR-0002 的 Agent/Application 边界，明确禁止。

## 后果

正面：Event/Episode 所有权和一致性有单一入口；Event digest、Episode revision 和 Approval result 可以互相校验；2D/3D、Agent 和报告未来都只依赖同一正式事件对象。

代价：确认请求必须增加结构化 `EpisodeSelection`，P1 草案 API 版本升为 `1.1.0-draft`；正式持久化前需要重做事务、锁、审计、迁移、删除传播和跨设备恢复；P2 内存状态重启即丢失。

## 验证与回滚

- 验证：`backend/tests/test_events.py`、`body-signal-event.schema.json`、P2 HTTP Event/Episode recovery、P1 全量回归。
- 停止条件：重复 Event、跨用户读取、stale 写入、R0/R1 confirmed 写入、部分事务或未知位置引用。
- 回滚：关闭 `P2_CONFIRMED_EVENT_STORE_PROTOTYPE`，恢复 P1 只生成 pending Approval/PrototypeEventReceipt；不删除未确认草稿或正式历史。
- 本 ADR 不批准 Provider、临床规则、人体资产或生产数据库。
