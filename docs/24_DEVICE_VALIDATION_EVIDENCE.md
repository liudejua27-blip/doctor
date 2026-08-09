# EVIDENCE-DEVICE-01：iOS 真机、无障碍、3D 性能与候选资产审核

| 属性 | 值 |
|---|---|
| 文档 ID | EVIDENCE-DEVICE-01 |
| 版本 | 1.5.9 |
| 状态 | Internal Simulator Host smoke passed; physical device and production 3D validation blocked |
| 执行日期 | 2026-08-08（设备尝试）；2026-08-09（Host 基线、候选 probe、文字部位切片、完整感觉切片、accessibility-size 结构切片与远端 CI 重建） |
| 对应 Git | `5dddd83602d0922bf78069dd6fdeaa5e5b5a5a5a`（内部 Host 基线；远端 CI run `31295533318` 已成功）；`79f1f36`（候选 3D 运行时防护）；`ea85c68`（证据提交；远端 CI run `31301067572` 已成功）；`9fc54d4`（文字部位 Area-only 修复；run `31303340128` 已成功）；`0105cd7`（完整感觉与感觉修订安全边界；run `31307042209` 已成功）；`7d8bf59`（P0 accessibility-size 结构优化；run `31311301360` 仅 HOST-T-015 failed）；`7e64833`（首个 HOST-T-015 自动化稳定性修复；run `31312416395` 仍仅 HOST-T-015 failed）；`e0f1089`（文字部位 Sheet 关闭后再断言 `body-map.next`；pushed SHA `306f2b91` 的 run `31313515662` 仍仅 HOST-T-015 failed）；`0ed0563`（第三次测试专用修复）；SHA `98a4200` 的 run `31314859140`（第四次仍仅 HOST-T-015 failed）；当前 safe-area CTA / identifier 保留修复尚未提交或推送 |
| 适用测试计划 | [TEST-BODY-MAP-V2](23_REHABMATE_NATIVE_PARITY_TEST_PLAN.md)、[TEST-BODY-MAP-V1](20_BODY_MAP_TEST_PLAN.md) |
| 资产记录 | [BODY-ASSET-01](21_BODY_ASSET_PROVENANCE.md)、[ADR-0018](decisions/ADR-0018-body-asset-manifest-runtime-gate.md) |

## 1. 结论先行

本次形成了受版本控制的内部 Simulator App Host 证据，但仍无法形成“真机通过”证据，原因是：

1. `5dddd83` 已提供 `BodyCompanionInternal.xcodeproj`、iOS App scheme 和 UI test target；它只使用 placeholder Bundle ID、禁用签名、无 entitlements，属于内部 Simulator Host，不能安装到真机。
2. `xcrun xctrace list devices` 与 `xcrun devicectl list devices` 均显示已登记的两部 iPhone 为 Offline/unavailable；没有已连接且已信任的设备可安装和运行。
3. `5dddd83` 的历史基线已在 booted iPhone 17 Pro / iOS 26.5 执行 7 项 UI smoke；远端 CI 在 iPhone 16 / iOS 18.5 成功运行同一脚本。两者都是 Simulator，不能外推为真机。
4. `79f1f36` 在本地同一 iPhone 17 Pro / iOS 26.5 完成 9 项 UI 测试；候选 probe 先观察当前 Scene 的 loader-entry，再实际出现 candidate-ready、3D 场景和列表入口。`ea85c68` 的远端 run `31301067572` 成功执行完整 Host suite；CI 日志确认 probe 成功，但不单独记录 ready/fallback 分支。它未点击人体，未测试碰撞、区域映射或性能。
5. `9fc54d4` 在同一 Simulator 完成 10 项 UI 流程与 87 项 Swift Core：共享文字入口可搜索本地中英文目录，选择后只创建待确认的宽泛 Area/Zone；无结果不写草稿；即使图形模式为 Pin 也不产生精确 Point。它同样不构成 VoiceOver、真实设备或网格命中证据。
6. `0105cd7` 在同一 Simulator 完成 12 项 UI 流程与 94 项 Swift Core：可展开“更多感觉（22 项）”并选中“麻木”，两位置时区分局部和全组 unknown；这些都只形成未确认的显式位置关联草稿。run `31307042209` 已在 iPhone 16 / iOS Simulator 18.5 成功重建 Swift 94、SDK build、Host boundary 与 internal Host smoke（Host smoke 09:55:37–10:04:42 UTC）。它同样不构成 VoiceOver、Dynamic Type、Reduce Motion、真实设备、碰撞、性能或资产审核证据。
7. `7d8bf59` 在本地 iPhone 17 Pro Max / iOS 26.5 完成 13 项 UI 流程与 94 项 Swift Core：HOST-T-015 只在 `UICTContentSizeCategoryAccessibilityXXXL` 下验证文字部位 Sheet、今天页两张展示性情境卡的稳定 ID/纵向分支和结构化页成对动作的局部结构。前三次远端失败历史保持不变；最新 SHA `98a4200` 的 run `31314859140` 是第四次仅 HOST-T-015 failed：iPhone 16 / iOS Simulator 18.5 / Xcode 16.4，Host smoke 12 passed、1 failed、0 skipped，文字部位 Sheet 关闭后 `body-map.next` 已存在但不可点击；Backend and contracts、Swift 94、iPhoneOS SDK build 与 Host 静态边界均成功。当前工作树将已有位置后的地图继续动作固定在 bottom safe-area，保留展示卡和子动作各自的 identifier，并加入 Today 内容滚动与 type-agnostic intake 查询；最后新增两条“情境卡为非操作元素”UI 断言后，iPhone 17 Pro / iOS 26.5 的定向 HOST-T-015 为 1 passed、0 failed、0 skipped（86.0s）。完整 Host 脚本已在该微调后 exit 0（402.313s；脚本安静输出，不记录精确 XCTest 数），远端 retry 尚未推送。它不构成 VoiceOver、完整最大 Dynamic Type、深色/高对比度、Reduce Motion、真实设备、碰撞、性能或资产审核证据。

