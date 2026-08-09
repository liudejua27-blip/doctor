# TEST-IOS-P0-RUNTIME-01：内部 iOS App Host 与 Simulator 测试计划

| 属性 | 值 |
|---|---|
| 测试 ID | TEST-IOS-P0-RUNTIME-01 |
| 版本 | 0.5.2-draft |
| 状态 | Executed locally: HOST-T-001～015 have internal-only Simulator evidence; `7d8bf59` binds HOST-T-015 locally and its current remote CI is pending |
| 关联功能 | FEAT-IOS-P0-RUNTIME-01、FEAT-COMP-01 P0、FEAT-BODY-MAP-V1/V2 |
| 负责人 | iOS + QA + 无障碍负责人（待 GOV-01 指定） |
| 依赖 | IOS-01、PRIV-01、QA-01、BODY-01、TEST-BODY-MAP-V1/V2、TEST-COMP-01、EVIDENCE-DEVICE-01 |
| 发布意义 | 内部 Simulator smoke；不构成真机、签名、临床、生产 3D 或生产 App 验收 |

## 1. 目标

证明受版本控制的 `BodyCompanionInternal` 可以作为 iOS Simulator App 启动，并在不启用网络、Provider、真实资料读取、正式写入、持久化或产品分析的情况下，运行既有 P0 页面与完整 2D/列表回退。

## 2. 环境与数据

| 项目 | 规定 |
|---|---|
| Xcode | 当前受支持 Xcode；实际版本写入执行证据 |
| Destination | 明确的 iPhone Simulator UDID/名称和 iOS runtime；不得把 Simulator 记为真机 |
| 数据 | 仅空白/合成测试状态；不得使用真实身体信号、真实账号、真实截图/录屏或生产 Provider |
| Host 模式 | `DebugInternal` 或等价内部配置；UI test 默认禁用候选 3D |
| 网络 | 断言无应用发起的网络/Provider 请求；测试工具下载不属于产品网络能力 |
| 记录 | 仅保存命令、构建版本、成功/失败、截图中不含真实健康内容的合成状态 |

## 3. 自动化覆盖矩阵

| 测试 ID | 场景 | 断言 | 层级 |
|---|---|---|---|
| HOST-T-001 | 工程发现 | `xcodebuild -list` 有 project、App scheme、UI test target | 静态/构建 |
| HOST-T-002 | Simulator 编译与安装 | 生成 Simulator `.app`，可由 XCTest 启动 | 集成 |
| HOST-T-003 | 冷启动今天页 | “今天”“记录这次不适”和非诊断说明存在；无“已恢复/已保存” | UI |
| HOST-T-004 | 多入口一致 | 今天、记录、AI 身体助手都可进入同一位置草稿路径 | UI |
| HOST-T-005 | 2D/文字列表路径 | 通过显式“用文字选择部位”入口，在本地目录搜索合成部位并选择；进入结构化描述，结果仅为待确认 Area/Zone | UI |
| HOST-T-006 | 草稿继续 | 进入草稿后返回入口，再继续时按当前 phase 进入结构化描述并保持进程内 draft；Core 测试锁定 UUID/位置/phase 语义 | UI + Core |
| HOST-T-007 | 新建确认 | 有草稿时“新建”先显示放弃对话框；UI 断言固定可见标题，Core 测试锁定取消不 reset、确认后才 reset | UI + Core |
| HOST-T-008 | 普通 AI 关闭 | AI 身体助手明确显示“普通对话尚未接入”；不存在建议、行动或资料已使用断言 | UI |
| HOST-T-009 | 候选 3D 回退 | UI test 配置下显示 2D/列表或明确内部候选/回退提示；不得依赖碰撞命中 | UI |
| HOST-T-010 | 权限与网络负向 | `check_internal_ios_host.py` 断言无 HealthKit/相机/麦克风/照片/通知 usage key、Provider/URLSession 入口或分析 SDK；冷启动 UI smoke 不出现应用权限流程 | 静态 + UI |
| HOST-T-011 | 存储负向 | 无 UserDefaults/Keychain/文件/数据库健康草稿写入；重启不宣称恢复 | 静态 + UI |
| HOST-T-012 | identifier 与动态文字基础 | 自定义主要按钮和路径状态有稳定 identifier；文字入口、搜索框、无结果状态和选项使用稳定目录 ID（不能使用过滤后的序号或用户输入）；系统 confirmationDialog 以固定可见中文标题断言；不得只以颜色传达状态 | UI 静态 + Simulator |
| HOST-T-013 | 候选 3D 显式 probe | 独立 `XCUIApplication` 只设置 `BODY_COMPANION_ENABLE_CANDIDATE_3D=1`；进入 3D 后，先等待本次 Scene 的 `onLoadAttempted` 确认，再等待“内部候选已加载并保留共享文字列表入口”或“加载/初始化错误或 8 秒超时后的固定 2D 回退公告并保留同一入口”之一。不得设置 `BODY_COMPANION_UI_SMOKE=1`、不得点击人体或断言命中 | Simulator UI |
| HOST-T-014 | 更多感觉与未知边界 | 从结构化描述页展开具有稳定、非健康内容 identifier `sensation-picker.more-open` 的“更多感觉”，以固定内部中文标签“麻木”选中既有稳定枚举中的扩展项（不依赖用户输入或过滤序号）；它沿用显式位置关联、只形成未确认草稿，不显示 AI 建议、网络、保存成功或医学结论。两个位置时还必须分别呈现“部分位置的感觉说不清”和“这些位置的感觉都说不清”，不能再出现重复的单位置同义入口 | Simulator UI + Core |
| HOST-T-015 | accessibility-size 结构回归 | 以 iOS Simulator 的 accessibility-size 启动参数冷启动；以合成草稿验证 2D/文字部位 Sheet 的选择链路、今天页两张情境提示卡，以及结构化描述页的“确认/未知”和“保存/未知”成对动作均可滚动到且可点击；在该尺寸下，三组并列内容必须暴露稳定的 `.vertical` 容器 identifier 且同名 `.horizontal` 容器不存在，证明运行时选择纵向布局分支；测试不比较滚动后控件的瞬时屏幕坐标。只使用稳定 identifier，不判断位置摘要/回退提示、VoiceOver 朗读、实际对比度数值、横屏或真机辅助功能 | Simulator UI |

