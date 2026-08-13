# BODY-ASSET-01：候选人体显示资产来源与发布门禁

状态：Active candidate record（不等于生产批准）
关联：FEAT-BODY-MAP-V1、FEAT-BODY-MAP-V2、TEST-BODY-MAP-V1、TEST-BODY-MAP-V2、ADR-0018、OSS-01、REL-01

## 1. 目的

本记录固定首个可运行的 3D 候选资产，避免“为了让界面显示模型”而把 RehabMate 的 `body.glb`、Web 运行时或未审计人体网格带入 App。候选资产是本项目用 Blender 脚本生成的分区更清晰、中性、非解剖展示模型，只能表达用户选择位置的视觉载体，不能表达疼痛来源、组织损伤、疾病或医学定位。

机器可读清单：[`body-neutral-procedural-v1.manifest.json`](assets/body-neutral-procedural-v1.manifest.json)。

## 2. 文件与哈希

| 项目 | 值 |
|---|---|
| Bundle 文件 | `ios/BodyCompanion/Sources/BodyCompanionIOS/Resources/BodyNeutralPrototype.usdz` |
| 生成脚本 | `tools/generate_neutral_body_asset.py` |
| 资产 ID / 版本 | `body-neutral-procedural-v1` / `1.2.0` |
| 生成方式 | 项目脚本直接按 Y-up/米制坐标创建球体、圆柱、倒角方块，导出 USDA 后由 `usdzip --arkitAsset` 生成 USDZ；未导入第三方网格 |
| 固定工具链 | Blender 5.1.2；Apple USD Tools 0.25.2；工具链变更必须升候选版本并重跑全部资产门禁 |
| SHA-256 | `3120c9de64d26c98aed073776107e154c0450b52d7e289aa61fa6dc63fc45d5f` |
| 坐标约定 | RealityKit Y-up、右手、米制；脚底中点为根原点语义 |
| 拓扑快照 | 24,020 个三角面（1.2.0 候选快照，仍需设备/碰撞复核） |

1.2.0 的哈希由 2026-08-13 同一生成脚本连续三次输出一致后记录。脚本不再用通用 ZIP 库重打包 USDZ，而是调用 OpenUSD 的 `usdzip --arkitAsset` 保持文件 64-byte alignment，仅在原位归一化 ZIP 时间字段；Blender/OpenUSD 工具链升级仍可能改变二进制输出。任何重新生成、导出、压缩或工具链升级都必须重新哈希、同步清单并重新评审。

当前 Bundle 的可复现深读回命令为 `python3 scripts/check_body_asset_release.py`。它在 macOS CI 中同时验证 ARKit 容器/64-byte 对齐、哈希、manifest/Swift/USD 身份、Y-up/米制/identity root、完整 Mesh 名称、冻结身高/地面与三角数。该命令通过只是 candidate 完整性证据，不是生产批准。

## 3. 权利与禁用边界

- 当前 `release_status=candidate`、签名 `unverified`、解剖审核 `pending`、性能 `pending`。1.2.0 修复坐标/容器契约、增加 `body_lower_back`，并把 `body_*` 写为实际 Mesh prim 名称；它仍是分段几何，不是连续高质量人体，也不改变其非医学语义。
- 当前清单将商业使用和 App Store 分发设为 `false`；`example.invalid` 仅表示尚未建立可验证的公共权利凭证，不是资产下载来源。
- 该资产只由内部 prototype flag 加载；生产调用默认要求 `BodyAssetRuntimeGate` 返回 `metadataEligible`，candidate 必须回退 2D/列表。
- 不得把此候选模型描述为“标准人体”“肌肉模型”或“专业模型”；专业肌肉/关节模型仍是独立采购/委托/审核任务。
- 不得以重命名、重新导出、转换格式或复制场景来绕过 RehabMate 资产禁用规则。

## 4. 进入生产所需证据

只有以下证据全部落盘，才可以把该资产或其替代品的 `release_status` 改为 `approved`：

1. 可核验的作者链、许可证全文、商业/App Store 分发和修改/衍生权利；
2. 项目法务记录、归属文本和发布包中的 attribution 位置；
3. 解剖/视觉审查明确“仅显示位置”语义，且不暗示临床定位；
4. 独立 region map、碰撞策略、前后左右视角和本体迁移测试；
5. 目标 iPhone 真机的冷启动、命中 P95、帧率、内存、VoiceOver 和降级证据；
6. 签名清单、文件哈希读回、撤回/回滚和 2D/列表 fail-closed 验收。

未完成上述证据时，`GATE-06`、`GATE-07` 和全球发布门禁仍保持未关闭。

## 5. 2026-08-08 设备与候选资产审核读回

历史设备记录见 [EVIDENCE-DEVICE-01](24_DEVICE_VALIDATION_EVIDENCE.md)，当前 1.2.0 命令收据见 [EVIDENCE-01](16_EXECUTION_EVIDENCE.md)。USDZ 容器可由 `usdcat`/`usdchecker --arkit` 读取，ZIP 对齐、Bundle SHA-256 与清单一致；这只证明文件结构和完整性，不证明 RealityKit 视觉、碰撞、解剖或设备性能。仓库已有内部 Simulator Host，但没有本轮签名真机执行证据，因此真机性能、VoiceOver、Dynamic Type、Reduce Motion 和黄金点命中均保持未测。

该次 1.1.0 审核发现 USD 根层有 `xformOp:rotateXYZ = (-90, 0, 0)`，清单却声明 identity canonical transform；模型缺少 `body_lower_back` 分段实体，且当时 loader 尚未实现独立 CollisionGroup 与 triangle/barycentric 命中证据。1.2.0 在资产侧修复根变换与 lower_back，iOS 18 代码已将 `TriangleHit.uv` 转为三分量 barycentric；固定工具链下的 `usdchecker --arkit`、读回层级和连续三次生成 SHA 验证已通过。当前仍无独立 CollisionGroup/碰撞产物、签名 region map 与 RealityKit 真机 faceIndex 黄金集；帧率/内存与无障碍也仍须由 iOS/QA/审核共同关闭，不能通过改写 `release_status` 绕过。