因此，Sheet、VoiceOver、Dynamic Type、Reduce Motion、3D 性能、RealityKit 碰撞命中和候选资产的生产批准均保持 **Pending/Blocked**。当前 safe-area CTA / identifier 保留修复已补充内部 Simulator 的定向与完整 Host script 收据，但远端 retry 尚未推送；它不关闭上述任一设备门禁。2D、部位列表和安全入口继续是唯一可外推的可用路径；候选 USDZ 继续为 `candidate`，不得发布。

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
| 本地 HOST-T-015 历史测试专用修复（`0ed0563`） | iPhone 17 Pro / iOS 26.5；不再依赖短暂选择反馈，先验证无并存 `MarkEditor`、完成/关闭文字部位 Sheet 后检查 `body-map.next`，并同样加固 `selectBoth`；完整 Internal Host suite、单独 HOST-T-015 与 Swift Core 94/94 通过 | 历史本地 Simulator 复测；后续 run `31314859140` 说明该断言修复本身未解决远端布局可点击性 |
| 当前 safe-area CTA / identifier 保留修复（未提交） | 将已有位置后的 `body-map.next` 固定至 bottom safe-area，且布局容器不覆盖展示性情境卡或子动作 ID；加入 Today 内容滚动与 type-agnostic intake 查询。最后新增两条“情境卡为非操作元素”UI 断言后，iPhone 17 Pro / iOS 26.5 的 XcodeBuildMCP 定向 HOST-T-015：1 passed、0 failed、0 skipped，86.0s；`BODY_COMPANION_SIMULATOR_UDID=68F37251-71BE-4F42-9849-62D61BFFE7C3 bash scripts/run_internal_ios_host_tests.sh` 已在该微调后 exit 0（402.313s；脚本安静输出，不记录精确 XCTest 数） | 只证明当前本地内部 Simulator 的局部定向回归；修复尚未推送，不能证明远端 retry、VoiceOver、完整 Dynamic Type、真机或资产质量 |
| GitHub Actions run `31295533318` | macOS runner 的 iPhone 16 / iOS 18.5 成功执行 `scripts/run_internal_ios_host_tests.sh`；iOS job 总时长 7m11s | 云端 Simulator 可重建；不是物理 iPhone 或签名证据 |
| GitHub Actions run `31301067572` | `ea85c68` 的 macOS runner / iPhone 16 / iOS 18.5 成功执行 Swift 83 项、iPhoneOS build、Host 静态边界检查和完整 `scripts/run_internal_ios_host_tests.sh`；Host smoke 288 秒 | 当前候选 probe 的远端可重建性；测试只接受 ready 或候选专属 2D fallback，未记录分支作为资产质量结论 |
| GitHub Actions run `31303340128` | `9fc54d4` 的 Backend and contracts 成功（20 秒）；iOS package and internal host 成功（8m28s），包括 Swift tests、iPhoneOS SDK build、Host boundary 与 internal Host smoke | 云端 Simulator 可重建当前文字部位切片；不是物理 iPhone、真实 VoiceOver、性能或签名证据 |
| GitHub Actions run `31307042209` | `0105cd7` 的 Backend and contracts 成功；iOS package and internal host 在 iPhone 16 / iOS Simulator 18.5 成功执行 Swift 94、iPhoneOS SDK build、Host boundary 与 internal Host smoke（Host smoke 09:55:37–10:04:42 UTC） | 云端 Simulator 可重建当前完整感觉/感觉修订边界；不是物理 iPhone、真实 VoiceOver、性能、碰撞或签名证据 |
| Swift iPhoneOS build | `BodyCompanionIOS` target 成功 | 只证明 iOS SDK 编译 |
| Swift iPhoneSimulator build | `BodyCompanionIOS` target 成功 | 只证明 Simulator SDK 编译 |
| Swift Core tests | `5dddd83` 的历史 Host 收据为 `80 tests, 0 failures`；`9fc54d4` 的历史 Area-only 收据为 `87 tests, 0 failures`；`0105cd7` 当前 checkout 已在本轮 `swift test` 复验为 `94 tests, 0 failures`，新增完整感觉目录、显式 marker 关联、unknown 边界和感觉修订安全回归 | 只证明状态/契约，不证明 UI/设备 |

