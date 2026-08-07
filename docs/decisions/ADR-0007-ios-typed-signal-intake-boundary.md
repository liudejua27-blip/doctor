# ADR-0007 iOS typed signal intake boundary

| 属性 | 值 |
|---|---|
| 状态 | Accepted for prototype |
| 日期 | 2026-08-05 |
| 决策者 | 产品架构、iOS、Agent、后端、安全 |
| 相关需求 | FEAT-P1D-IOS-SIGNAL-INTAKE-CORE-SLICE |
| 相关文档 | UX-01、DATA-01、SAFE-01、IOS-01、ADR-0002、ADR-0006 |

## 背景

P1A 的人体地图可以产生 `BodyLocation`，P4 可以保护简单的未确认草稿，但 iOS 仍缺少把“哪里、什么感觉、程度、时间、诱因、功能影响和背景”组织成可复核对象的领域边界。若直接在 SwiftUI View 中拼字符串，再交给 Agent 或草稿存储，会把 UI 状态、用户事实和 AI 候选混在一起，无法阻止默认值、普通 Agent 越过安全门禁或候选直接入档。

## 决策

1. 新增客户端本地投影 `SignalIntakeDraft`，与服务端 `AssessmentDraft` 语义对齐但不冒充公开 API；
2. 事实值、来源 (`SignalFactSource`) 和状态 (`SignalFactStatus`) 分开建模；
3. 所有枚举使用稳定代码，显示文案只在 SwiftUI 层本地化；
4. 用显式 `SignalIntakePhase` 状态机阻止没有位置、没有安全结果、未复核事实时推进；
5. 安全状态 `no_rule_triggered` 与“安全”严格分离；`unavailable` 只能走离线未确认草稿或错误；
6. iOS 端只做本地非法状态防护，最终安全规则、权限、版本、确认和 Event 写入必须由服务端重新校验；
7. `SignalIntakeDraft` 不允许携带正式 Event、Episode、Approval、Report 或诊断字段；
8. SwiftUI 使用 `Form` + 分区和可访问标签；位置仍由原生 SwiftUI/RealityKit 边界提供，绝不把 RehabMate Web 实现带入生产。

## 备选方案

### 在 View 中直接保存字典

拒绝。字典无法表达来源、未知和候选状态，编码错误会在运行时才暴露。

### 复用 `DraftEnvelope.facts` 的字符串数组作为全部领域模型

拒绝。P4 的 envelope 是同步/加密边界，字符串数组只用于最小样机；把它作为录入真源会丢失上下文和状态。P1D 只在映射层把 typed draft 降维为 P4 `UnconfirmedDraftFacts`。

### 在 iOS 端复制安全规则或让 LLM 决定安全

拒绝。规则必须由服务端版本化、确定性执行并先于 PydanticAI；客户端本地状态机只能 fail closed，不能产生临床结论。

## 后果

正面：UI、草稿、Agent DTO 和测试可以分别演进；未知和候选不会被静默升级；离线与 2D 回退有明确边界；状态机可在没有网络时验证。

代价：需要维护 Swift 与 Pydantic 模型之间的版本映射；真实联调前必须关闭 REL-01 GATE-07；P1D 不能被宣传为 AI 分析完成。

## 验收与回滚

- 验收依据 `TEST-P1D-IOS-SIGNAL-INTAKE-CORE-SLICE` 和 `ios-signal-intake.schema.json`；
- 若服务端最终契约不兼容，保留 P1D 本地投影，新增显式 adapter/version，而不是修改既有稳定字段含义；
- 若状态机或安全边界发现缺陷，关闭入口 feature flag，P1A 2D 位置记录和 P4 未确认草稿不受影响。
