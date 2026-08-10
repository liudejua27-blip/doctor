# BASELINE-01 已实现样机基线

| 属性 | 值 |
|---|---|
| 文档 ID | BASELINE-01 |
| 版本 | 1.12.9 |
| 状态 | Current prototype snapshot |
| 快照日期 | 2026-08-10 |
| 作用 | 取代已完成切片的独立 Feature Spec 与 Test Plan；记录现有代码边界、契约、测试和未证明范围 |
| 上位真源 | PROD-01、ARCH-01、IOS-01、AGENT-01、DATA-01、API-01、BODY-01、SAFE-01、PRIV-01、QA-01 |

## 1. 使用方式

> **2026-08-10 当前 H015 收据。** `4cc46e2` / run `31350639359` 的 Backend/contracts、Swift 94/94、iPhoneOS SDK build、Host boundary 与 internal Host smoke 全部成功（iPhone 16 / iOS Simulator 18.5 / Xcode 16.4）。本地 iPhone 17 Pro / iOS 26.5 targeted H015 1/0/0（77.241s）、多位置 unknown 1/0/0（49.167s），完整 internal Host script exit 0（446.330s）。仅内部 Simulator；不证明真机或完整无障碍、性能、资产和生产门禁。

本文只回答“当前样机代码已经证明了什么”。产品需求、长期架构、字段语义、安全规则、隐私权限、发布门禁仍以对应核心规范为准；机器序列化以 `docs/contracts/` 为准；不可逆决策以 `docs/decisions/` 为准。

> **2026-08-10 remote compatibility receipt.** SHA `9b6e10a` / run `31348638741` 在远端 Xcode 16.4 的 UI test 编译阶段失败：`XCTIssue.isFailure` 在该 XCTest SDK 不可用，0 个 UI test 执行；Backend/contracts、Swift、SDK 与 Host boundary 均已通过。失败诊断 artifact 已上传但没有测试附件；当前兼容性修复改用跨版本 `XCTIssue.type == .assertionFailure`，待提交、推送与重试。该事件不改变 Simulator-only、无障碍、真机或生产门禁边界。

本文不能用于宣称 App 已完成、生产可用、临床安全、诊断有效、真实人体资产获批或真实 Provider 合规。

## 2. 当前实现快照

