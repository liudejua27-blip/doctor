# ADR-0009：参考项目采用与原生重写边界

| 属性 | 值 |
|---|---|
| 决策 ID | ADR-0009 |
| 状态 | Accepted for design baseline; production review required |
| 日期 | 2026-08-06 |
| 决策人角色 | 系统架构负责人、AI 工程负责人、iOS 负责人 |
| 关联功能 | FRAME-01、FEAT-P1A、FEAT-P1B、FEAT-P1D、FEAT-P1E |
| 关联规范 | DOC-00、ARCH-01、IOS-01、AGENT-01、BODY-01、OSS-01、API-01、SAFE-01、PRIV-01、ADR-0018 |
| 替代/被替代 | 新增；不替代 ADR-0002、ADR-0004 或 ADR-0008 |

## 1. 背景

项目需要一个擅长强类型结构化提取、追问、资料读取和工具权限的 Agent 框架，也需要一个可验证的身体旋转、区域标记、精确点和视角交互参考。用户指定 PydanticAI 和 RehabMate 作为参考项目，但两者的用途、许可证、运行时和医疗语义完全不同：

- PydanticAI 是 Python Agent 运行时，能帮助约束模型输出和工具边界，但它不是身份、同意、安全规则或领域数据库；
- RehabMate 是静态 Web/Three.js 交互样本，其人体资产、区域算法和临时状态不能直接成为 iOS 生产模型或身体本体；
- 直接复制上游实现会混入 Web 运行时、未经审核的空间语义和没有确认/审计的临时状态；
- 完全不参考上游又会丢失已验证的交互问题和公开 API 的工程经验。

因此需要把“使用”定义为可追踪的采用分类，而不是笼统的“套用”。

## 2. 决策驱动因素

1. 强类型、可测试、可替换的 Agent 边界优先于模型展示效果；
2. 确定性安全规则、用户确认、正式写入和权限必须位于 PydanticAI 之外；
3. iOS 首发采用 SwiftUI + RealityKit 原生栈，2D 必须是完整回退路径；
4. 2D/3D 位置必须共享 `BodyLocation`，不接受仅世界坐标或模型顶点下标的事实；
5. 上游代码、依赖和资产的许可、版本、作者链和回滚必须可审计；
6. 任何不能通过临床/隐私/设备/无障碍门禁的能力必须保持关闭，不以参考项目的现成实现作为豁免。

## 3. 备选方案

### 3.1 方案 A：直接复制 RehabMate Web 到 iOS WebView

否决。它会把 Three.js、GSAP、DOM 状态、模型坐标和临时列表带入生产；无法满足 SwiftUI/RealityKit 原生要求、VoiceOver 语义、可靠锚点、资产迁移、权限和离线边界。它也不能把 Web 点击结果自动变成服务端确认事实。

### 3.2 方案 B：把 RehabMate 的模型和最近中心算法作为身体本体

否决。当前 `body.glb` 的作者链/商业使用仍未过门；最近椭球中心是渲染启发式，不是审核过的区域图；`face.a` 只使用三角形一个顶点，不能表达稳定表面语义。

### 3.3 方案 C：只使用 PydanticAI 的 Agent，不设独立 Application/Safety 层

否决。PydanticAI 的类型、工具和审批能约束模型运行，但不能替代认证、Consent、红旗规则、最高等级 reducer、事务和审计。该方案会让模型或客户端越过产品信任边界。

### 3.4 方案 D：锁定 PydanticAI 公共运行时 + 原生重写 RehabMate 交互

选择。PydanticAI 作为 `pydantic-ai-slim==2.23.0` 的锁定 Runtime dependency；RehabMate 只作为 Interaction/Pattern reference。后端 Domain 和 Application Service 拥有安全、授权、确认和写入；iOS 以 SwiftUI + RealityKit 重建交互并将结果写入规范 `BodyLocation`。

## 4. 决策

### 4.1 PydanticAI

- 生产代码只使用 `Agent`、`RunContext`、公开工具集/延迟工具、Pydantic 输出和测试模型等公开抽象；不依赖私有模块或 `main`。
- 单一 `AssessmentAgent` 只生成 `AssessmentAgentOutput`：普通追问、候选草稿、模型安全线索或安全失败；它不能写 Event、Approval、Profile 或 Report。
- Application Service 在每次运行前执行当前全部确定性安全规则，绑定 `AgentReadContext`、ConsentScope、版本和工具策略；只有完整、支持场景、R2/R3 才能进入普通 Agent。
- 模型工具审批不是用户身份认证或业务授权。恢复时必须重验主体、资源、digest、revision、有效期、Consent 和 SafetyBaseline。
- `TestModel`/`FunctionModel` 仅用于流程、契约和故障注入；真实 Provider 需另有隐私、地区、留存、结构化输出和锁定集评测决定。

### 4.2 RehabMate

- 只参考旋转/缩放、前后左右视角、区域与精确点两种表达、选中/聚焦和“命中表面→生成 Marker”的交互问题。
- iOS 使用 SwiftUI + RealityKit 原生实现；2D 列表/搜索/无障碍路径与 3D 生成同一 `BodyLocation`。
- 禁止生产复用 `index.html`、Three.js、GSAP、DOM 状态、`muscles.js` 生产本体、最近椭球中心、`face.a` 区域判定、点击三态、默认“酸痛”、世界坐标针点和 `assets/body.glb`。
- 任何未来代码复制都必须在第三方清单记录文件、锁定提交、复制范围、修改、版权/许可证和删除路径；默认采用原创 Swift/RealityKit 实现。

