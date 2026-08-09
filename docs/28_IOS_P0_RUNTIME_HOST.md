# FEAT-IOS-P0-RUNTIME-01：内部 iOS App Host 与 Simulator 验收路径

| 属性 | 值 |
|---|---|
| 功能 ID | FEAT-IOS-P0-RUNTIME-01 |
| 版本 | 0.3.11 |
| 状态 | Implemented / internal candidate 3D Simulator probe locally and remotely rebuilt；最新远端 run `31318855810`（SHA `544c39a`）中 Backend and contracts 成功，iOS 仅 Host smoke 失败：12 passed、1 failed、0 skipped，HOST-T-015 报 `Expected element to exist: body-map.next Button`（exit 65）。CI 没有 artifact 或 accessibility hierarchy，不能断定是文字选择未保留位置还是 AX 投影/元素类型问题。SHA `544c39a` 前的本地定向/完整 Simulator 回归仅为历史收据。当前 sibling footer、marker-count 先验和 generic stable-ID CTA 验收已实现；本地 iPhone 17 Pro / iOS 26.5 的 targeted HOST-T-015 + MoreSensations 为 2/0/0（138.1s），完整 internal Host script exit 0（426.285s）；远端尚未推送、远端收据 Pending；不构成生产、真机或资产批准 |
| 负责人 | iOS 负责人（待 GOV-01 指定） |
| 审核角色 | iOS、QA、无障碍、隐私安全、3D 资产、产品 |
| 变更级别 | B：安装运行时与测试路径；不得改变健康、AI、隐私或位置语义 |
| 关联需求 | PRD-F01、PRD-F03A、NFR-A11Y-001、NFR-PERF-001、COMP-P0-001～005 |
| 依赖 | DOC-00、IOS-01、BODY-01、PRIV-01、QA-01、REL-01、TRACE-01、FEAT-COMP-01、FEAT-BODY-MAP-V1/V2、EVIDENCE-DEVICE-01 |
| 机器契约 | 沿用现有 `body-location`、`ios-signal-intake@1.1` 与 `ios-draft-envelope@1.1`；本功能不新增 API、OpenAPI 或 JSON Schema |

## 1. 目的

当前 `BodyCompanion` 是 Swift Package：它可以编译 Core 和 iOS library，但不能产生可由 Simulator 安装的 iOS `.app`，也没有可执行的 UI Test bundle。因此，当前的 Sheet、导航、Dynamic Type、可访问标识和页面启动只能由静态代码或临时预览说明，不能形成受版本控制的 Simulator 运行证据。

本功能建立一个**内部专用、可版本控制**的 iOS App Host，将已存在的明亮中文 P0 壳运行在 Simulator 中，并提供最小黑箱 UI smoke 测试。它不是新的产品能力，而是对已有 `AppShell → BodyMapScreen → SignalIntakeScreen` 路径的运行时承载。

## 2. 范围与非目标

### 2.1 范围

- 新建 `ios/BodyCompanion/AppHost/BodyCompanionInternal.xcodeproj` 与共享的 `BodyCompanionInternal` scheme；
- 新建 iOS App target `BodyCompanionInternal`，仅通过本地 Package 依赖 `BodyCompanionIOS`；不得复制 Core、SwiftUI 页面或 USDZ 到 Host；
- 入口只渲染 `WindowGroup { AppShell(...) }`，并注入明确的内部 P0 能力集；
- 新建 `BodyCompanionInternalUITests`，使用 `XCUIApplication` 在指定 Simulator 覆盖 P0 启动、入口、2D/列表和草稿继续/明确放弃路径；
- 为现有可交互控件补充稳定、无健康正文的 accessibility identifier；
- 在本地及 CI 可复现地构建、安装、启动与运行 UI smoke；
- 产出仅限 `Simulator host smoke passed` 的证据，保留所有真机、资产、签名、临床和生产门禁。

### 2.2 非目标

