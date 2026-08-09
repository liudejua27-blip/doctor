# TEST-IOS-P0-RUNTIME-01：内部 iOS App Host 与 Simulator 测试计划

| 属性 | 值 |
|---|---|
| 测试 ID | TEST-IOS-P0-RUNTIME-01 |
| 版本 | 0.3.0 |
| 状态 | Executed local smoke including candidate 3D probe / internal-only evidence / remote run pending |
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
| HOST-T-005 | 2D/列表路径 | 不依赖候选 3D 选择一个合成部位，进入结构化描述 | UI |
| HOST-T-006 | 草稿继续 | 进入草稿后返回入口，再继续时按当前 phase 进入结构化描述并保持进程内 draft；Core 测试锁定 UUID/位置/phase 语义 | UI + Core |
| HOST-T-007 | 新建确认 | 有草稿时“新建”先显示放弃对话框；UI 断言固定可见标题，Core 测试锁定取消不 reset、确认后才 reset | UI + Core |
| HOST-T-008 | 普通 AI 关闭 | AI 身体助手明确显示“普通对话尚未接入”；不存在建议、行动或资料已使用断言 | UI |
| HOST-T-009 | 候选 3D 回退 | UI test 配置下显示 2D/列表或明确内部候选/回退提示；不得依赖碰撞命中 | UI |
| HOST-T-010 | 权限与网络负向 | `check_internal_ios_host.py` 断言无 HealthKit/相机/麦克风/照片/通知 usage key、Provider/URLSession 入口或分析 SDK；冷启动 UI smoke 不出现应用权限流程 | 静态 + UI |
| HOST-T-011 | 存储负向 | 无 UserDefaults/Keychain/文件/数据库健康草稿写入；重启不宣称恢复 | 静态 + UI |
| HOST-T-012 | identifier 与动态文字基础 | 自定义主要按钮和路径状态有稳定 identifier；系统 confirmationDialog 以固定可见中文标题断言；不得只以颜色传达状态 | UI 静态 + Simulator |
| HOST-T-013 | 候选 3D 显式 probe | 独立 `XCUIApplication` 只设置 `BODY_COMPANION_ENABLE_CANDIDATE_3D=1`；进入 3D 后，先等待本次 Scene 的 `onLoadAttempted` 确认，再等待“内部候选已加载并保留 3D 列表入口”或“加载/初始化错误或 8 秒超时后的固定 2D 回退公告并保留 2D 列表入口”之一。不得设置 `BODY_COMPANION_UI_SMOKE=1`、不得点击人体或断言命中 | Simulator UI |

### 3.1 候选 3D probe 的可接受结果

`HOST-T-013` 必须单独启动 App，避免默认 smoke 的 `BODY_COMPANION_UI_SMOKE=1` 覆盖显式候选开关。每次请求均有新的仅内存 attempt ID；测试先观察当前 `BodySceneView` 在 Bundle 查询/loader 前发出的 `onLoadAttempted`，再观察可见终态：

1. **内部候选加载成功**：可见“内部候选模型，未经生产审核”与 3D 页面中的“从列表选择部位”入口；或
2. **fail-closed 回退**：可见候选 loader 专用的固定 `body-map.candidate-3d-fallback-notice` 与 2D 部位列表入口；加载错误、初始化失败或 8 秒无终态都必须走此路径。普通 UI smoke 的 `body-map.fallback-notice` 不能代替此断言。

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

通过 Simulator Host smoke 的最低条件：HOST-T-001～013 均有自动化或静态覆盖、原有回归不退化、无新增 API/Schema/健康字段，且输出证据明确标记为内部 Simulator。系统 confirmationDialog 的取消/确认状态转换必须由 UI black-box 回归与 Core 回归共同锁定，避免把当前 XCTest 对原生系统按钮层级的可见性差异误写为功能缺口。

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
remote CI: 当前提交前 Pending
```

## 8. 变更记录

| 日期 | 变更 | 说明 |
|---|---|---|
| 2026-08-09 | 新建 TEST-IOS-P0-RUNTIME-01 | 将内部 App Host 的构建、启动、UI smoke、无网络/无权限/无持久化负向检查与真机不可外推边界固定下来。 |
| 2026-08-09 | 0.2.0 | 本地 iPhone 17 Pro / iOS 26.5 的 7 项 UI smoke 和远端 CI iPhone 16 / iOS 18.5 的同一脚本均通过；精确命令与未证明范围见 EVIDENCE-01/EVIDENCE-DEVICE-01。 |
| 2026-08-09 | 0.3.0 | 执行 HOST-T-013：显式候选 3D Simulator probe 先锁定 loader-entry，当前本地运行实际进入 ready 并保留列表入口；不测试人体命中或升级资产/真机结论，远端 CI 待推送。 |
