# ADR-0010：P1F Application Service 内部交接边界

| 属性 | 值 |
|---|---|
| 决策 ID | ADR-0010 |
| 状态 | Accepted for prototype; production review required |
| 日期 | 2026-08-06 |
| 决策人角色 | 后端架构负责人、AI 工程负责人、安全负责人 |
| 关联功能 | FEAT-P1F-IOS-SIGNAL-INTAKE-APPLICATION-HANDOFF、FEAT-P1E、FEAT-P1B |
| 关联规范 | DOC-00、ARCH-01、AGENT-01、API-01、SAFE-01、PRIV-01、FRAME-01、ADR-0002、ADR-0008、ADR-0009 |
| 替代/被替代 | 新增；不替代 P1E 适配边界或既有 P1B `AssessmentService.assess()` |

## 1. 背景

P1E 已经能把 iOS `SignalIntakeDraft` 严格转换为未确认 `AssessmentDraft`，但它不能自行运行服务端安全规则，也不能拥有 Application Service 的会话、权限和状态权威。如果直接把 P1E 接到 Agent 或公开路由，会产生以下风险：

- 客户端 `ordinary_agent_allowed`、`phase` 或旧规则版本被当作服务端许可；
- SafetyEngine 发生在模型之后，违反 `SAFE-INV-02`；
- 原始用户话术被复制到 adapter result、普通日志或错误；
- 多位置关系、revision、Profile/System source 或未确认候选被静默放大；
- P1D 联调临时端点绕过 P2 Confirmation/Approval/Event 事务；
- 修改现有 P1B `AssessmentService.assess()` 以接收 P1D 自由 Mapping，破坏既有契约。

FRAME-01 要求在实现前先定义 P1F；因此本 ADR 只决定内部 handoff 边界，不决定公开 API、真实 Provider 或临床规则。

## 2. 决策驱动因素

1. 规则必须先于任何普通 Agent；
2. P1E 继续保持纯适配、无副作用；
3. raw text 只可在 SafetyEngine 的短生命周期输入中使用，不可进入结果/错误/日志；
4. 既有 P1B API 和 P2 事务必须保持兼容；
5. 2D/offline 路径必须在服务端失败时保持可用；
6. 未来公开 API 必须能从内部 handoff 明确映射而不是直接暴露内部对象。

## 3. 备选方案

### 3.1 方案 A：在 P1E 适配器内部运行 Safety 或 Agent

否决。Domain adapter 会拥有 Application 编排职责，无法复用认证/Consent/revision，且会让纯函数产生隐式 Provider 或安全依赖。

### 3.2 方案 B：扩展现有 `AssessmentService.assess()`，把 P1D draft 塞进 `UserTurnInput.text`

否决。会丢失八事实组、显式 marker 关系和来源状态；还会把结构化数据重新拼成自由文本，难以证明字段完整性和 raw-text 边界。

### 3.3 方案 C：新增公开 `/v1/.../ios-intake` endpoint，直接返回 Agent 草稿

否决。P1F 尚未解决认证、Consent、API 错误码、幂等、ETag、草稿持久化和发布基线；公开 endpoint 会把内部实验契约变成承诺。

### 3.4 方案 D：新增内部 Application Service handoff use case

选择。Application Service 接收 typed P1D draft，调用 P1E 做结构 gate，调用当前 SafetyEngine，再调用 P1E 生成 P1F 脱敏结果；`ready_for_agent` 只交给后续独立 Agent use case，P1F 不运行 Agent、不写正式资源。

## 4. 决策内容

### 4.1 输入边界

`IOSSignalIntakeApplicationRequest` 必须包含：

- typed `IOSSignalIntakeDraft`，schema 版本严格为 `1.1`；
- 服务端绑定的 `expected_session_id` 和 `expected_draft_revision`；
- 已通过 Pydantic 的结构化 `SafetyAnswer` 集合；
- 服务端 `request_id`，不承载用户身份或原文。

不得增加第二个自由文本参数；完整 `raw_user_text` 只能从 P1D draft 的 transient 字段读取到安全规则调用。

### 4.2 顺序和结果

```text
P1D typed draft
  → P1E structural adapt without server safety
  → SafetyEngine.evaluate(current server rules)
  → P1E adapt with that exact SafetyEvaluation
  → P1F handoff result
```

结果使用 `ios-signal-intake-application-handoff.schema.json`：

- `ready_for_agent`：只在 complete/supported/R2/R3/no unresolved/ordinary allowed 时携带 `AssessmentDraft`；
- `safety_action_required`：高风险、未解决或 unsupported；不携带 draft；
- `offline_only`：规则不可用或安全预检异常；不携带 draft；
- `rejected`：结构/session/revision/source/序列化错误；带固定 error code，不泄露异常。