运行时前置条件缺失时，不能使用临时 `swift run`、macOS prototype 或无签名的 library 产物替代 iOS App 安装测试。

## 3. 维度结果矩阵

| 维度 | 结果 | 已有静态/代码证据 | 真机关闭条件 |
|---|---|---|---|
| Sheet | **Simulator smoke passed / device blocked** | 紧凑宽度通过系统 `.sheet`、`.medium/.large` detents、drag indicator 和 `ScrollView` 承载**位置 Inspector**；UI smoke 打开列表/编辑器并通过显式“完成”返回；删除后状态会由模型清理 | 在 iPhone 上验证首次选择、再次选择、切换标记、删除、旋转和系统返回；确认 Sheet 不遮挡继续入口、焦点不丢失 |
| VoiceOver | **Blocked** | 2D 有部位列表等价路径；主要按钮有 label/hint；3D 仅提供整体语义说明并保留 2D/列表回退 | 开启 VoiceOver，从 Today → 记录 → 2D/列表 → 位置 Inspector → 结构化描述 → 删除 → 继续全程完成；验证提示、计数、结构化程度控件、回退公告和导航顺序 |
| Dynamic Type | **Simulator structural smoke passed / device blocked** | 使用 `.body/.headline/.caption/.footnote` 等语义字体；`7d8bf59` 在 `UICTContentSizeCategoryAccessibilityXXXL` 下验证指定文字部位 Sheet、两张展示性情境卡和两组结构化成对动作的局部结构。最新第四次远端 HOST-T-015（run `31314859140`）仍失败：`body-map.next` 存在但不可点击。最后新增两条“情境卡为非操作元素”UI 断言后的当前修复在 iPhone 17 Pro / iOS 26.5 的定向 HOST-T-015 通过（1/0/0，86.0s）；完整 Host 脚本已在该微调后 exit 0（402.313s；脚本安静输出，不记录精确 XCTest 数），远端 retry 尚未推送 | 最大可访问字号和横屏下不截断标题、位置摘要、提示、结构化程度控件和按钮；确认 Sheet 可滚动且关键操作仍可达 |
| Reduce Motion | **Blocked** | 主题按钮的按压缩放使用 `.animation`，但在 `accessibilityReduceMotion` 时显式置为 `nil`；视角切换代码是直接 `look(at:from:)`，未发现持续旋转 | 开启 Reduce Motion，重复 front/back/left/right/top、焦点和 Sheet 展开；确认无不必要动画、闪烁或自动旋转，手势仍可用 |
| 3D 性能 | **Blocked** | USDZ 约 606 KB、manifest LOD 三角面 22,804；默认 UI smoke 强制禁用候选 3D，专用 probe 显式开启后仅观察 loader-entry 与 ready/回退终态；代码在加载时同步 `ModelEntity.loadModel` 和 `generateCollisionShapes(recursive:)` | 最低支持 iPhone 冷启动、首次交互、连续旋转/缩放 5 分钟；采集冷启动、P95 命中、FPS、内存、热状态和崩溃 |
| 碰撞命中 | **Blocked** | 使用 `hitTest(.nearest, mask: .all)`；先识别 `marker_`，再向父链解析 `body_`；保存 root-local position/normal | 真机逐区域黄金点、边界点、遮挡点和已有 Marker 重叠点；验证命中延迟、误落点、Marker 优先级和 2D 回退 |
| 候选资产生产审核 | **Candidate only / blocked by gate** | ZIP 无损、`usdchecker` Success、SHA 与清单一致；清单仍为 candidate/unverified/anatomy pending/performance pending/商业与 App Store false | 作者链/许可证、法务署名、解剖语义、区域图/碰撞、坐标迁移、真机性能、无障碍、签名读回全部通过后才可申请 approved |

