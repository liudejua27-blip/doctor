# ADR-0012：P1H Agent Turn Application 内部多轮边界

| 属性 | 值 |
|---|---|
| ADR ID | ADR-0012 |
| 状态 | Accepted for prototype; production review required |
| 日期 | 2026-08-06 |
| 决策角色 | Application Service、Agent、后端/API、安全、隐私、QA |
| 关联功能 | FEAT-P1H-AGENT-TURN-APPLICATION-SLICE、FEAT-P1F、FEAT-P1G、FEAT-P2 |
| 关联规范 | DOC-00、ARCH-01、AGENT-01、DATA-01、API-01、SAFE-01、PRIV-01、FRAME-01、ADR-0010、ADR-0011 |

## 1. 背景

P1F 已负责把 iOS typed draft 通过服务端 SafetyEngine 变成安全投影，P1G 已负责在 `ready_for_agent` 之后调用 PydanticAI 并返回未确认候选。两者之间仍缺少一个 Turn Application 边界：它无法证明同一 session 的前驱关系、sequence/revision 单调性、重试幂等和“追问回答必须新建 P1F handoff”。若直接把 P1G 结果暴露为 `agent-turn.schema.json` 或修改现有 HTTP 样机，会把 transient Agent 输出、公开生命周期和未来持久化混为一谈。

## 2. 决策

新增独立、内部、默认关闭的 `AgentTurnApplicationService`，采用如下链路：

```text
caller 生成新的 typed P1F handoff
  → P1H 重新验证 handoff + session/turn/sequence/revision/前驱
  → P1H 进程内 ledger 做幂等/CAS preflight
  → P1G ready-only handoff → Structured prompt → PydanticAI → PolicyValidator
  → P1H 映射为 AgentTurnApplicationResult
  → 原子写入 transient ledger（仅 result + digest + 当前 Turn 元数据）
```

决策细节：

1. P1H 不接收自由文本或安全答案，不重新运行 SafetyEngine。用户回答必须在上游转换为新 P1D draft，再由 P1F 运行当前规则并把新的 handoff 交给 P1H。
2. 首轮要求 `sequence=1`、无前驱；继续只允许从 `awaiting_user` 出发，要求前驱为 ledger 当前 Turn、`sequence=last+1`、`draft_revision>last`。
3. 相同 idempotency key 和 canonical request digest 重放同一 result，不重复调用 P1G；同 key 不同摘要、重用 Turn/sequence、前驱或 revision 冲突均 fail closed。
4. P1H result 只携带 P1G 状态、未确认候选、版本、脱敏来源和固定错误；不携带身份、raw text、prompt、messages、隐藏推理、Safety answers 或正式资源引用。
5. `draft_ready` 进入 P2 Confirmation/Approval；P1H 不创建 Approval 或 Event。`ask_question` 只能等待下一次经过 P1F 的 typed handoff。
6. ledger 是进程内原型 fixture，重启丢失；它不能被描述为 Turn 持久化、跨设备同步或正式幂等存储。

## 3. 被否决方案

### 3.1 直接扩展 P1G 以保存消息历史

否决。Agent/PydanticAI 不是长期事实存储；保存消息会扩大隐私留存、Provider 绑定和删除边界，也无法替代 session owner、Consent 和数据库 CAS。

### 3.2 P1H 接收用户原话并自己运行安全

否决。这样会形成第二个安全入口，可能绕过当前 SafetyBaseline、规则版本和 P1F 的结构/marker 约束。安全变化必须由新的 P1F request 完成。

### 3.3 用既有 `agent-turn.schema.json` 直接作为 P1H result

否决。既有 schema 包含公开 Turn 的 `input`、安全信封、生命周期和时间字段；P1H 当前没有持久化、认证、完整安全答案或正式 Turn 资源，直接复用会产生虚假完成感。P1H 使用独立 result schema，未来持久化 Feature 再定义兼容投影。

### 3.4 让 P1H 直接调用 P2 Confirmation/Event Store

否决。Agent 候选和用户确认是不同信任层；P2 必须保留八组事实复核、Approval 双确认、Event/Episode 事务和所有权检查。

## 4. 信任边界与不变量

| 层 | 权威 | P1H 可做 | P1H 禁止 |
|---|---|---|---|
| P1F | 当前 revision 的确定性 Safety 和 typed draft 资格 | 重新验证/拒绝 | 覆盖 Safety、接受 client flag |
| P1G | Agent 候选和工具权限 | 调用、映射 | 让候选变 confirmed 或安全结论 |
| P1H ledger | 当前进程的 Turn/CAS/幂等状态 | 暂存 result/digest | 充当数据库、审计或消息历史 |
| P2 | 用户确认、Approval、Event/Episode 事务 | 只转交 draft_ready 状态 | 创建/修改正式资源 |

不可放宽的不变量：

- `SAFE-INV-02`：任何普通 Agent 运行仍必须由 P1F Safety 先行；
- `SAFE-INV-06`：候选不等于确认事实；
- `SAFE-INV-07`：失败保留安全/手动/未确认路径；
- `SAFE-INV-08`：资料读取只接受当前主体和有效授权 context；
- `NFR-REL-002`：同一幂等动作不得重复产生副作用；
- `NoRuleTriggered` 不能被 P1H 显示或重写成“安全”。

## 5. 后果

优点：P1F 安全、P1G 模型和 P1H Turn/CAS 可以独立测试；继续请求的安全回路明确；同键重试不重复调用；P1B/P2 既有样机不被修改；公开 API 仍无新增承诺。

代价：短期存在 P1B/P1F/P1G/P1H 四个相邻内部入口；内存 ledger 不能在重启后恢复；真实多轮体验仍需 iOS、持久化、认证、Consent 和数据留存设计；typed draft 中的用户标签仍需要真实 Provider 隐私评审。

## 6. 原型退出条件与回滚

原型退出条件：P1H Feature/TEST/Schema/TRACE/证据链完成；ready-only、安全回退、前驱 CAS、幂等、重放、隐私和零正式副作用测试通过；P1B/P1F/P1G/P2 和后端全量回归通过；OpenAPI 无新增 operation。上述只表示 `Prototype verified`。

生产退出条件另需真实 Provider/地区/留存、认证/Consent、持久化/分布式锁、客户端离线恢复、SafetyBaseline、临床内容、Golden Set、多语言、无障碍和真实设备 E2E。

回滚：关闭 `P1H_AGENT_TURN_APPLICATION_PROTOTYPE` 或删除调用，回到 P1F/P1G 单次内部 handoff；清空 transient ledger；不删除正式 Event，不改变 P2 状态。

## 7. 变更记录

| 日期 | 变更 | 作者/批准人 |
|---|---|---|
| 2026-08-06 | 初稿：建立 P1F→P1G→P1H 的 transient Turn、前驱 CAS 和幂等边界；不接收 raw answer、不持久化、不新增公开 API | Codex / 待多角色评审 |
| 2026-08-06 | P1H 实现与 17 个聚焦用例、Schema/OpenAPI/文档检查通过；生产持久化、Provider、认证/Consent 和临床门禁保持打开 | Codex / 待多角色评审 |
