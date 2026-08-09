# 文档总索引

> 文档状态：方案与框架文档目标已完成，规范状态仍为 `Baseline Draft`。这表示文档体系、契约边界、样机追踪和实施门禁已经建立，不表示安全规则、医学内容、司法辖区、人体资产或生产系统已经获批发布。

## 当前结论

- 文档真源已经收敛到 `docs/`：需求、术语、架构、数据、API、Agent、2D/3D、安全、隐私、测试、开源采用、路线图、追踪和执行证据均有稳定入口。
- 当前工程状态只能称为 `Prototype verified`：已证明若干类型、状态、权限和失败关闭边界，未证明临床安全、生产可靠性、真实模型许可或真实用户 30 秒完成目标。
- 首发产品重心已明确为“运动/工作不适 → 位置 → 情境化 AI 追问 → 安全行动 → 复查/沟通摘要”；具体功能仍是 Draft，不能被描述为已上线或临床批准能力。
- [FEAT-IOS-P0-RUNTIME-01](28_IOS_P0_RUNTIME_HOST.md) 的仅限内部 Simulator App Host 已有本地与历史远端 CI 收据；`0105cd7` 的 94 项 Core 与 HOST-T-001～014 已由 run `31307042209` 在 iPhone 16 / iOS Simulator 18.5 重建。历史 SHA `98a4200` / run `31314859140` 的 H015 为文字部位 Sheet 关闭后 CTA 存在但不可点击。SHA `544c39a` 前的本地定向 H015 1/0/0（86.0s）和完整 Host script exit 0（402.313s）仅为历史收据。最新远端 run `31318855810`（SHA `544c39a`）中 Backend and contracts 成功，iOS 仅 Host smoke 失败：12 passed、1 failed、0 skipped，HOST-T-015 报 `Expected element to exist: body-map.next Button`（exit 65）。CI 无 artifact/accessibility hierarchy，不能断定是文字选择未保留位置还是 AX 投影/元素类型。当前工作树已实现底部独立、非滚动安全内容布局区；文字选择后先验证 marker-count summary 一项位置，再以 stable-id any-element 验证 CTA exists/hittable/tap；不以 `safeAreaInset` 或 `Button` class 作为跨 OS 契约。本地 iPhone 17 Pro / iOS 26.5 的 targeted HOST-T-015 + MoreSensations 为 2/0/0（138.1s），完整 internal Host script exit 0（426.285s）；远端尚未推送、远端重试 Pending。该工程例外不新增产品样机层，也不替代真机/生产验证；接下来仍须按 [REL-01 当前执行顺序](13_DELIVERY_ROADMAP.md#3-当前执行顺序)关闭生产门禁。
- [GOV-01 GATE-02 决策包](27_GATE_02_RESPONSIBILITY_AND_PRODUCT_BOUNDARY.md) 已准备好供具名责任人填写和书面批准；在其关闭前保持内部原型边界。
- [FEAT-COMP-01](25_CONVERSATIONAL_RECOVERY_COMPANION.md) 已附 P1I“情境 → 单一确定性追问”评审输入：当前按 CONFLICT-002 的保守临时行为由 Application Service 决定未来普通题选择权，模型只可处理当前计划的回答；它不构成 API、Schema、临床题目或实现授权。

## 文档退役登记

| 退役日期 | 原文件 | 处理 | 原因 | 替代真源 |
|---|---|---|---|---|
| 2026-08-07 | `AI_Body_Companion_iOS_产品与技术方案.md` | 物理删除 | 无稳定 ID 的早期总体分析，已明确不是执行真源，继续保留会造成重复与冲突 | 本索引；`PROD-01`、`ARCH-01`、`IOS-01`、`AGENT-01`、`BODY-01`、`SAFE-01`、`OSS-01`、`FRAME-01` |
| 2026-08-07 | `docs/features/*.md`、`docs/plans/*.md` 共 32 份 | 归并后物理删除 | 一次性工程切片全部完成，内容与核心规范、测试代码和追踪矩阵重复 | `BASELINE-01`、`QA-01`、`TRACE-01`、相关 ADR/Schema |

核心规范、ADR、机器契约、许可证据和正式发布证据不属于可清理垃圾。一次性 Feature/Test 切片只有在完整归并到核心真源和 [BASELINE-01](18_IMPLEMENTED_PROTOTYPE_BASELINE.md) 后才能删除。

## 阅读路径

```mermaid
flowchart TD
    A["DOC-00 文档治理"] --> B["TERM-01 统一术语"]
    B --> C["PROD-01 产品需求"]
    C --> D["UX-01 体验与用户流程"]
    C --> E["ARCH-01 系统架构"]
    E --> F["IOS-01 iOS 架构"]
    E --> G["AGENT-01 Agent 架构"]
    E --> H["DATA-01 领域数据模型"]
    H --> I["API-01 API 契约"]
    F --> J["BODY-01 2D/3D 人体地图"]
    G --> K["SAFE-01 安全与临床内容"]
    I --> K
    K --> L["PRIV-01 隐私、安全与合规"]
    J --> M["QA-01 测试与评测"]
    K --> M
    G --> R["FRAME-01 框架实施蓝图"]
    H --> R
    J --> R
    R --> S["BASELINE-01 当前样机"]
    S --> M
    M --> N["REL-01 交付路线图"]
    N --> O["TRACE-01 追踪矩阵"]
    J --> P["FEAT-BODY-MAP-V1 2D/3D 纵向切片"]
    P --> V["FEAT-BODY-MAP-V2 RehabMate 原生行为等价"]
    V --> Q["TEST-BODY-MAP-V2 行为等价测试"]
    Q --> X["EVIDENCE-DEVICE-01 真机与资产审核证据"]
    P --> W["TEST-BODY-MAP-V1 身体定位测试"]
    P --> T["BODY-ASSET-01 资产来源与哈希"]
```

## 当前实现入口

- [BASELINE-01 已实现样机基线](18_IMPLEMENTED_PROTOTYPE_BASELINE.md)：合并原 16 份 Feature Spec、16 份 Test Plan 的当前实现、测试和未证明范围。
- [FRAME-01 参考项目到产品框架的实施蓝图](17_FRAMEWORK_IMPLEMENTATION_BLUEPRINT.md)：长期运行时和参考采用边界。
- [FEAT-BODY-MAP-V1 全身 2D 与原生 3D 定位纵向切片](19_BODY_MAP_PRODUCTION_SLICE.md)：当前身体定位实施范围、状态、契约和发布边界。
- [TEST-BODY-MAP-V1 2D/3D 身体定位测试计划](20_BODY_MAP_TEST_PLAN.md)：身体区域、跨视图、回退、资产和无障碍测试门禁。
- [BODY-ASSET-01 候选人体显示资产来源与哈希](21_BODY_ASSET_PROVENANCE.md)：项目自生成候选模型的来源、哈希、清单和进入生产所需证据。
- [FEAT-BODY-MAP-V2 RehabMate 原生行为等价切片](22_REHABMATE_NATIVE_PARITY.md)：Zone/Pin、焦点、位置摘要/Inspector、Zone + Pin 合计 20 个位置上限和安全语义适配。
- [TEST-BODY-MAP-V2 原生行为等价测试计划](23_REHABMATE_NATIVE_PARITY_TEST_PLAN.md)：状态、回退、无障碍、性能和供应链门禁。
- [EVIDENCE-DEVICE-01 真机与资产审核证据](24_DEVICE_VALIDATION_EVIDENCE.md)：本轮设备可用性、Sheet/VoiceOver/Dynamic Type/Reduce Motion、3D 性能、碰撞命中和候选资产审核结果；Blocked 不得外推为通过。
- [FEAT-COMP-01 对话式恢复决策核心](25_CONVERSATIONAL_RECOVERY_COMPANION.md)：运动/工作不适的主闭环、AI 对话、资料可见性、审核行动、沟通摘要与 P1I 单题确定性追问的审核附录；Draft，未实现。
- [UX-COMP-01 对话式身体评估界面交付说明](30_CONVERSATIONAL_ASSESSMENT_SCREEN_SPEC.md)：上述主闭环的评审级屏幕、来源标签、安全替代、无障碍与六个走查场景；不新增契约或实现授权。
- [TEST-COMP-01 对话式恢复决策核心测试计划](26_CONVERSATIONAL_RECOVERY_COMPANION_TEST_PLAN.md)：上述主闭环的安全、隐私、无障碍、可用性和发布门禁；未执行。
- [GOV-01 GATE-02 责任与产品边界决策包](27_GATE_02_RESPONSIBILITY_AND_PRODUCT_BOUNDARY.md)：具名责任、地区、年龄、产品分类、外测与宣传边界的书面批准入口；当前 `Pending`。
- [FEAT-IOS-P0-RUNTIME-01 内部 iOS App Host](28_IOS_P0_RUNTIME_HOST.md)：受版本控制的 Simulator App Host、显式关闭能力集、默认 P0 UI smoke、专用候选 3D probe 与局部 accessibility-size 结构 smoke；基础 smoke、候选 probe 与完整感觉入口均已在本地及 run `31307042209` 的远端 CI 重建。历史 `31314859140`（SHA `98a4200`）的 H015 为 CTA 存在但不可点击；SHA `544c39a` 前的本地 1/0/0（86.0s）和 full Host script exit 0（402.313s）仅历史。最新 `31318855810`（SHA `544c39a`）的 Backend and contracts 成功、iOS 仅 Host smoke 失败（12/1/0，`Expected element to exist: body-map.next Button`，exit 65）；CI 无 artifact/hierarchy，根因未知。当前独立非滚动安全内容区、marker-count 一项位置先验、stable-id any-element CTA exists/hittable/tap 已实现；本地 iPhone 17 Pro / iOS 26.5 的 targeted H015 + MoreSensations 为 2/0/0（138.1s），full internal Host script exit 0（426.285s）；远端尚未推送、重试 Pending。不以 `safeAreaInset`/`Button` class 为契约，internal only。
- [TEST-IOS-P0-RUNTIME-01 内部 Host 测试计划](29_IOS_P0_RUNTIME_HOST_TEST_PLAN.md)：构建、安装、启动、2D/列表回退、无网络/权限/持久化负向检查、候选 Scene loader-entry/终态、完整感觉/unknown 入口和局部 accessibility-size 结构回归；本地和远端 CI 均只形成 Simulator 证据。

实现入口：

- [后端 Phase 1 样机](../backend/README.md)
- [原生 iOS Swift Package](../ios/BodyCompanion/README.md)

## 规范文件

| ID | 文档 | 作用 | 当前状态 |
|---|---|---|---|
| DOC-00 | [文档治理](00_DOCUMENTATION_SYSTEM.md) | 规范优先级、变更、DoR/DoD、版本基线 | Baseline Draft |
| PROD-01 | [产品需求](01_PRODUCT_REQUIREMENTS.md) | 用户、问题、范围、指标、非目标 | Baseline Draft |
| UX-01 | [体验与用户流程](02_UX_AND_USER_FLOWS.md) | 信息架构、30 秒主流程、异常路径 | Baseline Draft |
| ARCH-01 | [系统架构](03_SYSTEM_ARCHITECTURE.md) | 运行边界、数据流、状态与部署 | Baseline Draft |
| IOS-01 | [iOS 架构](04_IOS_ARCHITECTURE.md) | SwiftUI/RealityKit 模块与客户端状态 | Baseline Draft |
| AGENT-01 | [Agent 架构](05_AGENT_ARCHITECTURE.md) | PydanticAI、追问、工具、确认与回退 | Baseline Draft |
| DATA-01 | [领域数据模型](06_DOMAIN_DATA_MODEL.md) | Episode、事件、位置、报告与审计 | Baseline Draft |
| API-01 | [API 契约](07_API_CONTRACT.md) | 端点、权限、幂等、同步和错误 | Baseline Draft |
| BODY-01 | [2D/3D 人体地图](08_BODY_MAP_2D_3D.md) | 坐标、本体、资产、手势、映射和验收 | Baseline Draft |
| SAFE-01 | [安全与临床内容](09_SAFETY_AND_CLINICAL_CONTENT.md) | Safety Case、风险规则、内容审核 | Baseline Draft / Clinical Review Required |
| PRIV-01 | [隐私、安全与合规](10_PRIVACY_SECURITY_COMPLIANCE.md) | 同意、最小权限、数据流、审计与事件响应 | Baseline Draft / Legal Review Required |
| QA-01 | [测试与评测](11_TEST_AND_EVALUATION.md) | 测试金字塔、黄金集、影子测试和门禁 | Baseline Draft |
| OSS-01 | [开源采用与复刻边界](12_OPEN_SOURCE_ADOPTION.md) | PydanticAI/RehabMate 审计和许可边界 | Verified Snapshot |
| FRAME-01 | [参考项目到产品框架的实施蓝图](17_FRAMEWORK_IMPLEMENTATION_BLUEPRINT.md) | PydanticAI 运行时、RehabMate 交互参考和长期模块边界 | Active implementation boundary |
| REL-01 | [交付路线图](13_DELIVERY_ROADMAP.md) | 当前生产门禁、依赖和退出条件 | Active roadmap |
| GOV-01 | [GATE-02 责任与产品边界决策包](27_GATE_02_RESPONSIBILITY_AND_PRODUCT_BOUNDARY.md) | 具名责任、地区、外测与宣传边界的书面决策和退出条件 | Pending written approval |
| FEAT-IOS-P0-RUNTIME-01 | [内部 iOS App Host](28_IOS_P0_RUNTIME_HOST.md) | 仅限内部 Simulator 的可安装 App Host、显式能力关闭和 UI smoke | Implemented / Simulator verified / internal only |
| TEST-IOS-P0-RUNTIME-01 | [内部 Host 测试计划](29_IOS_P0_RUNTIME_HOST_TEST_PLAN.md) | Host 的 Simulator 构建、启动、P0 路径及负向能力检查 | Historical local HOST-T-001～015 evidence；SHA `544c39a` 前 targeted 1/0/0（86.0s）与 full Host script exit 0（402.313s）仅历史。latest remote `31318855810` (SHA `544c39a`)：Backend and contracts 成功，iOS only Host smoke failed（12/1/0；`Expected element to exist: body-map.next Button`；exit 65）；no CI artifact/accessibility hierarchy，选择丢失 vs AX projection unknown。current independent non-scrolling safe-content layout + marker-count first + stable-id any-element CTA exists/hittable/tap is implemented; iPhone 17 Pro/iOS 26.5 targeted H015 + MoreSensations 2/0/0（138.1s）and full internal Host script exit 0（426.285s）；remote not pushed/retry Pending; no `safeAreaInset`/`Button` class contract / Simulator-only evidence |
| TRACE-01 | [追踪矩阵](14_TRACEABILITY_MATRIX.md) | 当前需求到实现/验证/门禁的追踪 | Active traceability |
| TERM-01 | [统一术语](15_GLOSSARY.md) | 唯一名词和字段语义真源 | Baseline Draft |
| EVIDENCE-01 | [当前工程样机验证记录](16_EXECUTION_EVIDENCE.md) | 可复现命令、已证明边界与未证明能力 | Evidence snapshot / Prototype-only |
| BASELINE-01 | [已实现样机基线](18_IMPLEMENTED_PROTOTYPE_BASELINE.md) | 已完成临时切片归并、当前代码边界和测试状态 | Current prototype snapshot |
| FEAT-BODY-MAP-V1 | [全身 2D 与原生 3D 定位纵向切片](19_BODY_MAP_PRODUCTION_SLICE.md) | 当前 2D/3D 身体定位实施范围、状态、契约和发布边界 | Active implementation spec |
| TEST-BODY-MAP-V1 | [2D/3D 身体定位测试计划](20_BODY_MAP_TEST_PLAN.md) | 身体区域、跨视图、回退、资产和无障碍测试门禁 | Draft / implementation in progress |
| BODY-ASSET-01 | [候选人体显示资产来源与哈希](21_BODY_ASSET_PROVENANCE.md) | 候选 USDZ 的来源、哈希、权利与批准前门禁 | Candidate / production blocked |
| FEAT-BODY-MAP-V2 | [原生 iOS 身体地图交互切片](22_REHABMATE_NATIVE_PARITY.md) | Zone/Pin、焦点、位置摘要/Inspector、窄屏 Sheet 和反馈的原生重写边界；地图仅写位置，Zone + Pin 合计最多 20 个，重复 Zone 点击只选中，删除显式完成 | V2.4 automated slice implemented / device run blocked |
| TEST-BODY-MAP-V2 | [原生身体地图交互测试计划](23_REHABMATE_NATIVE_PARITY_TEST_PLAN.md) | 行为状态、回退、无障碍和供应链测试 | Automated slice implemented / device run blocked |
| EVIDENCE-DEVICE-01 | [真机与资产审核证据](24_DEVICE_VALIDATION_EVIDENCE.md) | 真机可用性、无障碍、3D 性能、碰撞命中和候选资产生产审核 | Historical Simulator Host receipts / latest remote H015 failed / physical device and production approval blocked |
| FEAT-COMP-01 | [对话式恢复决策核心](25_CONVERSATIONAL_RECOVERY_COMPANION.md) | 运动/工作不适的情境化 AI 追问、P1I 单题确定性编排审核附录、审核行动、复查和沟通摘要 | Draft / P0 visual prototype only |
| UX-COMP-01 | [对话式身体评估界面交付说明](30_CONVERSATIONAL_ASSESSMENT_SCREEN_SPEC.md) | 将既有对话式评估真源转为屏幕、来源、替代安全、无障碍与走查交付；不定义新能力 | Draft / Review-only / GATE-02 + ADR-0019 blocked |
| TEST-COMP-01 | [对话式恢复决策核心测试计划](26_CONVERSATIONAL_RECOVERY_COMPANION_TEST_PLAN.md) | 主闭环的产品、安全、隐私、无障碍与可用性验证 | Draft / P0 build passed; full plan not executed |

## 机器可读契约

- [OpenAPI v1](contracts/openapi-v1.yaml)
- [BodySignalEvent JSON Schema](contracts/body-signal-event.schema.json)
- [BodyLocation JSON Schema](contracts/body-location.schema.json)
- [AgentTurn JSON Schema](contracts/agent-turn.schema.json)
- [AgentReadContext JSON Schema](contracts/agent-context.schema.json)
- [iOS 未确认草稿 Envelope JSON Schema](contracts/ios-draft-envelope.schema.json)
- [iOS 结构化录入 JSON Schema](contracts/ios-signal-intake.schema.json)
- [iOS 结构化录入服务端适配结果 JSON Schema](contracts/ios-signal-intake-adapter-result.schema.json)
- [iOS 结构化录入 Application Service 内部交接 JSON Schema](contracts/ios-signal-intake-application-handoff.schema.json)
- [P1G Agent 内部交接结果 JSON Schema](contracts/agent-handoff-result.schema.json)
- [P1H Agent Turn Application 内部结果 JSON Schema](contracts/agent-turn-application-result.schema.json)
- [P2A Session/Turn 类型化投影结果 JSON Schema](contracts/session-turn-projection-result.schema.json)
- [P2B ConfirmationIntent 应用结果 JSON Schema](contracts/confirmation-intent-application-result.schema.json)
- [P2C Approval 决定应用结果 JSON Schema](contracts/approval-decision-application-result.schema.json)
- [P2D 确认事务回执 JSON Schema](contracts/confirmation-transaction-receipt.schema.json)
- [P1-C 体验研究记录 JSON Schema](contracts/p1c-ux-research-record.schema.json)
- [BodyAssetManifest JSON Schema](contracts/body-asset-manifest.schema.json)

机器契约与叙述文档冲突时，应先停止实现并走 DOC-00 的冲突处理流程；不得自动选择“更方便实现”的一方。

## 架构决策

- [ADR-0001：单仓库与运行时边界](decisions/ADR-0001-monorepo-and-runtime-boundaries.md)
- [ADR-0002：Agent 与安全边界](decisions/ADR-0002-agent-and-safety-boundary.md)
- [ADR-0003：规范身体位置](decisions/ADR-0003-canonical-body-location.md)
- [ADR-0004：iOS 3D 渲染边界](decisions/ADR-0004-ios-3d-rendering-boundary.md)
- [ADR-0005：确认事件与 Episode 事务边界](decisions/ADR-0005-confirmed-event-episode-transaction-boundary.md)
- [ADR-0006：iOS 未确认草稿加密与同步边界](decisions/ADR-0006-ios-offline-draft-encryption-boundary.md)
- [ADR-0007：iOS typed signal intake 边界](decisions/ADR-0007-ios-typed-signal-intake-boundary.md)
- [ADR-0008：iOS 结构化录入服务端适配边界](decisions/ADR-0008-ios-signal-intake-server-adapter-boundary.md)
- [ADR-0009：参考项目采用与原生重写边界](decisions/ADR-0009-reference-project-adoption-and-native-boundary.md)
- [ADR-0010：P1F Application Service 内部交接边界](decisions/ADR-0010-p1f-application-handoff-boundary.md)
- [ADR-0011：P1G P1F → PydanticAI Agent 内部交接边界](decisions/ADR-0011-p1g-agent-handoff-boundary.md)
- [ADR-0012：P1H Agent Turn Application 内部多轮边界](decisions/ADR-0012-p1h-agent-turn-application-boundary.md)
- [ADR-0013：P2A Session/Turn 类型化投影边界](decisions/ADR-0013-p2a-session-turn-projection-boundary.md)
- [ADR-0014：P2B ConfirmationIntent 应用边界](decisions/ADR-0014-p2b-confirmation-intent-application-boundary.md)
- [ADR-0015：P2C 第二次确认与终态投影应用边界](decisions/ADR-0015-p2c-approval-decision-application-boundary.md)
- [ADR-0016：P2D 确认事务写集与提交读回契约边界](decisions/ADR-0016-p2d-confirmation-transaction-contract-boundary.md)
- [ADR-0017：P1-C 体验研究记录边界](decisions/ADR-0017-p1c-ux-research-instrumentation-boundary.md)
- [ADR-0018：BodyAssetManifest 与 3D 运行时门禁边界](decisions/ADR-0018-body-asset-manifest-runtime-gate.md)
- [ADR-0019：情境化行动建议与沟通摘要边界](decisions/ADR-0019-contextual-guidance-and-communication-summary.md)
- [CONFLICT-001：R2 普通 Agent 门禁语义](decisions/CONFLICT-001-r2-ordinary-agent-gate.md)（开放；当前按更保守的 R3-only 行为执行）
- [CONFLICT-002：普通问题选择权与 PydanticAI 职责](decisions/CONFLICT-002-question-selection-authority.md)（开放；当前不实施 P1I，并按保守临时行为由 Application Service 决定未来普通题选择权）
- [CONFLICT-003：P1D 感觉修订与安全失效边界](decisions/CONFLICT-003-sensation-revision-safety-invalidation.md)（开放；当前普通路径修订必须重新安全检查，高风险安全行动中的直接本地修订保持拒绝）
- [CONFLICT-004：P1D 非感觉事实修订与安全行动保留](decisions/CONFLICT-004-p1d-non-sensation-revision-safety-boundary.md)（开放；高风险位置及其他事实修订尚未形成 retained-action/revision 闭环，受影响能力不得外部发布）

FRAME-01 是参考采用和模块落地真源；它不替代产品、数据、安全、隐私、契约或 ADR。上游项目只在 OSS-01 与 FRAME-01 明确的分类、版本和禁止清单内使用。

## 规范模板

- [ADR 模板](templates/ADR_TEMPLATE.md)
- [Feature Spec 模板](templates/FEATURE_SPEC_TEMPLATE.md)
- [测试计划模板](templates/TEST_PLAN_TEMPLATE.md)

## 当前需要签字或实证的事项

| 决策/验证 | 完成门禁 | 责任角色 |
|---|---|---|
| 具体 LLM provider、地区与数据保留 | 真实 Provider 接入前 | 隐私 + 安全 + AI 工程 |
| 红旗规则内容、组合逻辑与文案 | 内测前 | 临床安全负责人 |
| 默认/专业人体资产及区域本体 | 真实 3D 资产接入前 | 资产负责人 + 解剖审核人 + 法务 |
| iOS 最低版本与 RealityView/ARView 路径 | 技术样机后 | iOS 负责人 |
| 中国与目标上架地区的产品分类、备案和宣传边界 | 外部测试前 | 法务/合规 |
| 临床影子测试方案与样本量 | 受控灰度前 | 临床研究 + 统计 |

“待确认”不是放宽约束：在签字前应使用更保守行为、关闭相关能力或仅在内部原型中验证。

## 当前仍缺少的发布能力

| 优先级 | 缺口 | 关闭条件 | 当前保守行为 |
|---|---|---|---|
| P0 | [责任主体与外部边界](27_GATE_02_RESPONSIBILITY_AND_PRODUCT_BOUNDARY.md) | 实名产品/临床/隐私/安全/工程/QA 负责人签字；确认首发地区、最低 iOS、产品分类和宣传边界 | 仅内部原型，不外测、不宣传诊断能力 |
| P0 | 临床安全基线 | 完成红旗规则、行动文案、内容库、锁定 Golden Set、独立临床审核和 SafetyBaseline | 规则/内容未获批时关闭普通 AI 分析，保留固定安全入口 |
| P0 | 身份、同意与正式数据链 | OIDC/近期认证、Consent/撤回、正式数据库、事务/CAS/幂等/读回、审计、导出删除和迁移恢复通过 | 使用内存/假仓库，不接生产用户数据 |
| P0 | 真实 Agent Provider | 确认 Provider、地区/留存/传输、模型 profile、结构化输出、失败回退、成本与真实语义评测 | 仅 TestModel/FunctionModel，不发送真实健康请求 |
| P0 | 首发人体与客户端 | 获得默认模型作者链与商用/App Store 权利，完成真实文件哈希/签名、区域图、解剖审核、RealityKit loader、最低设备性能和无障碍测试 | 2D/列表为完整路径，3D 资产 gate 只验证合成 metadata |
| P0 | 真实端到端验证 | OpenAPI 同源客户端、iOS Keychain/Data Protection、离线恢复、真实设备 E2E、两类用户 30 秒研究和失败路径通过 | 不将本地单元测试视为可发布证据 |
| P0 | 远端版本门禁 | 将已建立的 `codex/initial-git-ci-baseline` 与 CI workflow 配置到远端；首次云端运行绿色，并把检查设为默认分支必需状态 | PR #1/#2 均在 required checks 成功后合并；合并后 CI 两个 job 成功，分支保护 API 读回成功 |
| P1 | MVP 产品闭环 | 今天页、复查/趋势、个人身体数字档案、报告/PDF/系统分享、提醒、访问记录形成正式数据闭环 | 保持在路线图 Phase 2/3，不提前开放 |
| P1 | 发布运营能力 | 监控告警、隐私遥测、SBOM、事故响应、回滚、影子测试和小流量门禁完成 | 不生成虚假 release-evidence，不进入外部发布 |
| P1 | 专业模型与外部资料 | 专业肌肉/关节模型、HealthKit/资料上传各自完成许可、同意、最小化和评测 | 首发后独立开关，默认关闭 |

2026-08-07 已关闭“回归套件可信性”和“本地版本控制基线”两个前置项：P2A 默认时钟由 fixture 冻结、显式过期边界保留，后端全量 189 个测试绿色；首个 `codex/` 分支、提交、依赖约束、仓库检查器和双作业 GitHub Actions workflow 已建立。远端门禁仍按上表保持 P0。