- 不新增 `context_lens`、`analysis_subject`、`QuestionPlan`、资料使用收据、ActionPlan、报告显示类型或任何健康字段；
- 不接入 PydanticAI Provider、云端 Agent、Profile/历史/HealthKit/上传资料读取、正式 API、身份、同意、正式 Event/Approval/Report 写入或分享；
- 不使用 Keychain、文件、UserDefaults、iCloud、共享容器或进程外草稿恢复保存健康内容；
- 不引入产品分析、崩溃 SDK、第三方网络 SDK、推送、后台模式、相机、麦克风、照片或 HealthKit 权限；
- 不让内部 Host、Simulator 截图或 UI smoke 成为真机、VoiceOver 实操、最大 Dynamic Type、Reduce Motion、3D 性能、碰撞命中、签名、资产许可或生产发布证据；
- 不修改现有 P0 的“普通对话尚未接入”状态，也不得展示假的个体建议、病因、动作、营养、药物或剂量。

## 3. 运行时设计

### 3.1 目录、依赖与目标

```text
ios/BodyCompanion/
├── Package.swift                         # 既有 Core/IOS library；仍是真正页面和资源来源
└── AppHost/
    ├── BodyCompanionInternal.xcodeproj/  # 受版本控制的原生 Xcode 工程
    ├── BodyCompanionInternal/             # 唯一 @main App 入口与最小 Info.plist
    ├── BodyCompanionInternalUITests/      # 黑箱 UI smoke
    ├── Config/                             # 无敏感值的公共构建配置
    └── README.md                           # 本地构建、运行和边界说明
```

App target 必须把 `../Package.swift` 作为本地 Swift Package，链接 `BodyCompanionIOS` 产品。`BodyCompanionPrototype` 是 macOS executable，不可作为 iOS Host 或 UI test 入口。Xcode project、scheme、Info.plist 和不含敏感内容的 build configuration 属于源代码；Team、真实 Bundle ID、签名证书、provisioning profile 和本机路径不得提交。

最初内部目标为 iOS 17.0。该值只用于 Simulator 工程兼容，不等于 G2-DEC-004 的发布最低版本决定。

### 3.2 固定内部能力集

Host 必须显式构造 `InternalP0RuntimeConfiguration`（命名可在实现中调整），其值由编译配置和 UI test launch environment 固定，而非来自远端或可编辑用户设置：

| 能力 | DebugInternal 默认 | ReleaseInternal 默认 | UI smoke 默认 | 约束 |
|---|---:|---:|---:|---|
| 2D/部位列表 | 开 | 开 | 开 | 是完整记录回退路径 |
| 候选 3D | 显式内部开关 | 关 | 关 | 未经生产审核；默认 UI smoke 不依赖 RealityKit 碰撞 |
| 网络 / Provider / API | 关 | 关 | 关 | 不得创建 URLSession 请求或发送健康数据 |
| 身份 / 同意 / Profile / 历史资料 | 关 | 关 | 关 | 不得模拟“已授权”或“已读取” |
| 正式写入 / 分享 / 导出 | 关 | 关 | 关 | 只能保留进程内未确认草稿 |
| 本地持久化 / Keychain | 关 | 关 | 关 | 终止后不承诺恢复 |
| 分析 / 崩溃 / 追踪 | 关 | 关 | 关 | 不得发送健康正文或位置数据 |

任何把上表中关闭能力打开的修改必须先完成其对应的 Feature Spec、隐私/安全评审、契约、测试与发布门禁，不能借用 Host 的内部开关绕过 GATE-02～GATE-08。

### 3.3 状态与生命周期