### 3.1 候选 3D probe 的可接受结果

`HOST-T-013` 必须单独启动 App，避免默认 smoke 的 `BODY_COMPANION_UI_SMOKE=1` 覆盖显式候选开关。每次请求均有新的仅内存 attempt ID；测试先观察当前 `BodySceneView` 在 Bundle 查询/loader 前发出的 `onLoadAttempted`，再观察可见终态：

1. **内部候选加载成功**：可见“内部候选模型，未经生产审核”与 3D 页面中的共享“用文字选择部位”入口；或
2. **fail-closed 回退**：可见候选 loader 专用的固定 `body-map.candidate-3d-fallback-notice` 与同一文字入口；加载错误、初始化失败或 8 秒无终态都必须走此路径。普通 UI smoke 的 `body-map.fallback-notice` 不能代替此断言。

两者都不是质量结论。不得由测试点击 3D 网格、Pin、Zone 或将测试结果解释为 Region/Collision/triangle/barycentric、视觉、解剖、FPS、内存、VoiceOver、Dynamic Type、Reduce Motion、真机或许可通过。

“已加载”可见状态必须只对应同一个已 `onLoadAttempted` 的当前 Scene `onReady`。`BodyMapModel` 的初始/2D interactive 状态、直接改为 3D mode、失败/过期 attempt 或测试 fixture 都不能复用该 identifier；切到 2D 或新的请求后，旧回调必须被拒绝；对应 Unit coverage 为 TEST-BODY-014 / TEST-BODY-V2-021。

## 4. 必须保留的现有回归

- `cd ios/BodyCompanion && swift test`；
- `BodyCompanionIOS` iPhoneOS SDK build；
- 后端完整测试与 `scripts/check_baseline.py`；
- TEST-BODY-MAP-V1/V2 的 Core 边界、P0 map-only 与 20 个总位置上限；
- TEST-COMP-01 的 P0 AI 关闭、草稿继续/新建与非诊断边界。

## 5. 无障碍与设备证据边界

Simulator smoke 可以证明 accessibility identifier、可见文案、无 3D 入口和基础布局没有在启动时崩溃；它**不能**替代：

- 开启 VoiceOver 的完整交互、焦点顺序或朗读正确性；
- 最大 Dynamic Type、横屏、Switch Control 或外接键盘体验；
- Reduce Motion 的系统行为；
- 真机 GPU、热、内存、触控、RealityKit 碰撞或候选资产性能；
- Team/证书/签名、真实设备安装或 App Store 审查。

这些项目仍按 EVIDENCE-DEVICE-01、TEST-BODY-MAP-V1/V2、IOS-01 和 GATE-06/08 跟踪。

## 6. 通过条件与停止规则

通过 Simulator Host smoke 的最低条件：HOST-T-001～015 均有自动化或静态覆盖、原有回归不退化、无新增 API/Schema/健康字段，且输出证据明确标记为内部 Simulator。系统 confirmationDialog 的取消/确认状态转换必须由 UI black-box 回归与 Core 回归共同锁定，避免把当前 XCTest 对原生系统按钮层级的可见性差异误写为功能缺口。语义感觉变更后的安全失效与高风险拒绝还必须由 Core 覆盖，不能由 Host UI 替代。

