# EVIDENCE-DEVICE-01：iOS 真机、无障碍、3D 性能与候选资产审核

| 属性 | 值 |
|---|---|
| 文档 ID | EVIDENCE-DEVICE-01 |
| 版本 | 1.6.0 |
| 状态 | Current local and remote internal Simulator Host receipt passed; physical device and production 3D validation blocked |
| 执行日期 | 2026-08-08（设备尝试）；2026-08-09（Host 基线与远端 CI 重建）；2026-08-10（H015 收据）；2026-08-13（1.2.0 资产读回、看门狗竞态与候选 ready 复测） |
| 对应 Git | 历史提交与失败 run 保留；当前 `4cc46e2` / run `31350639359` 已成功完成 Backend/contracts、Swift 94/94、SDK build、Host boundary 与 internal Host smoke；本地 targeted/full 收据见下 |
| 适用测试计划 | [TEST-BODY-MAP-V2](23_REHABMATE_NATIVE_PARITY_TEST_PLAN.md)、[TEST-BODY-MAP-V1](20_BODY_MAP_TEST_PLAN.md) |
| 资产记录 | [BODY-ASSET-01](21_BODY_ASSET_PROVENANCE.md)、[ADR-0018](decisions/ADR-0018-body-asset-manifest-runtime-gate.md) |

> **2026-08-10 当前 H015 收据。** 最新远端 `4cc46e2` / run `31350639359` 全部成功：Backend/contracts、Swift 94/94、iPhoneOS SDK build、Host boundary 与 internal Host smoke；CI 目的地为 iPhone 16 / iOS Simulator 18.5 / Xcode 16.4。Smoke 成功日志不提供精确 XCTest 数。本地 iPhone 17 Pro / iOS 26.5 targeted H015 1/0/0（77.241s）、多位置 unknown 1/0/0（49.167s），完整 internal Host script exit 0（446.330s）。范围仅为内部 Simulator；真机、VoiceOver、完整 Dynamic Type、Reduce Motion、3D 性能/碰撞和资产审核仍 Pending/Blocked。

## 1. 结论先行

> **2026-08-10 remote compatibility receipt.** SHA `9b6e10a` / run `31348638741` 在远端 Xcode 16.4 的 UI test 编译阶段失败：`XCTIssue.isFailure` 在该 XCTest SDK 不可用，0 个 UI test 执行；Backend/contracts、Swift、SDK 与 Host boundary 均已通过。失败诊断 artifact 已上传但没有测试附件；当前兼容性修复改用跨版本 `XCTIssue.type == .assertionFailure`，待提交、推送与重试。该事件不改变 Simulator-only、无障碍、真机或生产门禁边界。

本次形成了受版本控制的内部 Simulator App Host 证据，但仍无法形成“真机通过”证据，原因是：

1. `5dddd83` 已提供 `BodyCompanionInternal.xcodeproj`、iOS App scheme 和 UI test target；它只使用 placeholder Bundle ID、禁用签名、无 entitlements，属于内部 Simulator Host，不能安装到真机。
2. `xcrun xctrace list devices` 与 `xcrun devicectl list devices` 均显示已登记的两部 iPhone 为 Offline/unavailable；没有已连接且已信任的设备可安装和运行。
3. `5dddd83` 的历史基线已在 booted iPhone 17 Pro / iOS 26.5 执行 7 项 UI smoke；远端 CI 在 iPhone 16 / iOS 18.5 成功运行同一脚本。两者都是 Simulator，不能外推为真机。
4. `79f1f36` 在本地同一 iPhone 17 Pro / iOS 26.5 完成 9 项 UI 测试；候选 probe 先观察当前 Scene 的 loader-entry，再实际出现 candidate-ready、3D 场景和列表入口。`ea85c68` 的远端 run `31301067572` 成功执行完整 Host suite；CI 日志确认 probe 成功，但不单独记录 ready/fallback 分支。它未点击人体，未测试碰撞、区域映射或性能。
5. `9fc54d4` 在同一 Simulator 完成 10 项 UI 流程与 87 项 Swift Core：共享文字入口可搜索本地中英文目录，选择后只创建待确认的宽泛 Area/Zone；无结果不写草稿；即使图形模式为 Pin 也不产生精确 Point。它同样不构成 VoiceOver、真实设备或网格命中证据。
6. `0105cd7` 在同一 Simulator 完成 12 项 UI 流程与 94 项 Swift Core：可展开“更多感觉（22 项）”并选中“麻木”，两位置时区分局部和全组 unknown；这些都只形成未确认的显式位置关联草稿。run `31307042209` 已在 iPhone 16 / iOS Simulator 18.5 成功重建 Swift 94、SDK build、Host boundary 与 internal Host smoke（Host smoke 09:55:37–10:04:42 UTC）。它同样不构成 VoiceOver、Dynamic Type、Reduce Motion、真实设备、碰撞、性能或资产审核证据。
7. `7d8bf59` 的 accessibility-size 结构收据、历史失败 run 与当前 `4cc46e2` 收据分开记录：`4cc46e2` / run `31350639359` 远端 Host smoke 成功；本地 iPhone 17 Pro / iOS 26.5 targeted H015、多位置 unknown 与 full Host script 也通过。范围仍不构成 VoiceOver、完整最大 Dynamic Type、深色/高对比度、Reduce Motion、真实设备、碰撞、性能或资产审核证据。