| 能力组 | 当前实现 | 已证明 | 未证明/保持关闭 |
|---|---|---|---|
| iOS 身体位置与 P0 体验壳 | SwiftUI 全身 2D/列表、本地中文/英文文字部位 Sheet、RealityKit 原生 prototype loader、2D/3D 状态、规范 `BodyLocation`、2D 回退、候选资产哈希清单、单次选择的 Zone/Pin/位置摘要状态、窄屏系统 Sheet 与上限/回退反馈；今天/AI 身体助手/地图/结构化描述的明亮中文原型壳；进程内草稿的继续/明确放弃后新建入口；受版本控制的 `BodyCompanionInternal` Simulator App Host | 位置身份不随视图改变；文字目录固定产生宽泛 `Zone + Area + body_part_search`，即使当前图形模式为 Pin 也不伪造 Point/3D anchor；Zone + Pin 共享 20 个位置总上限，超限明确拒绝且不截断 typed draft；地图只写位置、不覆盖结构化感觉/程度/因素；完整感觉目录由同一 32 个稳定 code 构成，首屏 10 项、展开后 22 项；扩展感觉、`other` 与 unknown 只写未确认且显式关联的位置。`0105cd7` 的 94 项 Core、iPhoneOS build、静态 Host 检查与本地 12 项 Host UI flow 已覆盖普通状态的感觉修订失效和高风险状态拒绝。`4cc46e2` 进一步固定跨版本 per-location unknown selector、文字选项中心点击和 bounded scroll；run `31350639359` 的远端 Host smoke 全部成功，本地 H015、多位置 unknown 与完整 Host script 也通过。Host 默认禁用候选 3D、网络/Provider、权限、持久化和遥测 | 生产资产权利、真机命中、CollisionGroup/triangle 证据、视觉/解剖准确性、生产性能、真机 Sheet/VoiceOver/Dynamic Type/Reduce Motion；P0 不等于 AI 对话、情境资料读取、行动建议、正式档案或跨进程草稿恢复已实现；CONFLICT-004 的高风险非感觉事实修订仍阻断外部发布 |
| 3D 资产门禁 | `BodyAssetManifest` Schema、Swift metadata gate 和内部候选模型描述 | 未批准、未知、blocked/retired 资产 fail closed；内部 prototype 可显式展示候选状态；USDZ 容器和哈希读回通过 | 真实生产文件哈希/签名、商用权、App Store 分发、解剖与性能、下背实体/根变换/碰撞复核 |
| 结构化录入 | `SignalIntakeDraft`、八类事实、来源/确认状态、感觉—marker 关系；多位置时新增感觉必须显式选择 Marker；首屏常用 10 项与从同一枚举派生的扩展 22 项 | 未确认事实不会静默升级；新增位置不会复制既有感觉；空、重复或非活动 Marker 关联被拒绝；单位置/多位置 unknown 语义不重复；对 `not_run`/`unavailable`/`no_rule_triggered` 的语义感觉修订使旧本地 safety、普通 Agent 与审批资格失效，R0/R1/R2/`undetermined`/`safety_action` 直接修订拒绝 | 真实用户 30 秒完成率、公开 API 联调、生产持久化；服务端 retained action/revision 尚未完成，CONFLICT-004 仍阻断高风险非感觉事实修订 |
| 离线草稿 | CryptoKit/AES-GCM 端口、进程内密文仓和同步状态机；P4 1.1 未确认感觉保留 code/可选标签/显式位置关联 | 所有者隔离、篡改失败、幂等/冲突状态；重复位置 ID、悬空感觉关联和旧 code-only 1.0 恢复被拒绝 | Keychain、Data Protection、文件 durability、后台同步、真机恢复 |
| 安全与 Agent | 确定性 SafetyEngine、PydanticAI typed candidate、PolicyValidator、授权只读上下文 | Safety 先于 Agent；R2 只进入固定专业评估准备，普通 Agent 仅完整、支持、无未解决安全且 `ordinary_agent_allowed=true` 的 R3；LLM 不能降级、确认或正式写入 | 临床规则批准、真实 Provider、Golden Set、影子验证 |
| 确认链 | typed Session/Turn、ConfirmationIntent、approve/deny、事务 write-set/read-back 原型 | revision、前驱、摘要、幂等、全有/全无关系在内存/fake repository 中可测 | OIDC、Consent、正式数据库、分布式锁、审计、公开 API |
| 研究记录 | 默认关闭的 metadata-only 研究记录器 | 不采集健康正文、身份或音视频 | 真实参与者研究、伦理/隐私批准、可用性结论 |

## 3. 历史切片 ID 归并

以下 ID 仍可用于解释现有类名、测试名和 ADR 背景，但不再各自维护独立文档：

| 历史切片 | 归并后的长期真源 |
|---|---|
| `FEAT-P1A-*` | IOS-01、BODY-01、ADR-0003/0004/0018、资产 Schema |
| `FEAT-P1B-*`、`FEAT-P1E-*`、`FEAT-P1F-*`、`FEAT-P1G-*`、`FEAT-P1H-*` | ARCH-01、AGENT-01、SAFE-01、PRIV-01、ADR-0002/0008/0010/0011/0012 |
| `FEAT-P1C-*` | UX-01、QA-01、PRIV-01、ADR-0017 |
| `FEAT-P1D-*`、`FEAT-P4-*` | IOS-01、DATA-01、PRIV-01、ADR-0006/0007 |
| `FEAT-P2-*`、`FEAT-P2A-*`、`FEAT-P2B-*`、`FEAT-P2C-*`、`FEAT-P2D-*` | DATA-01、API-01、SAFE-01、ADR-0005/0013/0014/0015/0016 |
| `FEAT-P3-*` | AGENT-01、PRIV-01、`agent-context.schema.json` |