### 4.3 两者之间的反腐层

```text
RehabMate interaction idea ──→ iOS BodyKit candidate ──→ BodyLocation
PydanticAI candidate        ──→ PolicyValidator        ──→ AssessmentDraft
BodyLocation + Draft        ──→ Application confirmation ──→ Event/Episode
```

上游对象不能直接跨越反腐层成为领域事实。任何“方便联调”的自由 Mapping、客户端安全结果、模型坐标、默认感觉或模型确认字段都必须拒绝或降级。

## 5. 后果

### 正面

- 可以利用 PydanticAI 的强类型和测试能力，同时保持安全/授权/持久化独立；
- iOS 能获得接近用户期望的旋转、标记和视角体验，又不承受 WebView 和上游模型的生产风险；
- 上游升级、资产替换或模型切换不会直接改变 `BodyLocation`、Event 或 SafetyBaseline 语义；
- 2D、离线、无障碍和服务端回退路径可独立验证。

### 代价与风险

- Swift/Python 必须共同维护 JSON Schema、来源和 revision 语义；
- 原生 3D 需要重新做碰撞、锚点、LOD、无障碍和真机性能测试；
- PydanticAI 升级、Provider 更换或提示词变化都可能改变安全基线，不能当作普通依赖升级；
- 当前仍没有生产人体资产、临床规则、认证/Consent、真实 DB 或 Provider 批准，因此框架不能宣称生产完成。
- `BodyAssetManifest`/`BodyAssetRuntimeGate` 已固定为真实资产进入 RealityKit 前的 metadata 反腐层；当前只验证合成清单，不能把 `approved` fixture 当作上游模型或医学定位批准。

## 6. 验证和退出条件

### 6.1 当前设计基线

- FRAME-01 已记录采用分类、目录、端到端合同和实施边界；当前未决生产条件统一由 REL-01 管理；
- OSS-01 已锁定 RehabMate 提交和资产/算法禁止清单；
- AGENT-01 已固定 PydanticAI 版本和 Agent/Safety/Policy 边界；
- P1A/P1B/P1D/P1E/P2/P3/P4 的样机证据仍按 EVIDENCE-01 标记为 prototype。

### 6.2 后续实施结果

原 P1F 及其后续内部切片已经完成样机验证，并归并到 [BASELINE-01](../18_IMPLEMENTED_PROTOTYPE_BASELINE.md)。它们保持无公开 endpoint、无正式写入、无真实 Provider 健康请求；进入生产所需的 Provider、身份/Consent、数据库、临床和设备条件统一由 REL-01 管理。

### 6.3 重新评估/回滚

以下任一条件触发 ADR 复审和受影响能力关闭：

- PydanticAI 公开 API、依赖许可证、Provider 数据处理或版本兼容发生变化；
- RehabMate 作者链、GLB 权利、上游代码许可证或引用范围发生变化；
- 原生命中金标、左右侧、低置信映射、VoiceOver 或最低设备性能不达门槛；
- 任一模型/客户端路径能降低安全等级、绕过用户确认或产生正式写入；
- 发生跨账号、原始健康日志、资产许可或严重安全事件。

回滚方式是关闭 Agent/3D 能力开关并保留 2D 结构化记录和安全入口；不得以回滚为理由删除历史确认事实或覆盖原始位置锚点。

## 7. 追踪

| 对象 | ID/链接 |
|---|---|
| 框架蓝图 | [FRAME-01](../17_FRAMEWORK_IMPLEMENTATION_BLUEPRINT.md) |
| Agent/Safety | [AGENT-01](../05_AGENT_ARCHITECTURE.md)、[ADR-0002](ADR-0002-agent-and-safety-boundary.md) |
| iOS/3D | [IOS-01](../04_IOS_ARCHITECTURE.md)、[BODY-01](../08_BODY_MAP_2D_3D.md)、[ADR-0004](ADR-0004-ios-3d-rendering-boundary.md) |
| 资产清单门禁 | [FEAT-P1A-3D-ASSET-MANIFEST-SLICE](../18_IMPLEMENTED_PROTOTYPE_BASELINE.md)、[ADR-0018](ADR-0018-body-asset-manifest-runtime-gate.md) |
| 上游审计 | [OSS-01](../12_OPEN_SOURCE_ADOPTION.md) |
| P1E 边界 | [ADR-0008](ADR-0008-ios-signal-intake-server-adapter-boundary.md) |
| 测试/证据 | [QA-01](../11_TEST_AND_EVALUATION.md)、[EVIDENCE-01](../16_EXECUTION_EVIDENCE.md) |

## 8. 变更记录

| 日期 | 变更 | 作者/批准人 |
|---|---|---|
| 2026-08-06 | 初稿：锁定 PydanticAI runtime、RehabMate 原生重写边界和 FRAME-01 执行门禁 | Codex / 待多角色评审 |