因此，Sheet、VoiceOver、Dynamic Type、Reduce Motion、3D 性能、RealityKit 碰撞命中和候选资产的生产批准均保持 **Pending/Blocked**。历史失败 run 仍保留；当前 `4cc46e2` / run `31350639359` 已在 iPhone 16 / iOS Simulator 18.5 通过 Backend/contracts、Swift 94/94、SDK build、Host boundary 与 Host smoke。本地 iPhone 17 Pro / iOS 26.5 targeted H015、多位置 unknown 与 full Host script 也通过。上述结果不关闭任何设备门禁；2D、部位列表和安全入口继续是唯一可外推的可用路径，候选 USDZ 继续为 `candidate`，不得发布。

## 2. 环境与可复现检查

| 检查 | 结果 | 证据范围 |
|---|---|---|
| `xcode-select -p` / `xcodebuild -version` | `/Applications/Xcode.app/Contents/Developer`；Xcode 26.6 (17F113) | 工具链可用，不代表签名或安装可用 |
| `xcodebuild -list -project ...BodyCompanionInternal.xcodeproj` | 列出 `BodyCompanionInternal`、`BodyCompanionInternalUITests`、`DebugInternal`/`ReleaseInternal` 与共享 scheme | 受版本控制的 native Host 可由 Xcode 发现；不是签名/真机证据 |
| `xcrun xctrace list devices` | `iPhone13pro`、`yiyi的iPhone` 均在 Devices Offline | 真机不可用 |
| `xcrun devicectl list devices` | 两台设备均 `unavailable` | 真机不可用的独立读回 |
| 本地 `xcrun simctl` / `xcodebuild test` | iPhone 17 Pro / iOS 26.5 / UDID `68F37251-71BE-4F42-9849-62D61BFFE7C3` booted；7 passed, 0 failures | 内部 Simulator P0 UI smoke，不是设备验证 |
| 本地候选 3D 专用 probe (`79f1f36`) | 同一 iPhone 17 Pro / iOS 26.5；9 passed, 0 failures；先出现 `body-map.candidate-3d-load-attempted`，随后出现 `body-map.candidate-3d-ready`、3D Scene 与列表入口 | 只证明当前 Simulator Scene 进入 loader 入口并完成一次内部候选加载生命周期；不证明模型质量、网格命中、性能或真机 |
| 本地文字部位切片 (`9fc54d4`) | 同一 iPhone 17 Pro / iOS 26.5；10 passed, 0 failures；2D 中搜索“膝”选择“左膝附近”，无结果不写草稿，候选 ready-or-fallback 终态与默认回退均保留共享文字入口 | 只证明 Simulator 内本地目录与 Area-only 位置契约；不证明 VoiceOver、Dynamic Type、碰撞、性能、真机或资产质量 |
| 本地完整感觉切片 (`0105cd7`) | 同一 iPhone 17 Pro / iOS 26.5；12 passed, 0 failures；从结构化页展开稳定“更多感觉”入口并选择“麻木”，两位置分别呈现局部和全组 unknown；94 项 Core、iPhoneOS SDK build 和 Host 静态检查通过 | 只证明 Simulator 内未确认草稿、显式 marker 关联和感觉修订安全边界；不证明 VoiceOver、Dynamic Type、Reduce Motion、碰撞、性能、真机或资产质量 |
| 本地 accessibility-size 结构切片 (`7d8bf59`) | iPhone 17 Pro Max / iOS 26.5；13 passed, 0 failures；`UICTContentSizeCategoryAccessibilityXXXL` 下文字部位 Sheet、今天两张情境卡、结构化页两组动作均可达且纵向排列；94 项 Core、iPhoneOS SDK build 和 Host 静态检查通过 | 只证明当前 Simulator 的局部结构路径；不证明 VoiceOver、完整最大 Dynamic Type、横屏、Switch Control、实际深色/高对比度、Reduce Motion、碰撞、性能、真机或资产质量 |
| GitHub Actions run `31311301360` | `7d8bf59` 的 macOS runner / iPhone 16 / iOS Simulator 18.5：Backend and contracts、Swift 94、iPhoneOS SDK build 和 Host 静态边界成功；仅 internal Host smoke 的 HOST-T-015 失败（exit 65） | 失败记录；不能以已成功步骤或历史本地结果替代该次 Host smoke，更不能外推为无障碍、真机或发布通过 |
| GitHub Actions run `31312416395` | `7e64833` 的 macOS runner / iPhone 16 / iOS Simulator 18.5 / Xcode 16.4：终态 failed；Backend and contracts、Swift 94、iPhoneOS SDK build 和 Host 静态边界成功；internal Host smoke 为 12 passed、1 failed、0 skipped，仅 HOST-T-015 因预期 `body-map.next` Button 未找到而失败（exit 65） | 第二次失败记录；不证明该路径、无障碍、真机或发布通过 |
| GitHub Actions run `31313515662` | pushed SHA `306f2b91` 的 macOS runner / iPhone 16 / iOS Simulator 18.5 / Xcode 16.4：终态 failed；Backend and contracts、Swift 94、iPhoneOS SDK build 和 Host 静态边界成功；internal Host smoke 为 12 passed、1 failed、0 skipped，仅 HOST-T-015 因预期静态文案“已添加待确认位置：左膝附近”未找到而失败（exit 65） | 第三次失败记录；不证明该路径、无障碍、真机或发布通过 |
| GitHub Actions run `31314859140` | SHA `98a4200` 的 macOS runner / iPhone 16 / iOS Simulator 18.5 / Xcode 16.4：终态 failed；Backend and contracts、Swift 94、iPhoneOS SDK build 和 Host 静态边界成功；internal Host smoke 为 12 passed、1 failed、0 skipped，仅 HOST-T-015 失败，因为文字部位 Sheet 关闭后 `body-map.next` 已存在但不可点击（exit 65） | 第四次失败记录；不能把控件存在视为可达/可操作通过，也不证明无障碍、真机或发布通过 |
| GitHub Actions run `31318855810` | SHA `544c39a`：Backend and contracts 成功；iOS 仅 internal Host smoke 失败，12 passed、1 failed、0 skipped；HOST-T-015 报 `Expected element to exist: body-map.next Button`（exit 65）。CI 未上传 artifact 或 accessibility hierarchy | 历史 H015 CTA failure；不能断定文字选择未保留位置还是 AX 投影/元素类型，也不证明无障碍、真机或发布通过 |
| GitHub Actions run `31321251024` | SHA `cb5f798`：Backend and contracts、Swift、iPhoneOS SDK build 与 Host boundary 成功；internal Host smoke 12 passed、1 failed、0 skipped；唯一 H015 在 5 秒内未满足旧 `body-map.marker-count-summary` label CONTAINS `位置标记数量 1` | 历史 terminal failure；不能归因位置丢失；不证明无障碍、真机或发布通过 |
| GitHub Actions run `31350639359` | SHA `4cc46e2`：Backend/contracts、Swift 94/94、iPhoneOS SDK build、Host boundary 与 internal Host smoke 全部成功；iPhone 16 / iOS Simulator 18.5 / Xcode 16.4 | 当前远端 Simulator receipt；成功 smoke 日志不提供精确 XCTest 数，不证明真机或生产通过 |
| 2026-08-13 可信助手本地复验 | 未提交工作树：Swift 103/103、generic iPhoneOS build、Host 静态门禁和 AppHost 资源隔离通过；历史候选 probe 进入 ready 后等待 8.5 秒仍 ready；最终 13 项 iPhone 17 Pro / iOS 26.5 full Host 收据 exit 0 | 只证明当前 Simulator/SDK 上的受控状态与资源读取路径；未点击网格，不证明真机、faceIndex、性能、完整无障碍或生产资产 |
| 本地 HOST-T-015 历史测试专用修复（`0ed0563`） | iPhone 17 Pro / iOS 26.5；不再依赖短暂选择反馈，先验证无并存 `MarkEditor`、完成/关闭文字部位 Sheet 后检查 `body-map.next`，并同样加固 `selectBoth`；完整 Internal Host suite、单独 HOST-T-015 与 Swift Core 94/94 通过 | 历史本地 Simulator 复测；后续 run `31314859140` 说明该断言修复本身未解决远端布局可点击性 |
| SHA `544c39a` 前的 H015 本地收据 | 先前 safe-area CTA/identifier/Today 内容滚动/type-agnostic 查询及展示卡非动作断言后的 iPhone 17 Pro / iOS 26.5：定向 HOST-T-015 1 passed、0 failed、0 skipped（86.0s）；完整 script exit 0（402.313s） | 历史本地内部 Simulator 收据。当前 `4cc46e2` 的 targeted/full 收据另列，均不证明真机或资产质量 |
| GitHub Actions run `31295533318` | macOS runner 的 iPhone 16 / iOS 18.5 成功执行 `scripts/run_internal_ios_host_tests.sh`；iOS job 总时长 7m11s | 云端 Simulator 可重建；不是物理 iPhone 或签名证据 |
| GitHub Actions run `31301067572` | `ea85c68` 的 macOS runner / iPhone 16 / iOS 18.5 成功执行 Swift 83 项、iPhoneOS build、Host 静态边界检查和完整 `scripts/run_internal_ios_host_tests.sh`；Host smoke 288 秒 | 当前候选 probe 的远端可重建性；测试只接受 ready 或候选专属 2D fallback，未记录分支作为资产质量结论 |
| GitHub Actions run `31303340128` | `9fc54d4` 的 Backend and contracts 成功（20 秒）；iOS package and internal host 成功（8m28s），包括 Swift tests、iPhoneOS SDK build、Host boundary 与 internal Host smoke | 云端 Simulator 可重建当前文字部位切片；不是物理 iPhone、真实 VoiceOver、性能或签名证据 |
| GitHub Actions run `31307042209` | `0105cd7` 的 Backend and contracts 成功；iOS package and internal host 在 iPhone 16 / iOS Simulator 18.5 成功执行 Swift 94、iPhoneOS SDK build、Host boundary 与 internal Host smoke（Host smoke 09:55:37–10:04:42 UTC） | 云端 Simulator 可重建当前完整感觉/感觉修订边界；不是物理 iPhone、真实 VoiceOver、性能、碰撞或签名证据 |
| Swift iPhoneOS build | `BodyCompanionIOS` target 成功 | 只证明 iOS SDK 编译 |
| Swift iPhoneSimulator build | `BodyCompanionIOS` target 成功 | 只证明 Simulator SDK 编译 |
| Swift Core tests | 历史 `5dddd83` / `9fc54d4` / `0105cd7` 收据分别为 80/87/94 tests；2026-08-13 当前未提交 checkout 已复验 `103 tests, 0 failures`，新增 Zone/Pin+surface、triangle/barycentric、region-map confidence、watchdog 和 approved 资产门禁回归 | 只证明状态/契约，不证明 UI/设备 |

