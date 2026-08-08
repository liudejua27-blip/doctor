# BASELINE-01 已实现样机基线

| 属性 | 值 |
|---|---|
| 文档 ID | BASELINE-01 |
| 版本 | 1.1.0 |
| 状态 | Current prototype snapshot |
| 快照日期 | 2026-08-08 |
| 作用 | 取代已完成切片的独立 Feature Spec 与 Test Plan；记录现有代码边界、契约、测试和未证明范围 |
| 上位真源 | PROD-01、ARCH-01、IOS-01、AGENT-01、DATA-01、API-01、BODY-01、SAFE-01、PRIV-01、QA-01 |

## 1. 使用方式

本文只回答“当前样机代码已经证明了什么”。产品需求、长期架构、字段语义、安全规则、隐私权限、发布门禁仍以对应核心规范为准；机器序列化以 `docs/contracts/` 为准；不可逆决策以 `docs/decisions/` 为准。

本文不能用于宣称 App 已完成、生产可用、临床安全、诊断有效、真实人体资产获批或真实 Provider 合规。

## 2. 当前实现快照

| 能力组 | 当前实现 | 已证明 | 未证明/保持关闭 |
|---|---|---|---|
| iOS 身体位置 | SwiftUI 全身 2D/列表、RealityKit 原生 prototype loader、2D/3D 状态、规范 `BodyLocation`、2D 回退、候选资产哈希清单、RehabMate 行为等价的 Zone/Pin/摘要状态、窄屏系统 Sheet 与上限/回退反馈 | 位置身份不随视图改变；禁止保存世界坐标；全身区域目录、命中、列表路径、原生 iOS 编译有证据；V2 Core 状态规则有单元测试 | 生产资产权利、真机命中、视觉/解剖准确性、生产性能、真机 Sheet/VoiceOver/Dynamic Type |
| 3D 资产门禁 | `BodyAssetManifest` Schema、Swift metadata gate 和内部候选模型描述 | 未批准、未知、blocked/retired 资产 fail closed；内部 prototype 可显式展示候选状态 | 真实生产文件哈希/签名、商用权、App Store 分发、解剖与性能 |
| 结构化录入 | `SignalIntakeDraft`、八类事实、来源/确认状态、感觉—marker 关系 | 未确认事实不会静默升级；显式未知和安全回退存在 | 真实用户 30 秒完成率、公开 API 联调、生产持久化 |
| 离线草稿 | CryptoKit/AES-GCM 端口、进程内密文仓和同步状态机 | 所有者隔离、篡改失败、幂等/冲突状态 | Keychain、Data Protection、文件 durability、后台同步、真机恢复 |
| 安全与 Agent | 确定性 SafetyEngine、PydanticAI typed candidate、PolicyValidator、授权只读上下文 | Safety 先于 Agent；LLM 不能降级、确认或正式写入 | 临床规则批准、真实 Provider、Golden Set、影子验证 |
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
| Markdown | 51 files、0 断链、0 尾随空白 | 只证明清理后的文档结构完整 |
| JSON Schema | 16 个可解析 | 只证明 Schema 结构有效 |
| OpenAPI | 1.1.0-draft、36 paths、111 schemas | 只证明草案可解析 |
| iOS Swift | 64 tests、0 failures；iOS `BodyCompanionIOS` 与 prototype generic build 绿色 | 只证明 Core/原生适配器可编译和合成样机 |
| 后端 Python | 189 tests、0 failures；P2A 聚焦 19 tests | 受控时钟回归已修复；只证明合成/内存样机 |
| Git/CI | `codex/initial-git-ci-baseline` 受保护默认分支合并提交 `2bb8e8a`；本轮复刻切片提交 `6f232b4`；此前基线 `0fa2a17`；双作业 workflow；Python 3.11 constraints | 本地可追溯基线、GitHub Actions、分支保护、PR #4 及合并后 CI 均已验证 |

## 6. 删除登记

2026-08-07 经用户明确要求，以下过程性文档在本文件完成归并后物理删除：

- `docs/features/` 下 16 份已完成样机 Feature Spec；
- `docs/plans/` 下 16 份与现有测试代码、QA-01 重复的 Test Plan；
- EVIDENCE-01 中 E-001～E-133 的逐轮流水账，改为当前快照与关键失败证据；
- REL-01 中逐切片开发历史，改为只保留当前交付门禁。

ADR、核心规范、机器契约、许可证/资产边界和实际测试代码没有删除。

## 7. 下一步

按 REL-01 顺序执行：先把现有 workflow 推到远端并建立必需状态检查/保护分支，再关闭责任/地区、临床安全、Provider、身份同意数据库、真实资产与客户端、公开纵向联调、真实用户/设备验证门禁。

当前实施入口为 [FEAT-BODY-MAP-V1](19_BODY_MAP_PRODUCTION_SLICE.md)、[FEAT-BODY-MAP-V2](22_REHABMATE_NATIVE_PARITY.md)、[TEST-BODY-MAP-V1](20_BODY_MAP_TEST_PLAN.md)、[TEST-BODY-MAP-V2](23_REHABMATE_NATIVE_PARITY_TEST_PLAN.md) 和 [BODY-ASSET-01](21_BODY_ASSET_PROVENANCE.md)。