- 每次冷启动创建新的进程内 `SignalIntakeModel`；Host 只显示当前启动中的未确认草稿，不显示“恢复”“同步完成”或“已保存”；
- `Today`、`记录`、`AI 身体助手` 继续使用同一个 `IntakeEntryPolicy`：继续保留同一 draft，只有用户确认放弃后才 reset；
- UI test 可以通过启动参数选择 2D/列表回退和可重复的初始页面，但不得注入真实/仿真健康正文、持久化记录、SafetyTier、Agent 内容或已确认事实；
- Host 不在 `body`、`task`、生命周期回调或后台任务中发起网络、授权、存储或遥测；
- 候选 3D 开关开启时，页面必须持续保留“内部候选、未经生产审核”说明和 2D/列表回退。任何加载/碰撞失败只回退，不能改写位置事实或阻断 P0 路径。
- `BODY_COMPANION_ENABLE_CANDIDATE_3D=1` 只能由人工内部运行或专门的 Simulator probe 显式设置；默认 UI smoke 仍以 `BODY_COMPANION_UI_SMOKE=1` 强制关闭它。probe 不得同时设置两个开关，也不得把候选开关变成 Debug/Release 的默认值。
- 专门 probe 先记录当前 Scene 的 `onLoadAttempted`（发生在 Bundle 查询/loader 前），再只允许记录两种终态：RealityKit 实际加载候选 Bundle 后出现内部候选状态与 3D→列表回退入口，或加载/渲染初始化失败、在 8 秒内没有进入任一终态后出现固定 2D 回退公告与列表入口。它不点击人体、不生成 `BodyLocation`、不验证碰撞、区域映射、性能、无障碍或资产审批。
- 每次 3D 请求都有新的仅内存 attempt ID；“内部候选已加载”不是通用 interactive 状态的别名：它只能由当前已请求且已 `onLoadAttempted` 的 `BodySceneView.onReady` 写入。初始 2D、手动改 mode、失效 attempt 或未收到回调都必须保持 loading，随后 fail-closed 回退；切到 2D 或再次请求会使旧回调无效。

### 3.4 隐私、权限与包体边界

- App target 不申请 HealthKit、通知、相机、麦克风、照片、位置、蓝牙、后台模式、iCloud 或共享容器能力；
- 不包含第三方分析/崩溃 SDK，也不配置网络域名白名单、Provider key、API endpoint 或真实 Bundle/Team 值；
- `Info.plist` 不得含使用敏感权限的 usage description；若未来出现该类 key，测试必须失败并要求单独评审；
- Host 仅在 Simulator 使用合成、空白和本轮人工输入；不得把截图、录屏、Accessibility hierarchy 或 XCTest 附件当作可共享的健康资料；
- 普通日志只允许测试名、页面 ID、错误类别和构建版本；不得打印用户输入、位置、感觉、程度、草稿序列化或 3D 命中数据。

## 4. UI smoke 路径

| ID | 路径 | 最低断言 | 不得推导 |
|---|---|---|---|
| HOST-AC-001 | 冷启动 → 今天 | 中文标题、非诊断说明与“记录这次不适”可见 | 账户、年龄、同意、档案已存在 |
| HOST-AC-002 | 今天 / 记录 / AI 身体助手入口 | 三个入口都能到同一进程内位置草稿 | AI 已读取运动/工作/生活资料 |
| HOST-AC-003 | 身体地图 → 2D/部位列表 | 2D/列表路径可选位置并进入结构化描述 | 3D 资产、碰撞或解剖命中通过 |
| HOST-AC-004 | 已有草稿 → 继续 / 新建 | 继续不改变 draft；新建必须展示放弃确认；取消不 reset | 草稿已落盘或正式保存 |
| HOST-AC-005 | AI 身体助手页 | “普通对话尚未接入”与开始记录入口可见 | AI 分析、建议、行动计划或安全完成 |
| HOST-AC-006 | 3D 被禁用或失败 | 可理解回退文案，2D/列表仍可完成 | 真机 3D、性能或碰撞验收 |
| HOST-AC-007 | 显式内部候选 3D probe | 在独立 Simulator 启动中先确认当前 Scene 的 loader-entry，再只接受“候选加载后仍有列表入口”或“固定 2D 回退后仍有列表入口”两种终态 | 候选资产获批、视觉/解剖正确、任一 3D 命中、碰撞、性能、真机或发布验收 |
| HOST-AC-008 | accessibility-size 结构回归 | `UICTContentSizeCategoryAccessibilityXXXL` 下文字部位 Sheet、两张今天展示性情境卡与结构化页指定成对动作保持纵向结构；内容滚动后，情境卡只验证单一合并的非动作卡片元素、独立 stable ID 与运行时 vertical 布局分支 identifier。所有布局分支容器不得把自己的 identifier 传播或覆盖到子卡片或子动作；结构化动作和地图继续动作才验证可点击。文字选择完成/关闭后，先由 `body-map.marker-count-summary` 表达恰有一项位置；地图继续动作必须在底部独立、非滚动的安全内容布局区，通过 stable identifier 的任意元素查询验证存在、`isHittable` 且可 `tap`。具体布局 API 和 AX element class（尤其 `Button`）不是跨 OS 契约 | VoiceOver、完整最大 Dynamic Type、横屏、Switch Control、实际深色/高对比度、Reduce Motion、真机或发布验收 |