P1F 不返回安全答案、原始话术、用户 ID、token、Provider/model、正式资源引用或隐藏推理。

### 4.3 责任分配

| 能力 | P1F Application Service | P1E adapter | P1B Agent/Service |
|---|---|---|---|
| schema/session/revision gate | 调用并绑定 | 实际结构校验 | 不负责 |
| 当前确定性 Safety | 负责调用和结果权威 | 只消费传入结果 | 不能覆盖 |
| PydanticAI 调用 | 禁止（本切片） | 禁止 | 后续 use case 负责 |
| Profile/Consent 读取 | 当前不读取；未来由 P3/应用层授权 | 拒绝客户端 profile/system | 仅 typed context 工具 |
| Event/Approval/Episode/Report | 禁止 | 禁止 | P2 Confirmation/事务负责 |
| raw text | transient 传给 Safety | 不返回 | 后续 Provider 是否可用另行审批 |

### 4.4 幂等和副作用

P1F 在当前样机中是纯/可重复的 Application use case：相同 typed draft、session、revision、Safety answers 和规则版本应返回等价结果；不创建 resource ID、不修改 EventStore、不创建 Approval。生产持久化、幂等键、审计事件和并发 CAS 由未来公开 Assessment use case 决定，不能在 P1F 中模拟成已完成。

## 5. 后果

### 正面

- P1E 保持可单测、无副作用；Safety 顺序可以被 spy/故障注入证明；
- P1B 既有文本 Assessment 不被 P1D DTO 破坏；
- P1F 结果明确区分安全行动、离线和 Agent-ready，不把准备状态伪装成分析完成；
- 未来可在不改变 P1E schema 的情况下增加公开 API adapter。

### 代价与风险

- 当前需要维护 P1D、P1E、P1F 三个相邻契约；
- SafetyEngine 目前是样机规则目录，不能证明临床安全；
- P1F ready 仍不是 Agent 输出，也不是用户确认或正式 Event；
- raw text 的 Provider 发送、Consent、持久化和审计仍需独立设计。

## 6. 验证和退出条件

原型退出条件与当前证据：

1. P1F JSON Schema、ADR 和 BASELINE-01 的文档链接/版本检查；
2. 结构失败不调用 Safety、Safety 失败不调用 Agent、P1F 内 Agent 调用为 0；
3. R0/R1/incomplete/unavailable/unsupported 永不 ready；
4. raw text、身份和内部异常不进入 handoff/result/error/log；
5. formal resource counter 始终为 0；
6. P1F 不增加公开 operation，OpenAPI 不出现新的 P1F endpoint。

当前聚合测试状态统一见 [EVIDENCE-01](../16_EXECUTION_EVIDENCE.md)，不得引用已删除的逐轮证据编号作为当前绿色结论。

回滚：关闭 P1F use case 调用，保留 P1D 本地未确认草稿、P1E 纯适配和 2D 入口；不删除历史确认 Event，不修改既有 P1B/P2 状态。

## 7. 追踪

| 对象 | ID/链接 |
|---|---|
| 功能 | [FEAT-P1F](../18_IMPLEMENTED_PROTOTYPE_BASELINE.md) |
| 测试 | [TEST-P1F](../18_IMPLEMENTED_PROTOTYPE_BASELINE.md) |
| 结果契约 | [ios-signal-intake-application-handoff.schema.json](../contracts/ios-signal-intake-application-handoff.schema.json) |
| 上游采用 | [FRAME-01](../17_FRAMEWORK_IMPLEMENTATION_BLUEPRINT.md)、[OSS-01](../12_OPEN_SOURCE_ADOPTION.md) |
| 安全/Agent | [AGENT-01](../05_AGENT_ARCHITECTURE.md)、[SAFE-01](../09_SAFETY_AND_CLINICAL_CONTENT.md) |
| 现有适配边界 | [ADR-0008](ADR-0008-ios-signal-intake-server-adapter-boundary.md) |

## 8. 变更记录

| 日期 | 变更 | 作者/批准人 |
|---|---|---|
| 2026-08-06 | 初稿：P1E → SafetyEngine → P1F handoff；不接 Agent、公开 API 或正式资源 | Codex / 待多角色评审 |
| 2026-08-06 | 内部 Application Service 原型实现；15 个 P1F 用例、后端全量、Schema/OpenAPI/文档检查通过；生产门禁保持未关闭 | Codex / 待多角色评审 |