## 4. 本次静态审核发现

这些是生产门禁问题，不因“无法连接设备”而自动通过：

| ID | 严重度 | 发现 | 处理要求 |
|---|---|---|---|
| DEVICE-FINDING-001 | P0 | 无 App target 的 Simulator 阻塞已由 `5dddd83` 解除；仍没有受真实 Team/Bundle ID/证书支持的签名 App target，无法安装、切换真实设备辅助功能设置或采集设备性能 | 由具名 iOS/安全负责人提供正式 Bundle ID、Team/证书、必要 entitlements 与真机 scheme；完成后重跑本记录 |
| DEVICE-FINDING-002 | P1 | RealityKit 命中使用 `.all`，未实现 BODY-01 要求的人体/Marker/覆盖层 CollisionGroup 分离 | 增加独立 collision groups/masks，并用真机黄金点证明 Marker 优先与命中边界；不能以最近实体或 mask 全开替代 |
| DEVICE-FINDING-003 | P1 | `BodyHitEvidence` 当前没有从 `hitTest` 读取 triangle index/barycentric；候选代码只传 local position/normal | 建立受测的三角/重心或离线表面解析路径；若系统能力不足必须记录 fallback/候选确认，不得伪造精确点 |
| DEVICE-FINDING-004 | P1 | 候选 USDZ 没有 `body_lower_back` 实体；解析器会把躯干实体映射为 `body.torso.general`，不能证明下背区域命中 | 在资产 region map 中补齐或明确“躯干宽泛候选”，完成解剖/视觉审核和边界黄金集；禁止静默声称下背命中 |
| DEVICE-FINDING-005 | P1 | USD 根层包含 `xformOp:rotateXYZ = (-90, 0, 0)`，而 manifest `canonical_transform` 为 identity | 由资产负责人核对导出变换、根原点、前后/左右方向并更新不可变 manifest/迁移证据；真机命中前不得批准 |
| DEVICE-FINDING-006 | P1 | manifest `performance.status=pending` 且冷启动/P95/FPS/内存均为 0；代码没有 FPS/内存/signpost 采集 | 在目标 iPhone 上建立不含健康正文的性能采集和阈值评审；未测量不能改为 passed |
| DEVICE-FINDING-007 | P2 | 2026-08-09 已从 `MarkEditor` 移除程度 Slider；结构化 `SignalIntakeScreen` 的程度控件虽有可见“程度”标签与 accessibility value，仍未经过真机 VoiceOver/最大 Dynamic Type 验证。第四次远端 HOST-T-015（run `31314859140`）仍失败：文字部位 Sheet 关闭后 `body-map.next` 存在但不可点击。当前 safe-area CTA / identifier 保留修复在 Today 内容滚动与 type-agnostic intake 查询后，最后新增两条“情境卡为非操作元素”UI 断言；其本地定向 HOST-T-015 已通过（1/0/0，86.0s），完整 Host 脚本已在该微调后 exit 0（402.313s；脚本安静输出，不记录精确 XCTest 数）；远端 retry 尚未推送。位置摘要、完整页面、深色/高对比度和横屏仍未经过设备验证。 | 真机 VoiceOver/Dynamic Type 验证结构化程度控件；必要时取消摘要硬截断，并保留部位列表等价路径。 |

## 5. 候选资产审核读回

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

本轮决定：**记录历史基础 `Simulator host smoke passed`、`79f1f36` 的本地候选 loader lifecycle probe passed、`ea85c68` / run `31301067572` 的远端完整 Host smoke passed，以及 `9fc54d4` 的本地文字部位 Area-only Simulator flow 与 run `31303340128` 的远端 Simulator 重建成功；另记录 `0105cd7` 的本地完整感觉/感觉修订安全边界 Simulator flow 及 run `31307042209` 的远端重建成功。最新远端 run `31314859140`（SHA `98a4200`）仍仅 HOST-T-015 failed：12 passed、1 failed、0 skipped，文字部位 Sheet 关闭后 `body-map.next` 存在但不可点击。当前 safe-area CTA / identifier 保留修复在最后新增两条“情境卡为非操作元素”UI 断言后，已在本地 iPhone 17 Pro / iOS 26.5 通过定向 HOST-T-015（1/0/0，86.0s）；完整 Host 脚本已在该微调后 exit 0（402.313s；脚本安静输出，不记录精确 XCTest 数），尚未推送或得到远端终态。** 不批准生产 3D，不声称真机通过或无障碍通过，不关闭 GATE-06/GATE-07/GATE-08。设备和正式 App target 到位前，生产路径保持 2D/列表 fail-closed；候选资产和 3D loader 仅限内部 prototype flag。
