# EVIDENCE-DEVICE-01：iOS 真机、无障碍、3D 性能与候选资产审核

| 属性 | 值 |
|---|---|
| 文档 ID | EVIDENCE-DEVICE-01 |
| 版本 | 1.0.0 |
| 状态 | Attempted / blocked pending authorized physical iPhone and signed app target |
| 执行日期 | 2026-08-08 |
| 对应 Git | `d7853a7932e0109d5563cfc80e44cd0e485c8fac`（默认分支快照） |
| 适用测试计划 | [TEST-BODY-MAP-V2](23_REHABMATE_NATIVE_PARITY_TEST_PLAN.md)、[TEST-BODY-MAP-V1](20_BODY_MAP_TEST_PLAN.md) |
| 资产记录 | [BODY-ASSET-01](21_BODY_ASSET_PROVENANCE.md)、[ADR-0018](decisions/ADR-0018-body-asset-manifest-runtime-gate.md) |

## 1. 结论先行

本次无法形成“真机通过”证据，原因是：

1. Xcode 26.6 可用，但仓库没有可签名的 `.xcodeproj`/`.xcworkspace`、iOS App scheme、Bundle ID 或 entitlements；当前只有 Swift Package，`BodyCompanionIOS` 是 library target，`BodyCompanionPrototype` 在 macOS 下才提供可运行的 executable 壳。
2. `xcrun xctrace list devices` 与 `xcrun devicectl list devices` 均显示已登记的两部 iPhone 为 Offline/unavailable；没有已连接且已信任的设备可安装和运行。
3. 所有 iOS Simulator 均为 Shutdown。本记录不把 Simulator、泛 iOS SDK 编译或 Core 单元测试外推为真机证据。

因此，Sheet、VoiceOver、Dynamic Type、Reduce Motion、3D 性能、RealityKit 碰撞命中和候选资产的生产批准均保持 **Pending/Blocked**。2D、部位列表和安全入口继续是唯一可外推的可用路径；候选 USDZ 继续为 `candidate`，不得发布。

## 2. 环境与可复现检查

| 检查 | 结果 | 证据范围 |
|---|---|---|
| `xcode-select -p` / `xcodebuild -version` | `/Applications/Xcode.app/Contents/Developer`；Xcode 26.6 (17F113) | 工具链可用，不代表签名或安装可用 |
| XcodeBuildMCP `session_show_defaults` | project/workspace/scheme/device/simulator 均未设置 | 会话没有可运行 App 目标 |
| XcodeBuildMCP `discover_projs` | `Found 0 projects and 0 workspaces` | 仓库无 Xcode project/workspace |
| `xcrun xctrace list devices` | `iPhone13pro`、`yiyi的iPhone` 均在 Devices Offline | 真机不可用 |
| `xcrun devicectl list devices` | 两台设备均 `unavailable` | 真机不可用的独立读回 |
| `xcrun simctl list devices available` | iOS 26.5 模拟器全部 `Shutdown` | 未运行 Simulator 测试 |
| Swift iPhoneOS build | `BodyCompanionIOS` target 成功 | 只证明 iOS SDK 编译 |
| Swift iPhoneSimulator build | `BodyCompanionIOS` target 成功 | 只证明 Simulator SDK 编译 |
| Swift Core tests | `64 tests, 0 failures` | 只证明状态/契约，不证明 UI/设备 |

运行时前置条件缺失时，不能使用临时 `swift run`、macOS prototype 或无签名的 library 产物替代 iOS App 安装测试。

## 3. 维度结果矩阵

| 维度 | 结果 | 已有静态/代码证据 | 真机关闭条件 |
|---|---|---|---|
| Sheet | **Blocked** | 紧凑宽度通过系统 `.sheet`、`.medium/.large` detents、drag indicator 和 `ScrollView` 承载编辑器；删除后状态会由模型清理 | 在 iPhone 上验证首次选择、再次选择、切换标记、删除、旋转和系统返回；确认 Sheet 不遮挡继续入口、焦点不丢失 |
| VoiceOver | **Blocked** | 2D 有部位列表等价路径；主要按钮有 label/hint；3D 仅提供整体语义说明并保留 2D/列表回退 | 开启 VoiceOver，从 Today → 记录 → 2D/列表 → Sheet 编辑 → 删除 → 继续全程完成；验证提示、计数、Slider、回退公告和导航顺序 |
| Dynamic Type | **Blocked** | 使用 `.body/.headline/.caption/.footnote` 等语义字体，编辑器放入 `ScrollView` | 最大可访问字号和横屏下不截断标题、标记摘要、提示、Slider 和按钮；确认 Sheet 可滚动且关键操作仍可达 |
| Reduce Motion | **Blocked** | 未发现 `withAnimation`、`.animation` 或持续旋转；视角切换代码是直接 `look(at:from:)` | 开启 Reduce Motion，重复 front/back/left/right/top、焦点和 Sheet 展开；确认无不必要动画、闪烁或自动旋转，手势仍可用 |
| 3D 性能 | **Blocked** | USDZ 约 606 KB、manifest LOD 三角面 22,804；代码在加载时同步 `ModelEntity.loadModel` 和 `generateCollisionShapes(recursive:)` | 最低支持 iPhone 冷启动、首次交互、连续旋转/缩放 5 分钟；采集冷启动、P95 命中、FPS、内存、热状态和崩溃 |
| 碰撞命中 | **Blocked** | 使用 `hitTest(.nearest, mask: .all)`；先识别 `marker_`，再向父链解析 `body_`；保存 root-local position/normal | 真机逐区域黄金点、边界点、遮挡点和已有 Marker 重叠点；验证命中延迟、误落点、Marker 优先级和 2D 回退 |
| 候选资产生产审核 | **Candidate only / blocked by gate** | ZIP 无损、`usdchecker` Success、SHA 与清单一致；清单仍为 candidate/unverified/anatomy pending/performance pending/商业与 App Store false | 作者链/许可证、法务署名、解剖语义、区域图/碰撞、坐标迁移、真机性能、无障碍、签名读回全部通过后才可申请 approved |