对应 `TEST-*` 计划已归并到 QA-01 的测试矩阵和实际测试代码。原 `OPEN-P1*`、`OPEN-P2*`、`OPEN-P3*`、`OPEN-P4*` 过程项不再单独维护；尚未关闭的内容已去重为 REL-01 的当前发布门禁。

## 4. 当前机器契约

保留的 16 个 JSON Schema 与 OpenAPI 是跨端兼容真源，包括身体事件/位置、Agent Turn/授权上下文、iOS 草稿/录入、内部 handoff/确认事务、研究元数据和资产清单。删除历史切片文档不表示这些契约被废弃；删除或修改契约必须独立执行兼容性评审。

## 5. 当前验证状态

| 检查 | 当前结果 | 解释 |
|---|---|---|
| Markdown | 63 files、399 个已检查链接、0 尾随空白 | 临时测试缓存已排除；只证明清理后的文档结构完整 |
| JSON Schema | 16 个可解析 | 只证明 Schema 结构有效 |
| OpenAPI | 1.1.0-draft、36 paths、111 schemas | 只证明草案可解析 |
| iOS Swift | `4cc46e2`：本地 Swift Core 94/94、iOS SDK build、`check_internal_ios_host.py` 与 iPhone 17 Pro / iOS 26.5 targeted H015 1/0/0、多位置 unknown 1/0/0、full Host exit 0；远端 run `31350639359` 在 iPhone 16 / iOS Simulator 18.5 通过 Swift、SDK、Host boundary 与 internal Host smoke。历史失败保留用于回溯 | 证明当前内部 Simulator Host、跨版本 selector/scroll 和既有 94 项 Core 回归；不能替代真机 UI、完整 Dynamic Type、VoiceOver、深色/高对比度、Reduce Motion 或临床验收 |
| 后端 Python | 194 tests、0 failures；P2A 聚焦 19 tests | 受控时钟回归已修复；只证明合成/内存样机 |
| Git/CI | 当前分支 `codex/body-signal-intake-boundaries`、提交 `4cc46e2`；双作业 workflow；Python 3.11 constraints | 远端 run `31350639359` 全绿，本地 targeted/full 收据通过；历史失败 run 保留。任何结果均不等于真机或发布验收 |

## 6. 删除登记

2026-08-07 经用户明确要求，以下过程性文档在本文件完成归并后物理删除：

- `docs/features/` 下 16 份已完成样机 Feature Spec；
- `docs/plans/` 下 16 份与现有测试代码、QA-01 重复的 Test Plan；
- EVIDENCE-01 中 E-001～E-133 的逐轮流水账，改为当前快照与关键失败证据；
- REL-01 中逐切片开发历史，改为只保留当前交付门禁。

ADR、核心规范、机器契约、许可证/资产边界和实际测试代码没有删除。

## 7. 下一步

按 REL-01 顺序执行：`4cc46e2` 的内部 Host、远端 CI 和本地复测已完成；下一步仍是关闭责任/地区、临床安全、Provider、身份同意数据库、真实资产与客户端、公开纵向联调、真实用户/设备验证门禁。Simulator 收据不关闭 GATE-02/06/07/08。

当前实施入口为 [FEAT-BODY-MAP-V1](19_BODY_MAP_PRODUCTION_SLICE.md)、[FEAT-BODY-MAP-V2](22_REHABMATE_NATIVE_PARITY.md)、[TEST-BODY-MAP-V1](20_BODY_MAP_TEST_PLAN.md)、[TEST-BODY-MAP-V2](23_REHABMATE_NATIVE_PARITY_TEST_PLAN.md) 和 [BODY-ASSET-01](21_BODY_ASSET_PROVENANCE.md)。