每个可测入口、可见状态与确认动作使用稳定的 identifier；identifier 不得编码身体位置、用户输入、健康事实或诊断词。

## 5. Definition of Ready

- 本 Feature Spec、TEST-IOS-P0-RUNTIME-01、IOS-01、PRIV-01、QA-01、REL-01 与 TRACE-01 已同步；
- 工程只引入 Xcode Host、内部配置、空白 Info.plist、共享 scheme 与 UI test target；
- 未修改任何领域字段、机器契约、远端 API、安全规则或临床内容；
- 内部 Bundle ID/Team/签名策略和 Simulator destination 明确为非生产、非真机；
- 2D/列表、候选 3D 回退、草稿继续/明确放弃和普通 AI 关闭的断言已写入测试计划；
- 文档中明确 Simulator 成功不关闭 DEVICE-FINDING-001 的签名/真机部分，不关闭 GATE-06/07/08。

## 6. 验收与证据

完成该功能至少需要：

1. `xcodebuild -list` 可读出 Xcode project、`BodyCompanionInternal` scheme 和 UI test target；
2. iOS Simulator build 成功，并产生可安装的 `.app`；
3. 指定 Simulator 安装、启动和 UI smoke 全部通过；
4. source/Info.plist/entitlements/编译设置扫描证明没有网络、Provider、权限、持久化或分析 SDK 入口；
5. 原有 Swift Core、iPhoneOS library build、后端和文档/契约基线继续通过；
6. `EVIDENCE-DEVICE-01` 仅追加 Simulator Host 的真实命令与范围，明确真机、签名、VoiceOver、Dynamic Type、Reduce Motion、3D 性能/碰撞和资产审核仍未通过；
7. 相应 commit、远端 required CI 与文档链接均可追溯。

`HOST-AC-007` 的通过只能补充“候选 Bundle 的内部 Simulator 加载/回退路径已运行”的证据。它不改变 `BodyAssetManifest`、许可、审核、性能或发布状态，也不能关闭任一 `DEVICE-FINDING-*`、GATE-06、GATE-07 或 GATE-08。

SHA `544c39a` 的远端 run `31318855810` 不满足 HOST-AC-008：Backend and contracts 成功，但 iOS Host smoke 以 `Expected element to exist: body-map.next Button` 失败（12 passed、1 failed、0 skipped，exit 65）。由于 CI 未提供 artifact 或 accessibility hierarchy，它只表明当时黑箱断言未成立，不能判断位置选择是否丢失，或 `body-map.next` 是否仅以不同 AX 投影/元素类型出现。当前工作树已实现 sibling footer 的底部独立、非滚动安全内容布局区；H015 先断言 `body-map.marker-count-summary` 为一项位置，再以 generic stable-ID any-element 查询验证 CTA 存在、`isHittable` 与 `tap`。不得把 `safeAreaInset` 或 `Button` class 固定为验收 API。本地 iPhone 17 Pro / iOS 26.5 的 targeted HOST-T-015 + MoreSensations 为 2/0/0（138.1s），完整 internal Host script exit 0（426.285s）；远端尚未推送，远端重试 Pending。

## 7. 未决项与停止规则