以下任一项失败即停止：2D/列表不能完成、草稿被静默丢弃或误称保存、普通 AI/建议被伪造、检测到网络/Provider/权限/持久化/分析入口、候选 3D 没有回退、或文档把 Simulator 外推为真机/生产。

## 7. 执行证据模板

```text
commit: <sha>
project/scheme: BodyCompanionInternal.xcodeproj / BodyCompanionInternal
destination: <simulator name + runtime + UDID>
configuration: DebugInternal
commands: <xcodebuild build-for-testing / test>
result: passed | failed
covered test IDs: HOST-T-001 ...
not proven: 真机、签名、VoiceOver 实操、最大 Dynamic Type、Reduce Motion、3D 性能/碰撞、资产许可、临床/生产发布
```

### 7.1 当前本地执行记录（候选 3D 专用 probe）

```text
commit: 79f1f36
project/scheme: BodyCompanionInternal.xcodeproj / BodyCompanionInternal
destination: iPhone 17 Pro / iOS 26.5 / 68F37251-71BE-4F42-9849-62D61BFFE7C3
configuration: DebugInternal
result: 9 passed, 0 failures
coverage: 9 个 UI XCTest + `check_internal_ios_host.py` 的静态覆盖共同覆盖 HOST-T-001～013；HOST-T-013 先出现 body-map.candidate-3d-load-attempted，随后出现 body-map.candidate-3d-ready、3D Scene 与列表入口
not proven: 不点击人体；未生成 BodyLocation 或健康事实；不证明真机、签名、VoiceOver、最大 Dynamic Type、Reduce Motion、3D 性能/碰撞、资产许可、临床/生产发布
remote CI: ea85c68 / run 31301067572 成功；CI 只证明 HOST-T-013 的允许终态，不将 ready/fallback 分支作为资产质量结论
```

### 7.2 当前本地执行记录（文字部位 Area-only）

```text
commit: 9fc54d4
project/scheme: BodyCompanionInternal.xcodeproj / BodyCompanionInternal
destination: iPhone 17 Pro / iOS 26.5 / 68F37251-71BE-4F42-9849-62D61BFFE7C3
configuration: DebugInternal
result: 10 passed, 0 failures；Swift Core 87 passed, 0 failures；iPhoneOS SDK build 与 check_internal_ios_host.py 通过
coverage: HOST-T-005/012 验证 2D 中本地搜索“膝”并选择稳定目录项“左膝附近”、无结果不写草稿；HOST-T-009/013 验证默认 2D fallback 与候选 ready-or-fallback 终态都可进入同一文字入口。Pin 模式的 Area-only 不变量由 Core TEST-BODY-V2-022 覆盖：无 `anchor_2d.point`、`anchor_3d` 或顶层 `model_asset`，但保留 2D 区域锚点的目录资产元数据
remote CI: 9fc54d4 / run 31303340128 成功；Backend and contracts 与 iOS Swift tests、SDK build、Host boundary、internal Host smoke 均通过
not proven: 不点击人体；不证明真实 VoiceOver、最大 Dynamic Type、Reduce Motion、真机、3D 性能/碰撞、资产许可、签名、临床/生产发布
```

### 7.3 当前本地执行记录（完整感觉与感觉修订安全边界）

```text
commit: 0105cd7
project/scheme: BodyCompanionInternal.xcodeproj / BodyCompanionInternal
destination: iPhone 17 Pro / iOS 26.5 / 68F37251-71BE-4F42-9849-62D61BFFE7C3
configuration: DebugInternal
result: 12 passed, 0 failures；Swift Core 94 passed, 0 failures；iPhoneOS SDK build 与 check_internal_ios_host.py 通过
coverage: HOST-T-001～014 的完整内部 Host suite。HOST-T-014 从既有位置路径进入结构化描述，展开 `sensation-picker.more-open` 的“更多感觉（22 项）”，以原生 Toggle 选中“麻木”，只保留带显式 marker 关联的未确认草稿；两个位置分别出现“部分位置的感觉说不清”和“这些位置的感觉都说不清”。Core 同时覆盖常用 10 项/扩展 22 项的单一派生目录、普通本地安全状态下语义感觉修订的 safety/Agent/approval 失效、R0/R1/R2/undetermined/safety_action 的直接修订拒绝，以及 no-op 不变性
remote CI: 0105cd7 / run 31307042209 成功；Backend and contracts 成功，iOS package and internal host 在 iPhone 16 / iOS Simulator 18.5 成功重建 Swift 94、SDK build、Host boundary 与 internal Host smoke（Host smoke 09:55:37–10:04:42 UTC）
not proven: 不点击人体；不证明真实 VoiceOver、最大 Dynamic Type、Reduce Motion、真机、3D 性能/碰撞、资产许可、签名、临床/生产发布；不关闭 CONFLICT-004 的高风险非感觉事实修订阻断
```

