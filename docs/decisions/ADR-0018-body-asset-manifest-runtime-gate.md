# ADR-0018：BodyAssetManifest 与 3D 运行时门禁边界

| 属性 | 值 |
|---|---|
| ADR ID | ADR-0018 |
| 状态 | Accepted for metadata-only prototype; asset/legal/anatomy/device approval required |
| 日期 | 2026-08-06 |
| 负责人 | 3D 资产 + iOS + QA + 隐私安全 |
| 关联功能 | FEAT-P1A-IOS-BODY-MAP-SHELL、FEAT-P1A-3D-ASSET-MANIFEST-SLICE |
| 机器契约 | `body-asset-manifest.schema.json` |
| 关联规范 | BODY-01、IOS-01、OSS-01、ADR-0003、ADR-0004 |

## 背景

产品需要默认中性 3D、专业肌肉/关节 3D、旋转/缩放、区域和精确点，但任何裸模型都无法证明权利、完整性、坐标、拓扑、碰撞网格、区域本体、迁移或最低设备性能。RehabMate 锁定提交中的 `assets/body.glb` 被其许可证单独排除，且不能满足本项目的资产/位置门禁。

在真实资产可用之前，需要先把“什么条件才允许运行时考虑一个资产”固定为可测试的文档和类型边界，同时保持 2D/列表完整可用。

## 决策驱动因素

- 资产权利、作者链、商业/App Store 分发和署名必须可审计；
- `BodyLocation` 必须绑定不可变 `asset_id/asset_version/topology_id` 和坐标/映射版本；
- 生产不得通过最近中心、`face.a`、世界坐标、数组下标或裸文件推断身体语义；
- 未知、撤回、签名未验证、解剖/性能未通过时必须 fail closed；
- 3D 失败不能阻断 2D、列表、P1D 和安全入口；
- 当前只能使用合成 fixture，不能把工程清单验证当作真实资产批准。

## 备选方案

### 方案 A：运行时直接加载 USDZ/GLB

优点是接线快。代价是权利、坐标、拓扑、区域映射、性能和撤回没有单一事实源；容易把上游 demo 资产和算法带入生产。拒绝。

### 方案 B：版本化 AssetManifest + fail-closed runtime gate

清单固定资产身份、来源、权利、哈希/签名状态、坐标、artifact 角色、LOD、映射、审核、性能和回退；只有交叉约束通过才返回运行时 metadata decision，文件签名/哈希仍由发布流水线实际验证。选择。

### 方案 C：只允许 2D，永不建立资产契约

安全性最高但不能验证产品明确的默认/专业 3D 方向，也无法为未来模型采购和迁移建立可审计接口。作为 3D 失败回退，不作为最终产品方向。

## 决策

1. 新增 `BodyAssetManifest` Schema 1.0，`additionalProperties=false`，清单版本不可变。
2. 清单必须包含资产 ID/版本/变体/拓扑、来源、权利、完整性、Canonical 坐标、artifact、LOD、映射、审核、性能、署名和回退字段。
3. `release_status=approved` 只有在商业/App Store 权利、非零清单摘要、签名状态、解剖审核和性能状态均通过时才可满足 metadata gate；`blocked/retired` 永不允许运行时加载。
4. 默认/专业 3D 的 approved 清单还必须同时引用必需的 render、独立 collision、region map、surface correspondence 与 camera preset artifact；collision 不得与 render 共用 URI 或文件摘要。candidate 可显式共用便于内部探针，但不能仅靠改写批准字段越过该结构门禁。
5. `BodyAssetRuntimeGate` 只做 typed metadata decision，不读取文件、不下载、不验证真实签名密钥、不创建 `BodyLocation`、Event、Consent 或 Agent 结果。
6. RealityKit loader 必须以 gate 结果为前置条件，并在发布流水线验证每个 artifact 的实际哈希/签名。`integrity.source_sha256` 是来源交付物的摘要，不得被解释为所有 bundle artifact 必须共用的哈希。
7. Bundle、Manifest、Swift 绑定常量和 USD custom metadata 的 asset/version/topology 必须由同一自动检查读回；资产容器仍须过 `usdchecker --arkit`、对齐、层级、三角数和稳定 mesh 集验证。
8. 任何默认/专业资产进入仓库或构建包前必须更新第三方清单、许可证证据、哈希、修改说明、AssetManifest registry 和设备/解剖验收证据。
9. `app_store_distribution=false` 的资产不得进入任何生产 archive；正式 App target 建立前必须拆分 internal-only resource target 或建立 archive denylist/产物扫描。
10. RehabMate Web/Three.js/GSAP、`body.glb`、`muscles.js`、最近中心、`face.a`、点击三态和世界坐标针点不在此 ADR 的可复用范围内。

## 后果

### 正面

- 资产、权利、位置语义和性能有同一版本化入口；
- 资产撤回和专业模型失败可稳定回退 2D/列表；
- 历史 `BodyLocation` 不会因模型升级被静默重写；
- iOS/后端/QA 可以围绕同一 Schema 生成契约测试；
- 上游 demo 的视觉参考与生产运行时被清楚分离。

### 代价与风险

- 真实资产接入前要建立签名 registry、密钥轮换、文件哈希和迁移流水线；
- 需要资产、法务、解剖、QA、iOS 和无障碍协作；
- 精确点跨模型无法映射时必须保留区域级候选并请求用户复核；
- metadata gate 通过不代表真实文件和视觉质量通过，发布流程不能省略后续验证。

## 验证和退出条件

- `TEST-P1A-3D-ASSET-MANIFEST-SLICE` 的 13 个契约/安全/供应链场景通过；
- Schema 可由 Draft 2020-12 解析，代表性 candidate/approved/rejected fixture 通过/拒绝关系校验；
- Swift Core 与 iOS SDK 编译通过；未知字段、版本、清单状态和关键 artifact fail closed；
- 源码和构建包扫描没有 RehabMate 禁止资产/代码；
- 真实资产接入前，完成 REL-01 GATE-06 的作者链、签名、解剖、法务、设备和无障碍评审。

回滚：关闭 `P1A_ASSET_MANIFEST_GATE_PROTOTYPE` 或撤回清单；保持 2D/列表和安全入口，不删除历史位置引用。

## 追踪

| 对象 | ID/链接 |
|---|---|
| 需求 | PRD-F03A、PRD-F03B、NFR-PERF-001～003、NFR-A11Y-001 |
| 数据/接口 | [`body-asset-manifest.schema.json`](../contracts/body-asset-manifest.schema.json)、`BodyLocation.model_asset` |
| 功能/测试 | [FEAT-P1A-3D-ASSET-MANIFEST-SLICE](../18_IMPLEMENTED_PROTOTYPE_BASELINE.md)、[TEST-P1A-3D-ASSET-MANIFEST-SLICE](../18_IMPLEMENTED_PROTOTYPE_BASELINE.md) |
| 风险 | OSS-01、BODY-01、SAFE-INV-09、REL-01 GATE-06 |

## 变更记录

| 日期 | 变更 | 作者/批准人 |
|---|---|---|
| 2026-08-13 | 将 approved 3D 的独立 collision/region map/surface correspondence/camera preset、非零清单摘要、跨层身份读回与生产 archive 排除写入不可绕过门禁 | Codex / 待资产、法务、iOS、QA 评审 |
| 2026-08-06 | 建立 metadata-only AssetManifest 与运行时门禁边界 | Codex / 待资产、法务、解剖、iOS、QA 审核 |