## 4. 本次静态审核发现

这些是生产门禁问题，不因“无法连接设备”而自动通过：

| ID | 严重度 | 发现 | 处理要求 |
|---|---|---|---|
| DEVICE-FINDING-001 | P0 | 没有可签名 iOS App target，无法安装、切换辅助功能设置或采集设备性能 | 建立正式 iOS App target、Bundle ID、Team/证书、entitlements 和可复现 scheme；完成后重跑本记录 |
| DEVICE-FINDING-002 | P1 | RealityKit 命中使用 `.all`，未实现 BODY-01 要求的人体/Marker/覆盖层 CollisionGroup 分离 | 增加独立 collision groups/masks，并用真机黄金点证明 Marker 优先与命中边界；不能以最近实体或 mask 全开替代 |
| DEVICE-FINDING-003 | P1 | `BodyHitEvidence` 当前没有从 `hitTest` 读取 triangle index/barycentric；候选代码只传 local position/normal | 建立受测的三角/重心或离线表面解析路径；若系统能力不足必须记录 fallback/候选确认，不得伪造精确点 |
| DEVICE-FINDING-004 | P1 | 候选 USDZ 没有 `body_lower_back` 实体；解析器会把躯干实体映射为 `body.torso.general`，不能证明下背区域命中 | 在资产 region map 中补齐或明确“躯干宽泛候选”，完成解剖/视觉审核和边界黄金集；禁止静默声称下背命中 |
| DEVICE-FINDING-005 | P1 | USD 根层包含 `xformOp:rotateXYZ = (-90, 0, 0)`，而 manifest `canonical_transform` 为 identity | 由资产负责人核对导出变换、根原点、前后/左右方向并更新不可变 manifest/迁移证据；真机命中前不得批准 |
| DEVICE-FINDING-006 | P1 | manifest `performance.status=pending` 且冷启动/P95/FPS/内存均为 0；代码没有 FPS/内存/signpost 采集 | 在目标 iPhone 上建立不含健康正文的性能采集和阈值评审；未测量不能改为 passed |
| DEVICE-FINDING-007 | P2 | `MarkEditor` 的 Slider 只有 accessibility value，没有明确的稳定 label；固定 520pt 2D 画布、两行摘要限制在大字号下有截断风险 | 真机 VoiceOver/Dynamic Type 验证；必要时补 label、取消摘要硬截断并保留部位列表等价路径 |

## 5. 候选资产审核读回

- Bundle：`ios/BodyCompanion/Sources/BodyCompanionIOS/Resources/BodyNeutralPrototype.usdz`
- 文件大小：606,024 bytes；USDZ 内含 `BodyNeutralPrototype.usdc` 与 `textures/color_0C0C0C.exr`，均通过 `unzip -t`。
- `usdchecker`：`Validation Result ... Success!`。
- SHA-256：`299d896513a8c7ef7e5d584495c9bc5ba78505da5f20c9dc2b50e0ef9d7e5668`，与 `docs/assets/body-neutral-procedural-v1.manifest.json` 的 source/render/collision artifact 一致。
- USD 树可读，包含 `body_root` 与 29 个分段实体（`body_*` Xform 共 30 个）；这只是文件结构证据，不是解剖质量、RealityKit 视觉、碰撞或设备性能证据。
- manifest 的 `release_status=candidate`、`signature_status=unverified`、`rights.commercial_use=false`、`rights.app_store_distribution=false`、`review.anatomy_status=pending`、`performance.status=pending` 必须保持不变。

## 6. 设备恢复后的复测顺序

1. 用户连接并解锁 iPhone，点击“信任”，确认 `xctrace` 与 `devicectl` 状态为 available/connected。
2. 在 Xcode 中提供正式 iOS App target、scheme、Bundle ID、Team、签名和 Debug/Release 配置；把 Swift Package 的 `BodyCompanionIOS` 作为依赖，不把 macOS executable 当作 iOS 壳。
3. 先跑 2D/列表和 Sheet 的 VoiceOver、Dynamic Type、Reduce Motion；失败时不得进入 3D 资产批准。
4. 在候选开关下运行 3D，采集冷启动、FPS、P95 命中、内存、热状态、崩溃和所有回退；不记录原始健康对话。
5. 执行碰撞黄金集：每个可映射区域的内部点、边界点、遮挡点、Marker 重叠点、前后/左右视角和取消/重试；确认结果只生成未确认位置草稿。
6. 由资产、解剖/视觉、无障碍、iOS、QA、法务分别签字后，才允许更新 manifest 的批准字段和发布门禁。

## 7. 发布决定

本轮决定：**不批准生产 3D，不声称真机通过，不关闭 GATE-06/GATE-07/GATE-08。** 在设备和正式 App target 到位前，生产路径保持 2D/列表 fail-closed；候选资产和 3D loader 仅限内部 prototype flag。