| ID | 未决项 | 责任角色 | 最晚门禁 | 临时行为 |
|---|---|---|---|---|
| HOST-OPEN-001 | 内部 App 的最终 Bundle ID、Team、签名和真机安装策略 | iOS + 安全 | 真机安装前 | 仅 Simulator，绝不提交 Team/证书 |
| HOST-OPEN-002 | Simulator 可证明的 VoiceOver/Dynamic Type/Reduce Motion 最低自动化范围；最新 SHA `544c39a` 的 run `31318855810` 中 Backend and contracts 成功，iOS 仅 Host smoke 的 HOST-T-015 失败（12 passed、1 failed、0 skipped，`Expected element to exist: body-map.next Button`，exit 65）。CI 缺 artifact/accessibility hierarchy，选择状态与 AX 投影根因均未知。当前工作树已实现 sibling footer 的底部独立、非滚动安全内容布局区，先验证 `body-map.marker-count-summary` 为一项位置，再以 generic stable-ID any-element 查询验证 CTA 存在、可点击并触发；不得要求具体 `safeAreaInset` API 或 `Button` class。本地 iPhone 17 Pro / iOS 26.5 的 targeted HOST-T-015 + MoreSensations 为 2/0/0（138.1s），完整 internal Host script exit 0（426.285s）；远端尚未推送，远端 retry Pending | iOS + 无障碍 + QA | GATE-06 前 | 仅声称局部 UI smoke，不称无障碍通过 |
| HOST-OPEN-003 | 候选 3D 的跨 Simulator/Xcode 加载与回退 probe 稳定性；本地与单次远端重建已完成，但不替代资产或真机门禁 | iOS + 3D 资产 + QA | GATE-06 前 | 默认 UI smoke 强制 2D/列表；probe 仅显式开关、先确认 loader-entry 且两种终态都保持列表回退 |
| HOST-OPEN-004 | Xcode project 的 CI macOS/Xcode 版本与 scheme 保持策略 | iOS + QA | 合并前 | 使用受版本控制 project/scheme 和当前 CI 的 Swift Package 基线 |

任一 Host 出现网络请求、权限请求、健康数据落盘、遥测上传、AI/行动内容伪装、2D/列表不可用或草稿无确认 reset，必须停止该内部路径并回退修复；不得以“仅 Simulator”豁免。

## 8. 变更记录