运行时前置条件缺失时，不能使用临时 `swift run`、macOS prototype 或无签名的 library 产物替代 iOS App 安装测试。

## 3. 维度结果矩阵

| 维度 | 结果 | 已有静态/代码证据 | 真机关闭条件 |
|---|---|---|---|
| Sheet | **Simulator smoke passed / device blocked** | 紧凑宽度通过系统 `.sheet`、`.medium/.large` detents、drag indicator 和 `ScrollView` 承载**位置 Inspector**；UI smoke 打开列表/编辑器并通过显式“完成”返回；删除后状态会由模型清理 | 在 iPhone 上验证首次选择、再次选择、切换标记、删除、旋转和系统返回；确认 Sheet 不遮挡继续入口、焦点不丢失 |
| VoiceOver | **Blocked** | 2D 有部位列表等价路径；主要按钮有 label/hint；3D 仅提供整体语义说明并保留 2D/列表回退 | 开启 VoiceOver，从 Today → 记录 → 2D/列表 → 位置 Inspector → 结构化描述 → 删除 → 继续全程完成；验证提示、计数、结构化程度控件、回退公告和导航顺序 |
| Dynamic Type | **Simulator structural smoke / device blocked** | `4cc46e2` 与 run `31350639359` 已重建 H015；本地 iPhone 17 Pro / iOS 26.5 targeted H015 1/0/0（77.241s）。仍只覆盖局部结构与稳定 selector，不证明 VoiceOver、真实最大字号、横屏或真机 | 最大可访问字号和横屏下不截断标题、位置摘要、提示、结构化程度控件和按钮；确认 Sheet 可滚动且关键操作仍可达 |
| Reduce Motion | **Blocked** | 主题按钮的按压缩放使用 `.animation`，但在 `accessibilityReduceMotion` 时显式置为 `nil`；视角切换代码是直接 `look(at:from:)`，未发现持续旋转 | 开启 Reduce Motion，重复 front/back/left/right/top、焦点和 Sheet 展开；确认无不必要动画、闪烁或自动旋转，手势仍可用 |
| 3D 性能 | **Blocked** | 1.2.0 render USDZ 为 600,103 bytes/24,020 triangles，独立 collision 为 1,904 triangles；专用 Simulator probe 显式开启后进入 ready 且 8.5 秒后仍保持 ready。代码在 MainActor 同步 `Entity.load` 和 `generateCollisionShapes(recursive:)`，现有日志仍没有单独计时 collision 生成 | 最低支持 iPhone 冷启动、首次交互、连续旋转/缩放 5 分钟；采集分段 load/collision/attach 耗时、P95 命中、FPS、内存、热状态和崩溃 |
| 碰撞命中 | **Static path implemented / device validation blocked** | 只对独立 `body_collision_v1` 设置人体 CollisionGroup，marker 使用独立 group；`hitTest(.nearest, mask: body ∪ marker)` 先识别 `marker_`，再解析稳定 collision Mesh；位置/法线相对 collision Mesh，iOS 18 将 `TriangleHit.uv` 转为与 triangle index 成对的 barycentric，face range 由签名 region map 解析，iOS 17 无 TriangleHit 时保持 2D/列表回退 | 真机逐区域黄金点、边界点、遮挡点和已有 Marker 重叠点；验证 RealityKit faceIndex 与冻结面顺序、命中延迟、误落点、Marker 优先级和 2D 回退 |
| 候选资产生产审核 | **Candidate only / blocked by gate** | `usdchecker --arkit` Success、render/collision ZIP payload 64-byte 对齐、SHA/清单/Swift/USD identity 一致；独立 collision geometry digest、region map/surface correspondence/camera preset、manifest self-hash 和离线签名 verified；Y-up/米制/identity root，30 个 render Mesh 含 lower_back；候选资源仅由内部 AppHost 显式打包。清单仍为 candidate、commercial/app_store=false、anatomy/performance pending | 作者链/许可证、法务署名、解剖语义、真机性能/命中、无障碍和生产签字全部通过后才可申请 approved |

