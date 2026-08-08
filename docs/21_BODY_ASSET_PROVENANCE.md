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
| 资产 ID / 版本 | `body-neutral-procedural-v1` / `1.1.0` |
| 生成方式 | 项目脚本创建球体、圆柱、倒角方块并导出 USDZ；未导入第三方网格 |
| SHA-256 | `299d896513a8c7ef7e5d584495c9bc5ba78505da5f20c9dc2b50e0ef9d7e5668` |
| 坐标约定 | RealityKit Y-up、右手、米制；脚底中点为根原点语义 |
| 拓扑快照 | 22,804 个三角面（1.1.0 候选快照，仍需设备/碰撞复核） |

哈希由 `shasum -a 256` 在 2026-08-08 生成；脚本只固定 USDZ 容器的归档元数据，Blender 二进制导出的内容仍可能在重新生成时变化。任何重新生成、导出或压缩文件都必须重新哈希、同步清单并重新评审。

## 3. 权利与禁用边界

- 当前 `release_status=candidate`、签名 `unverified`、解剖审核 `pending`、性能 `pending`。1.1.0 只增加独立显示分区和表面平滑度，不改变其非医学语义。
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