| 日期 | 变更 | 说明 |
|---|---|---|
| 2026-08-09 | 新建 FEAT-IOS-P0-RUNTIME-01 | 以受版本控制的内部 App Host 解除 Swift Package 无 `.app` 的 Simulator 运行证据缺口，不增加产品健康语义。 |
| 2026-08-09 | 0.2.0 | `BodyCompanionInternal` App target、共享 scheme、静态边界扫描、7 项本地 UI smoke 与远端 CI 均已通过；证据见 EVIDENCE-01/EVIDENCE-DEVICE-01，真机与发布门禁保持打开。 |
| 2026-08-09 | 0.3.0 | 实现 `HOST-OPEN-003` 的本地候选 3D Simulator probe：每次请求有独立内存 attempt，先确认 loader-entry，再以 ready 或 fail-closed 回退保留列表路径；不改变候选资产状态或扩大 P0 能力。 |
| 2026-08-09 | 0.3.1 | `ea85c68` 的 CI run `31301067572` 成功重建候选 probe 所在完整 Host suite；远端只验证受控 probe 的成功终态集合，不升级资产、真机、性能、碰撞、无障碍或发布结论。 |
| 2026-08-09 | 0.3.2 | `7d8bf59` 为 HOST-AC-008/HOST-T-015 增加本地 accessibility-size 结构 smoke；当时只验证指定合成路径的纵向与可达布局，远端 CI 结果尚待运行（后续结果见 0.3.3），未关闭无障碍或设备门禁。 |
| 2026-08-09 | 0.3.3 | 首次远端 run `31311301360` 在 iPhone 16 / iOS Simulator 18.5 只有 HOST-T-015 失败（exit 65），后端/契约、Swift 94、SDK build 和 Host 静态边界均成功。`7e64833` 只稳定 HOST-T-015 自动化见证；其本地 iPhone 17 Pro / iOS 26.5 复测通过，后续远端结果见 0.3.4，未关闭无障碍或设备门禁。 |
| 2026-08-09 | 0.3.4 | `7e64833` 的第二次远端 run `31312416395` 仍只失败于 HOST-T-015（exit 65）；iPhone 16 / iOS Simulator 18.5 / Xcode 16.4 中为 12 passed、1 failed、0 skipped，未找到 `body-map.next` Button。`e0f1089` 只将断言移至文字部位 Sheet 关闭后；本地完整 Host suite 与单独 HOST-T-015 通过，远端 retry pending，未关闭无障碍或设备门禁。 |
| 2026-08-09 | 0.3.5 | pushed SHA `306f2b91` 的第三次远端 run `31313515662` 仍只失败于 HOST-T-015（exit 65）；iPhone 16 / iOS Simulator 18.5 / Xcode 16.4 中为 12 passed、1 failed、0 skipped，未找到静态文案“已添加待确认位置：左膝附近”。测试专用修复 `0ed0563` 不再依赖该短暂选择反馈，先验证无并存 `MarkEditor`、完成/关闭文字部位 Sheet 后检查 `body-map.next`，并同样加固 `selectBoth`；本地完整 Host suite、单独 HOST-T-015 与 Swift Core 94/94 通过，远端 retry 尚未推送，未关闭无障碍或设备门禁。 |
| 2026-08-09 | 0.3.6 | 澄清 HOST-AC-008：今天的两张情境卡是单一合并的非动作展示信息，不是 P0 点击入口；accessibility-size smoke 在内容滚动后只验证其独立 stable ID 与 vertical 布局分支 identifier，且所有布局容器不得覆盖子卡片或子动作 ID，不用 `isHittable` 伪造展示动作验收。该布局 identifier 不是 VoiceOver 结论。结构化动作与地图继续动作仍必须可点击。该澄清不改变健康、API、网络、持久化、安全或 AI 行为；本版本执行收据待后续验证归档。 |
| 2026-08-09 | 0.3.7 | 归档 SHA `98a4200` 的第四次远端 run `31314859140`：iPhone 16 / iOS Simulator 18.5 / Xcode 16.4 的 Host smoke 为 12 passed、1 failed、0 skipped；唯一 HOST-T-015 失败是文字部位 Sheet 关闭后 `body-map.next` 已存在但不可点击，Backend and contracts、Swift 94、SDK build 与 Host 静态边界均成功。后续当前工作树把继续动作固定在 bottom safe-area，并保留展示性情境卡/子动作 identifier；在最后的 Today 强制内容滚动与 type-agnostic intake 查询小改后，当前版本本地复测与远端 retry 均待执行。该状态不关闭无障碍或设备门禁。 |
| 2026-08-09 | 0.3.8 | 归档当前工作树的 safe-area map footer、identifier 保留、Today 内容滚动与 type-agnostic intake 查询修复；最后新增两条“情境卡为非操作元素”UI 断言后，iPhone 17 Pro / iOS 26.5 的 XcodeBuildMCP 定向 HOST-T-015 为 1 passed、0 failed、0 skipped（86.0s）。完整 `run_internal_ios_host_tests.sh` 已在该微调后 exit 0（402.313s；脚本安静输出，不记录精确 XCTest 数）；远端 retry 尚未推送。这些仍只是内部 Simulator 局部回归，不关闭无障碍、真机或设备门禁。 |
| 2026-08-09 | 0.3.9 | 归档 SHA `544c39a` 的 run `31318855810`：Backend and contracts 成功，iOS 仅 internal Host smoke 失败（12 passed、1 failed、0 skipped）；HOST-T-015 报 `Expected element to exist: body-map.next Button`（exit 65）。CI 未上传 artifact/accessibility hierarchy，不能在选择未保留与 AX 投影/元素类型之间归因。将下一次修复规格收敛为底部独立、非滚动的安全内容布局区；文字选择后先验证 `body-map.marker-count-summary` 的一项位置，CTA 再以 stable-id any-element 查询验证存在、`isHittable` 与 `tap`，不以 `safeAreaInset` 或 `Button` class 为跨 OS 契约。新实现、本地复测和下一次远端 retry 均 Pending，不关闭无障碍或设备门禁。 |
| 2026-08-09 | 0.3.10 | 当前工作树已实现 sibling footer 的独立非滚动安全内容区、文字选择后的 marker-count 一项位置断言，以及 generic stable-ID any-element CTA exists/hittable/tap 验收；具体 `safeAreaInset` API 与 `Button` class 仍不构成跨 OS 条件。随后收据见 0.3.11；该状态不关闭无障碍、真机或设备门禁。 |
| 2026-08-09 | 0.3.11 | 当前工作树在 iPhone 17 Pro / iOS 26.5 的 targeted HOST-T-015 + MoreSensations 为 2 passed、0 failed、0 skipped（138.1s），完整 internal Host script exit 0（426.285s）。远端尚未推送、远端重试 Pending；该收据仅限内部 Simulator，不关闭无障碍、真机或设备门禁。 |