## 4. 本次静态审核发现

这些是生产门禁问题，不因“无法连接设备”而自动通过：

| ID | 严重度 | 发现 | 处理要求 |
|---|---|---|---|
| DEVICE-FINDING-001 | P0 | 无 App target 的 Simulator 阻塞已由 `5dddd83` 解除；仍没有受真实 Team/Bundle ID/证书支持的签名 App target，无法安装、切换真实设备辅助功能设置或采集设备性能 | 由具名 iOS/安全负责人提供正式 Bundle ID、Team/证书、必要 entitlements 与真机 scheme；完成后重跑本记录 |
| DEVICE-FINDING-002 | P1 剩余验证 | 当前代码已实现独立 collision/marker CollisionGroup 与 mask，且不再使用 `.all`；尚未有真机黄金点和 collision 生成耗时收据 | 用真机黄金点证明 Marker 优先、命中边界、遮挡行为和 P95；不能以 Simulator ready 替代 |
| DEVICE-FINDING-003 | P1 剩余验证 | 1.1.0 历史代码未读取 triangle/barycentric；当前 iOS 18 已把 `TriangleHit.uv` 转成 `{u,v,1-u-v}` 并与 triangle index 成对，Core 对非法/缺配对命中 fail closed | 使用不对称冻结网格在真机验证 RealityKit faceIndex 与 region map 顺序；iOS 17 继续明确降级，不得伪造精确面 |
| DEVICE-FINDING-004 | P1 剩余验证 | 1.1.0 缺少 `body_lower_back`；1.2.0 已以实际 Mesh prim 补齐，并有独立 collision triangle region map、surface correspondence 和离线签名通过静态读回。当前仍无解剖/视觉签字和真机黄金集，不能由分段名称或静态映射声称下背命中 | 完成解剖/视觉审核、真机 faceIndex 黄金集和边界集；禁止仅根据实体名声称下背命中 |
| DEVICE-FINDING-005 | P1 剩余验证 | 1.1.0 根层 `-90°` 与清单冲突；1.2.0 的 `/BodyCompanion` 与 `/body_root` 已是 identity，Y-up/米制/groundY=0/height=1.86 已由跨层脚本读回 | 在真机以方向哨兵点验证前后/左右和相机 preset；缺该证据仍不得批准 |
| DEVICE-FINDING-006 | P1 | manifest `performance.status=pending` 且冷启动/P95/FPS/内存均为 0；代码没有 FPS/内存/signpost 采集 | 在目标 iPhone 上建立不含健康正文的性能采集和阈值评审；未测量不能改为 passed |
| DEVICE-FINDING-007 | P2 | 2026-08-09 已从 `MarkEditor` 移除程度 Slider；结构化 `SignalIntakeScreen` 的程度控件虽有可见“程度”标签与 accessibility value，仍未经过真机 VoiceOver/最大 Dynamic Type 验证。`4cc46e2` 的 Simulator H015/multi-location/full receipts 不关闭该设备发现；位置摘要、完整页面、深色/高对比度和横屏仍未经过设备验证。 | 真机 VoiceOver/Dynamic Type 验证结构化程度控件；必要时取消摘要硬截断，并保留部位列表等价路径。 |

