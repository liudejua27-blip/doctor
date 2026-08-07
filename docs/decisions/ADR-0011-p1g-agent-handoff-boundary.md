# ADR-0011：P1G P1F → PydanticAI Agent 内部交接边界

| 属性 | 值 |
|---|---|
| ADR ID | ADR-0011 |
| 状态 | Accepted for prototype; production review required |
| 日期 | 2026-08-06 |
| 决策角色 | Agent 工程、后端架构、安全、隐私、QA |
| 关联功能 | FEAT-P1G-P1F-AGENT-HANDOFF-SLICE、FEAT-P1F、FEAT-P1B、FEAT-P3 |
| 关联规范 | DOC-00、ARCH-01、AGENT-01、SAFE-01、PRIV-01、FRAME-01、ADR-0002、ADR-0010 |

## 1. 背景

P1F 已把 iOS typed draft 经过服务端 SafetyEngine 变成脱敏的 `ready_for_agent` handoff，但刻意没有调用 Agent。若直接修改既有 P1B `AssessmentService.assess()`，会把 P1D/P1F 的 DTO、P1B 的文本输入、安全评估和未来公开 API 混在一起，无法证明“P1F 安全门之后才调用模型”。因此需要一个独立、内部、无副作用的 P1G use case。

## 2. 决策

选择独立 `P1GAgentHandoffService`：

```text
P1F handoff
  → 验证 status=ready_for_agent + server_safety invariants
  → StructuredPromptBuilder(typed AssessmentDraft)
  → AgentDependencies(主体 + typed context + scopes)
  → PydanticAI AssessmentAgentRunner
  → PolicyValidator
  → 脱敏 P1G result
```

P1G：

- 只调用现有 `AssessmentAgentRunner` 和四个只读 PydanticAI 工具；
- 只接受 `ready_for_agent`，不相信客户端 safety/phase/display 字段；
- 不重新运行 SafetyEngine，不允许模型改变安全等级；安全事实变化必须新 revision 回到 P1F；
- 以结构化 `AssessmentDraft` 生成 prompt，不传 P1D 完整 `raw_user_text`、安全答案原文、身份或内部异常；
- 只返回 `AskQuestionCandidate`/`DraftCandidate`，通过 `PolicyValidator` 后仍是未确认候选；
- 不新增 HTTP route、Provider、数据库、repository 或正式资源。

## 3. 被否决方案

### 3.1 直接扩展 P1B `AssessmentService.assess()`

否决。其输入是 `UserTurnInput` 文本和独立 `SafetyEngine`，会重复安全运行并掩盖 P1F gate；还会让 P1F 结果无法单独证明 raw-text 和 revision 边界。

### 3.2 让 P1F 直接调用 Agent

否决。P1F 的职责是服务端安全交接；把 Agent 放入 P1F 会让结构门、安全门、模型失败和持久化边界难以分别测试。

### 3.3 把 `AssessmentDraft` 直接拼成无边界 prompt

否决。用户标签、时间描述和功能补充是数据，不是指令；必须由 builder 固定 envelope、排序和字段白名单，禁止完整 raw text、身份和工具元数据扩散。

### 3.4 新增公开 Agent endpoint

否决。认证、Consent、幂等、Turn 持久化、错误码、数据地区、Provider 留存和发布基线尚未完成；P1G 只能是内部 use case。

## 4. 信任与权限边界

| 层 | 权威事实 | P1G 行为 |
|---|---|---|
| P1F `server_safety` | 当前 revision 的确定性安全门 | 只验证，不覆盖、不降级 |
| `AssessmentDraft` | 未确认 typed 身体事实候选 | 作为数据投影，不是系统指令 |
| `AgentDependencies` | 服务端主体、scope、typed context | 只读工具授权和 source audit |
| PydanticAI Agent | 问题/草稿候选 | 不可信，必须 PolicyValidator |
| P1G result | 状态、候选、脱敏来源/错误 | 不产生正式资源 |

`authenticated_user_id` 只用于构造依赖，不进入结果；`agent_source_ids` 只说明读取过哪些脱敏来源，不等于用户确认或档案事实。

## 5. 后果

优点：P1F 安全顺序和 P1G 模型行为可以独立测试；P1B 既有文本路径保持稳定；工具权限、raw-text 约束和候选策略清晰。

代价：短期维护 P1B/P1F/P1G 三个相邻入口；结构化 prompt 仍可能包含用户填写的短文本，需要新的 Provider/隐私评审；多轮持久化、重试和真实模型评测必须另立 Feature。

## 6. 原型退出条件

1. P1F non-ready 的 runner 调用始终为 0；
2. P1F ready 才可进入 PydanticAI，客户端安全状态不能放行；
3. TestModel/FunctionModel 的 ask/draft union、工具 scope、Policy/digest/marker 失败均 fail closed；
4. raw text、身份、token、内部异常和完整 prompt 不出现在 result/error/普通日志；
5. formal resource counter 始终为 0，OpenAPI 不增加 operation；
6. P1G Schema registry、P1G 聚焦测试和后端全量回归通过。

生产退出条件仍包括真实 Provider、Consent/认证、Turn 持久化、数据地区/留存、SafetyBaseline、Golden Set、临床内容、设备和隐私法务签字。

## 7. 回滚

关闭 `P1G_AGENT_HANDOFF_PROTOTYPE` 或移除 P1G 调用；保留 P1F `ready_for_agent`、2D/离线草稿和 P1B 独立入口；不删除历史 Event，不改变 P1F/P2 状态。

## 8. 原型验证记录

该原型的历史聚焦测试已经归并到 [BASELINE-01](../18_IMPLEMENTED_PROTOTYPE_BASELINE.md)；当前聚合状态以 [EVIDENCE-01](../16_EXECUTION_EVIDENCE.md) 为准。样机证据不关闭真实 Provider、认证/Consent、临床、持久化或发布门禁。