### 7.4 当前本地执行记录（accessibility-size 结构回归）

```text
commit: 7d8bf59
project/scheme: BodyCompanionInternal.xcodeproj / BodyCompanionInternal
destination: iPhone 17 Pro Max / iOS 26.5 / 8E7BDCDA-1B31-44ED-A48F-030C64725289
configuration: DebugInternal
result: 13 passed, 0 failures；Swift Core 94 passed, 0 failures；iPhoneOS SDK build 与 check_internal_ios_host.py 通过
coverage: HOST-T-001～015；HOST-T-015 使用 UICTContentSizeCategoryAccessibilityXXXL，只验证合成草稿后的 2D/文字部位 Sheet 选择链路、今天页两张情境提示卡纵向排列，以及结构化描述页“确认/未知”“保存/未知”成对动作纵向且可达
remote CI: pending
not proven: 不判断位置摘要、焦点/重置、回退提示、VoiceOver 朗读或焦点顺序、真实最大 Dynamic Type、横屏、Switch Control、实际深色/高对比度数值、Reduce Motion、真机、3D 性能/碰撞、资产许可、签名、临床/生产发布
```

## 8. 变更记录

| 日期 | 变更 | 说明 |
|---|---|---|
| 2026-08-09 | 新建 TEST-IOS-P0-RUNTIME-01 | 将内部 App Host 的构建、启动、UI smoke、无网络/无权限/无持久化负向检查与真机不可外推边界固定下来。 |
| 2026-08-09 | 0.2.0 | 本地 iPhone 17 Pro / iOS 26.5 的 7 项 UI smoke 和远端 CI iPhone 16 / iOS 18.5 的同一脚本均通过；精确命令与未证明范围见 EVIDENCE-01/EVIDENCE-DEVICE-01。 |
| 2026-08-09 | 0.3.0 | 执行 HOST-T-013：显式候选 3D Simulator probe 先锁定 loader-entry，当前本地运行实际进入 ready 并保留列表入口；不测试人体命中或升级资产/真机结论，远端 CI 待推送。 |
| 2026-08-09 | 0.3.1 | `ea85c68` 的 CI run `31301067572` 成功重建完整 Host suite；其 Host smoke 通过有效终态集合，不把远端分支、碰撞、资产或设备质量外推为通过。 |
| 2026-08-09 | 0.4.0-draft | 规定 HOST-T-005/013 使用共享的本地文字部位入口；实现后必须证明搜索选择只生成 Area/Zone，且不将 Simulator 外推为 VoiceOver 或真机通过。 |
| 2026-08-09 | 0.4.1-draft | 已实现本地文字入口、稳定目录项与 Area/Zone-only 写入路径；Core 与本地 Simulator 执行收据由 EVIDENCE-01 归档，VoiceOver/真机门禁不变。 |
| 2026-08-09 | 0.4.2-draft | 归档 `9fc54d4` 的 87 项 Core 与 10 项本地 Host UI 收据；候选 ready/fallback 共享入口和 Area-only 边界均经 Simulator 自动化覆盖，远端 CI run `31303340128` 已成功。 |
| 2026-08-09 | 0.4.3-draft | 新增 HOST-T-014：完整感觉词典的“更多感觉”内部入口；实现前先按 CONFLICT-003 锁定修订后的安全失效与高风险 P0 拒绝边界。 |
| 2026-08-09 | 0.4.4-draft | 归档 `0105cd7` 的 94 项 Core 与 12 项本地 Host UI 收据：HOST-T-014 已执行，完整感觉与两类 unknown 均只进入未确认草稿；感觉修订按 CONFLICT-003 在普通状态失效、在高风险状态拒绝。远端 CI run `31307042209` 已成功在 iPhone 16 / iOS Simulator 18.5 重建同一 iOS job。 |
| 2026-08-09 | 0.5.0-draft | 新增 HOST-T-015：只在内部 Simulator 验证 accessibility-size 下的结构与关键动作可达；实现前不把它表述为 VoiceOver、最大字号、深色/高对比度、横屏或真机通过。 |
| 2026-08-09 | 0.5.1-draft | `7d8bf59` 已在本地 iPhone 17 Pro Max / iOS 26.5 完成 HOST-T-001～015（13 项 UI 流程）；HOST-T-015 只形成 accessibility-size 的局部结构/可达性 Simulator 证据，远端 CI 尚待运行。 |
| 2026-08-09 | 0.5.2-draft | 为跨 Simulator 尺寸的 HOST-T-015 稳定性，将“纵向排列”的自动化见证固定为运行时布局容器 identifier（`.vertical` 存在、`.horizontal` 不存在）并先滚动到对应动作，再检查分支；仍须由后续本地/远端执行记录证明，不外推视觉几何、VoiceOver 或真机。 |