## 5. 候选资产审核读回（1.1.0 历史快照）

> 本节记录升级前 1.1.0 的发现，不是当前 Bundle 状态。2026-08-13 的 1.2.0 当前生成与校验收据见 EVIDENCE-01；设备门禁仍未关闭。

- Bundle：`ios/BodyCompanion/Sources/BodyCompanionIOS/Resources/BodyNeutralPrototype.usdz`
- 文件大小：606,024 bytes；USDZ 内含 `BodyNeutralPrototype.usdc` 与 `textures/color_0C0C0C.exr`，均通过 `unzip -t`。
- `usdchecker`：`Validation Result ... Success!`。
- SHA-256：`299d896513a8c7ef7e5d584495c9bc5ba78505da5f20c9dc2b50e0ef9d7e5668`，与 `docs/assets/body-neutral-procedural-v1.manifest.json` 的 source/render/collision artifact 一致。
- USD 树可读，包含 `body_root` 与 29 个分段实体（`body_*` Xform 共 30 个）；这只是文件结构证据，不是解剖质量、RealityKit 视觉、碰撞或设备性能证据。
- manifest 的 `release_status=candidate`、`signature_status=unverified`、`rights.commercial_use=false`、`rights.app_store_distribution=false`、`review.anatomy_status=pending`、`performance.status=pending` 必须保持不变。

## 6. 设备恢复后的复测顺序

1. 用户连接并解锁 iPhone，点击“信任”，确认 `xctrace` 与 `devicectl` 状态为 available/connected。
2. 以现有 `BodyCompanionInternal` 为基础，由具名负责人提供正式 iOS App target、scheme、Bundle ID、Team、签名和 Debug/Release 配置；继续把 Swift Package 的 `BodyCompanionIOS` 作为依赖，不把 macOS executable 当作 iOS 壳。
3. 先跑 2D/列表和 Sheet 的 VoiceOver、Dynamic Type、Reduce Motion；失败时不得进入 3D 资产批准。
4. 在候选开关下运行 3D，采集冷启动、FPS、P95 命中、内存、热状态、崩溃和所有回退；不记录原始健康对话。
5. 执行碰撞黄金集：每个可映射区域的内部点、边界点、遮挡点、Marker 重叠点、前后/左右视角和取消/重试；确认结果只生成未确认位置草稿。
6. 由资产、解剖/视觉、无障碍、iOS、QA、法务分别签字后，才允许更新 manifest 的批准字段和发布门禁。

## 7. 发布决定

本轮决定：**在既有历史收据之外，记录 2026-08-13 未提交工作树的 103 项 Core、AppHost 资源隔离、候选资产闭环读回和历史候选 ready 跨 8.5 秒/13 项 full Host 收据。** 这些结果只证明内部 Simulator/SDK；不批准生产 3D，不声称真机或完整无障碍通过，不关闭 GATE-06/GATE-07/GATE-08。当前也没有远端 CI/受保护分支新收据。设备和正式 App target 到位前，生产路径保持 2D/列表 fail-closed；候选资产和 3D loader 仅限内部 prototype flag。
