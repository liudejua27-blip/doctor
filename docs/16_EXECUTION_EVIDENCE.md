# EVIDENCE-01 当前工程验证快照

| 属性 | 值 |
|---|---|
| 文档 ID | EVIDENCE-01 |
| 版本 | 2.14.0 |
| 状态 | Current local snapshot / Prototype-only |
| 工作区 | `/Users/liuchongjiang/Documents/3D人体` |
| 快照日期 | 2026-08-13 |
| 对应 Git | `codex/body-signal-intake-boundaries`；本轮为保留既有用户改动之上的未提交工作树，尚无可引用 commit/远端 CI 收据；历史提交与失败 run 保留 |
| 本轮变更状态 | FEAT-TRUSTED-COMPANION-01 已形成内部本地实现：后端 204/204、Swift 103/103、generic iPhoneOS build、Host 静态检查、候选资源 AppHost 隔离、baseline/diff、render/collision USDZ ARKit/跨层身份校验均通过；Simulator smoke 收据仍只代表受控内部路径。它仍不构成真机、完整辅助功能、真实 Provider/认证/数据库、临床、法务、资产发布或生产批准 |
| **2026-08-13 当前收据** | `baseline_checks=passed markdown_files=65 checked_links=404 json_schemas=18 ... prohibited_source_matches=0`；Backend 204/204；Swift 103/103；`check_body_asset_release.py` 读回 30 render Mesh / 24,020 render triangles / 1,904 collision triangles / 2 个 64-byte aligned USDZ ZIP entries，manifest self-hash/离线签名 verified；候选资产仍为 candidate/fail-closed |

## 1. 证据解释

本文件只保留当前可复现结果，不再累计每个临时切片的重复流水账。已实现边界见 [BASELINE-01](18_IMPLEMENTED_PROTOTYPE_BASELINE.md)，需求到证据关系见 [TRACE-01](14_TRACEABILITY_MATRIX.md)，发布门禁见 [REL-01](13_DELIVERY_ROADMAP.md)。

> **2026-08-10 remote compatibility receipt.** SHA `9b6e10a` / run `31348638741` 在远端 Xcode 16.4 的 UI test 编译阶段失败：`XCTIssue.isFailure` 在该 XCTest SDK 不可用，0 个 UI test 执行；Backend/contracts、Swift、SDK 与 Host boundary 均已通过。失败诊断 artifact 已上传但没有测试附件；当前兼容性修复改用跨版本 `XCTIssue.type == .assertionFailure`，待提交、推送与重试。该事件不改变 Simulator-only、无障碍、真机或生产门禁边界。

历史 iOS Host 基线绑定提交 `5dddd83`：本地 iPhone 17 Pro Simulator 与远端 CI iPhone 16 Simulator 均已重建。当前候选 3D 运行时防护绑定 `79f1f36`，本地专用 probe 的证据提交 `ea85c68` 已由远端 CI run `31301067572` 成功重建。进入外测前仍必须由受保护提交、SafetyBaseline、真实设备和所有发布门禁另行验证。

## 2. 当前验证结果

| ID | 检查 | 当前结果 | 证明范围 |
|---|---|---|---|
| EV-CURRENT-001 | `scripts/check_baseline.py` | `passed; markdown_files=65 checked_links=404 json_schemas=18 openapi_paths=36 openapi_schemas=111 asset_manifests=1 prohibited_source_matches=0` | 文档、契约清单、CI Action SHA/权限、依赖 pin、资产清单/Bundle SHA、退役路径和禁止源码引用的本地静态门禁；`.pytest_cache` 等临时目录不计入工程文档清单 |
| EV-CURRENT-002 | P2A 聚焦回归 | `19 passed` | 默认时钟被 fixture 冻结；显式过期路径仍可测试 |
| EV-CURRENT-003 | Python 编译与依赖 | `compileall` 通过；`pip check` 无破损依赖 | Python 3.11 当前约束环境可导入；不证明其他平台/版本 |
| EV-CURRENT-004 | `cd ios/BodyCompanion && swift test` | `103 tests, 0 failures` | Swift Core 样机；新增 2D Zone=Area、Pin=Point、surface 身份、3D triangle/barycentric/UV、region-map confidence、3D ready 看门狗、approved 资产独立产物门禁等回归；不证明真机/签名/生产资产、临床规则或服务端 retained action |
| EV-CURRENT-005 | `./.venv311/bin/python -m pytest backend/tests --tb=short` | `204 passed` | 后端合成/内存样机全量绿色；非布尔目录控制、损坏规则/伪造 hit/matched 空证据整体 fail-closed，R0/R1 最高风险行动不被低优先级 undetermined 覆盖，Agent 调用为 0；不证明真实 Provider、生产规则、认证或数据库 |
| EV-CURRENT-006 | 退役文档/旧链接/旧过程 OPEN ID 扫描 | `retired_slice_files=0 stale_retired_links=0 stale_open_process_ids=0` | 32 份过程文档已删除，非归并登记处不存在旧路径或旧门禁引用 |
| EV-CURRENT-007 | RehabMate 禁止生产实现扫描 | `0 matches` | iOS/后端源码未出现被禁止的 Web/算法/资产关键词；不替代许可证人工审计 |
| EV-CURRENT-008 | iOS SDK target build | `swift build --sdk $(xcrun --sdk iphoneos --show-sdk-path) --triple arm64-apple-ios17.0 --target BodyCompanionIOS` 构建通过；generic prototype build 亦通过 | 只证明 Swift Package/RealityKit 适配器编译，不证明签名安装/真机运行 |
| EV-CURRENT-009 | `.github/workflows/ci.yml` | Ubuntu 24.04 后端/契约 + macOS 15 iOS；官方 Action 固定完整 SHA；iOS job 含 Host 静态扫描与 Simulator smoke | `4cc46e2` / run `31350639359` 的 Backend/contracts、Swift 94/94、iPhoneOS SDK build、Host boundary 与 internal Host smoke 全部成功；CI 目的地为 iPhone 16 / iOS Simulator 18.5 / Xcode 16.4。Smoke 成功日志不提供精确 XCTest 数；本地 targeted/full 收据见 EV-CURRENT-018。历史失败 run 保留，不外推为真机或生产通过 |
| EV-CURRENT-010 | BODY-ASSET-01 候选资产 | 1.2.0 / topology-v2；render SHA-256 `3120c9de64d26c98aed073776107e154c0450b52d7e289aa61fa6dc63fc45d5f`、collision SHA-256 `54bc86d6466de1a4acef43a2b1bc526a9ddcb2431d1b96cfe4a0cf742ab49176`；render 600,103 bytes / 24,020 triangles，collision 1,904 triangles；连续三次 render 生成 SHA 一致；`usdchecker --arkit` Success；Y-up/米制/identity root/groundY=0/height=1.86m，30 个实际 render `body_*` ModelEntity 含 `body_lower_back`；离线 manifest 签名 verified | 证明固定工具链下 render/collision 容器对齐、确定性、清单/Bundle/Swift/USD 身份、collision face range、region map/correspondence schema 与资源隔离；仍是分段 candidate，未解剖/法务/性能/真机审核，不能发布 |
| EV-CURRENT-011 | 默认分支保护 | GitHub API 读回成功：`Backend and contracts`、`iOS Swift package` 为必需检查；strict=true、管理员强制、线性历史开启、禁止强推/删除；PR #1 与 PR #4 已合并 | 证明远端设置和两次 PR 合并路径；不证明所有后续变更或发布门禁自动安全 |
| EV-CURRENT-012 | FEAT-BODY-MAP-V2 上游行为基线 | RehabMate commit `1378a752dfb0d656a27a73c234269f9f5be2c3ca`、代码 MIT、上游 `body.glb` Git blob SHA-1 `adbf4de165f5698b770e36d33fa953a2210f968c` 和 raw SHA-256 `ffd98cc59f128d1c162e1d63af905e4f459b6e18618a7c853b1cbe8a43cf0ce2` 已记录；内置浏览器打开成品站超时 | 证明源审计锚点和采用边界；不证明成品站视觉加载或生产资产权利 |
| EV-CURRENT-013 | FEAT-BODY-MAP-V2.1 窄屏编辑与反馈 | `swift test --parallel`：`64 tests, 0 failures`；iOS SDK target 构建通过；窄屏编辑器使用系统 Sheet/Detent，Pin 上限和 3D 回退使用固定文本提示；不证明真机 Sheet/VoiceOver/动态字体行为 | 证明代码和 Core 回归已覆盖 V2.1 逻辑；设备、无障碍和生产门禁仍未关闭 |
| EV-CURRENT-014 | EVIDENCE-DEVICE-01 真机与候选资产审核 | 历史 `5dddd83` 已解除“无 Simulator App target”阻塞：本地 iPhone 17 Pro / iOS 26.5 的 7 项 UI smoke 与远端 iPhone 16 / iOS 18.5 的同一脚本均成功。`79f1f36` 在本地 iPhone 17 Pro / iOS 26.5 运行 9 项 UI 测试，专用 probe 实际观察到当前 Scene 的 loader-entry，随后进入 candidate-ready，并保留 3D 场景与列表入口；`ea85c68` 的远端 run `31301067572` 成功运行同一完整 Host suite。当前 1.2.0 已修复旧版 lower_back/根变换，iOS 18 代码已实现独立 collision group、triangle+barycentric、region map/surface correspondence；这些只有静态/Core/Simulator 证据。两部登记 iPhone 仍 Offline/unavailable；当前未关闭的是真机 faceIndex 黄金集、真实性能/无障碍、解剖/权利和生产批准 | 证明 Simulator Host 与一次内部候选加载生命周期及其远端可重建性；不证明 Sheet 的真机体验、VoiceOver、Dynamic Type、Reduce Motion、3D FPS/内存、碰撞黄金集、签名或生产批准；详见 [`EVIDENCE-DEVICE-01`](24_DEVICE_VALIDATION_EVIDENCE.md) |
| EV-CURRENT-015 | P0 明亮中文体验壳与录入完整性 | `9fc54d4` 的 Area-only 文字部位收据仍保留。`0105cd7` 在本地完成 94 项 Swift Core、iPhoneOS SDK build、静态 Host 检查和 iPhone 17 Pro / iOS 26.5 的 12 项 Internal Host UI 流程：结构化页可展开“更多感觉（22 项）”并选中“麻木”，仅形成带显式位置关联的未确认草稿；多位置分别显示“部分位置的感觉说不清”和“这些位置的感觉都说不清”。普通本地安全状态的语义感觉修订会撤销旧安全、普通 Agent 与审批下游资格；高风险安全行动中控件禁用并由 Core 拒绝直接修订。没有新增 API/Schema/健康字段、网络、Provider、资料读取、行动建议、持久化或正式写入 | 证明 P0 路由、未确认草稿、感觉目录入口和该感觉修订安全边界的内部本地回归；不证明 P0 视觉可用性、VoiceOver、Dynamic Type、Reduce Motion、签名安装、真机 3D、真实 AI、临床安全或高风险非感觉事实修订 |
| EV-CURRENT-016 | 内部 iOS App Host | `xcodebuild -list` 发现 App target、UI test target 与共享 scheme；`check_internal_ios_host.py` 通过；`0105cd7` 本地 `bash scripts/run_internal_ios_host_tests.sh` 在 iPhone 17 Pro / iOS 26.5 产生 `12 passed, 0 failures`，覆盖 HOST-T-001～014。HOST-T-014 使用稳定 identifier 展开“更多感觉”，以原生 Toggle 选中“麻木”，并验证两位置的局部 unknown 与全组 unknown 文案互不重复；不点击人体。远端 run `31307042209` 亦成功完成 Backend and contracts，以及 iPhone 16 / iOS Simulator 18.5 上的 Swift 94、iPhoneOS SDK build、Host boundary 与 internal Host smoke。历史远端 run `31295533318`、`31301067572` 与 `31303340128` 的成功记录保留 | 只证明无网络/Provider/权限/持久化/遥测入口的内部 Simulator UI smoke；不证明系统权限弹窗、网络抓包、真机、VoiceOver、Dynamic Type、Reduce Motion、性能、碰撞、资产许可或发布 |
| EV-CURRENT-017 | P0 accessibility-size 结构回归 | `7d8bf59` 的局部 accessibility-size 结构历史收据保留；后续 selector 与 bounded-scroll 修复已在 `4cc46e2` 合入。最新远端 run `31350639359` 全部成功；本地 targeted H015 1/0/0（77.241s）、多位置 unknown 1/0/0（49.167s），full Host exit 0（446.330s） | 只证明受控 Simulator 的局部结构化自动化；不证明 VoiceOver、完整 Dynamic Type、横屏、Switch Control、实际深色/高对比度、Reduce Motion、真机、3D 性能/碰撞、资产许可、签名或发布 |
| EV-CURRENT-018 | `4cc46e2` accessibility host selectors 与 CI 重建 | 最新远端 run `31350639359`：Backend/contracts、Swift 94/94、iPhoneOS SDK build、Host boundary、internal Host smoke 全成功；CI 目的地 iPhone 16 / iOS 18.5 / Xcode 16.4。成功 smoke 脚本只输出 `Testing started`，不提供精确 XCTest 数。本地 iPhone 17 Pro / iOS 26.5 targeted H015 1/0/0（77.241s）、多位置 unknown 1/0/0（49.167s），full Host script exit 0（446.330s） | 当前内部 Simulator Host 与跨版本 selector/scroll 行为已重建；不证明真机、VoiceOver、完整 Dynamic Type、Reduce Motion、暗色/高对比度、3D 性能/碰撞、资产许可、签名、临床或生产通过 |
| EV-CURRENT-019 | FEAT-TRUSTED-COMPANION-01 本地整体验证 | generic iPhoneOS build exit 0；`check_internal_ios_host.py` 通过；候选 3D probe 进入 ready 后等待 8.5 秒仍保持 ready。加入该断言后的首次 full Host 仅 accessibility-size 场景偶发失败（471.327s）；该场景定向重跑 exit 0，最终 13 项 iPhone 17 Pro / iOS 26.5 Host smoke 全量复验 exit 0（461.853s） | 证明四根页入口、2D/列表、结构化草稿、草稿确认、局部 accessibility-size 结构和 candidate ready/fallback 的受控 Simulator 路径；不证明真实 3D 点击、真机、完整无障碍、性能、临床或发布 |
| EV-CURRENT-020 | `scripts/check_body_asset_release.py` 与 approved 负向门禁 | `body_asset_release_checks=passed asset=body-neutral-procedural-v1@1.2.0 sha256=3120c9de...45d5f meshes=30 render_triangles=24020 collision_triangles=1904 zip_entries=2`；manifest self-hash/离线签名 verified；只将当前清单改为 approved 时 JSON Schema 仍拒绝权利/审核/性能等缺口 | 绑定 render/collision Bundle/清单/Swift/USD identity、ARKit 容器、根/坐标、Mesh 集合、collision geometry digest、连续 region map、surface correspondence、camera preset、签名和 AppHost 资源隔离；不证明真机命中、解剖、性能、无障碍或发布批准 |

## 3. 当前已证明

- PydanticAI 使用固定公共发行版；确定性 SafetyEngine 位于普通 Agent 之前。
- Agent 输出保持强类型、未确认，工具读取受主体/scope/expiry/allowlist 约束。
- iOS Core 能表达规范位置、结构化身体信号、2D 回退、密文草稿和同步状态。
- 确认链在进程内/fake repository 中验证了 revision、前驱、摘要、幂等、有限写集和 read-back 关系。
- BodyAssetManifest metadata gate 会对未知、未批准、blocked/retired 或交叉约束不完整的资产回退 2D。
- 机器契约和当前测试代码仍保留；删除的是重复的过程性 Feature/Test 文档。
- P0 明亮中文体验壳已连接到既有 2D/3D 位置与未确认结构化草稿路径；地图只产生位置，感觉、程度和因素只能在结构化页填写；没有新增真实资料读取、行动建议或正式写入。
- R2 已在 Swift/Python 状态机和机器契约中抑制普通 Agent；多位置的感觉关联、结构化删除与草稿继续/新建均需要明确用户动作；位置变化会使本地 safety、普通 Agent 与审批阶段失效，避免复用旧结果。
- `0105cd7` 将感觉目录固定为常用 10 项与从同一稳定枚举派生的扩展 22 项；扩展选择、`other` 标签与感觉 unknown 都只写未确认草稿。对普通本地安全状态，语义感觉修订会使旧 safety/Agent/approval 失效；对 R0/R1/R2/`undetermined`/`safety_action`，直接本地感觉修订被拒绝。该修复不关闭 CONFLICT-004：位置、程度、时间、因素、功能影响和背景的高风险修订仍不能外部发布。
- 受版本控制的 `BodyCompanionInternal` 已可在本地和远端 Simulator 构建、安装、启动并通过历史 7 项基础 UI smoke；`9fc54d4` 的 10 项文字部位流程和 `0105cd7` 的 12 项完整 Host 流程均有本地证据，后者已由 run `31307042209` 的 iPhone 16 / iOS Simulator 18.5 重建。候选开关、网络/Provider、权限、持久化、遥测和正式档案能力均显式保持关闭。
- `7d8bf59` 为内部 Simulator 增加了 accessibility-size 下的结构回归；历史失败 run 保留。当前 `4cc46e2` / run `31350639359` 的远端 Host smoke 成功，本地 iPhone 17 Pro / iOS 26.5 targeted H015 1/0/0、多位置 unknown 1/0/0、full Host exit 0。所有记录都只证明指定合成路径的结构化自动化，不得写成完整 Dynamic Type、VoiceOver、深色/高对比度、Reduce Motion 或真机通过。
- 2026-08-13 的可信助手根页面把主动作、四步流程、进程内草稿、正式记录空态、AI readiness 和关闭能力分开呈现；普通聊天、正式档案和云端能力没有被视觉伪装成可用。
- SafetyEngine 对 unavailable/empty、重复规则 ID、hit 身份错配、matched 无 tier 和 evaluator 异常统一返回 unavailable/undetermined，丢弃部分结果且不调用普通 Agent；Agent metadata 不再携带伪隐私开关。
- 2D Zone 只产生 Area+region mask，Pin 才产生 point；surface 进入稳定身份。RealityKit triangle hit 转为三分量 barycentric，不再写成纹理 UV；位置/法线相对稳定语义实体，iOS 17 保留合法局部点回退。
- 1.2.0 资产生成/封装链已通过固定工具链的三次 SHA、64-byte alignment 和 `usdchecker --arkit`，但视觉几何仍是分段候选，不得描述成连续高质量或医学人体。

## 4. 已关闭项与剩余阻断

### CLOSED-EV-001 P2A 墙上时钟漂移

根因是 Session 使用固定 `2026-08-06` 创建，部分请求却回退到真实墙上时钟。现在 autouse fixture 冻结领域默认 `utc_now`，并新增省略请求 `now` 的回归；过期测试仍显式注入时间。P2A 19 个与后端全量 194 个测试均绿色。

### PARTIAL-EV-001 远端 CI 与保护分支

本地 `codex/` 分支、首个提交、Python 3.11 约束和 CI workflow 已建立；`origin` 已配置，PR #4 已合并到受保护默认分支提交 `2bb8e8a`，合并后两个 CI job 成功。`5dddd83` 的 run `31295533318` 还成功重建了新增的 iOS Host 任务；后续变更仍必须复用该 PR/required-check 路径。

### PARTIAL-EV-002 候选 3D 专用 Simulator probe

`79f1f36` 在本地 iPhone 17 Pro / iOS 26.5 完成 9 项内部 Host UI 测试：专用 probe 只设置候选开关，先读到当前 Scene 的 loader-entry，再实际进入 candidate-ready 并保留 3D 场景与部位列表；未点击网格，未生成 `BodyLocation` 或其他健康事实。证据提交 `ea85c68` 的远端 CI run `31301067572` 已成功重建完整 Host suite；CI 只验证可接受终态集合，未记录 ready/fallback 分支作为质量证据。无论本地或远端结果，都不构成候选资产、碰撞、性能、无障碍、签名、真机或生产批准。

### PARTIAL-EV-003 文字部位 Area-only Simulator 切片

`9fc54d4` 在本地 iPhone 17 Pro / iOS 26.5 完成 87 项 Swift Core 与 10 项 Internal Host UI 测试。文字入口只对本地静态目录做中文/英文匹配，当前视图先过滤；输入“膝”后选择“左膝附近”只会创建待确认的 `Zone + Area + body_part_search + region_mask_id`，即使图形模式为 Pin 也不产生 `anchor_2d.point`、`anchor_3d` 或顶层 `model_asset`（保留 2D 区域锚点所需的目录资产元数据）。无匹配结果不改变草稿；候选 ready 与专属 fallback 都保留同一文字入口。该切片没有读取网络、资料、历史或 Agent，没有持久化或创建正式档案。远端 run `31303340128` 已成功完成后端/契约与 iOS internal Host 验证；无论本地或远端结果如何，本条不构成 VoiceOver、Dynamic Type、Reduce Motion、真实 iPhone、碰撞/命中、性能、资产许可、签名或生产批准。

### PARTIAL-EV-004 完整感觉目录与感觉修订安全边界

`0105cd7` 在本地 iPhone 17 Pro / iOS 26.5 完成 94 项 Swift Core 与 12 项 Internal Host UI 流程，并通过 iPhoneOS SDK build 与 `check_internal_ios_host.py`。完整目录仍是既有 32 个稳定 code：首屏呈现常用 10 项，扩展 22 项由同一枚举派生；“更多感觉”选中“麻木”只形成未确认、显式 marker 关联的草稿。单位置不再同时提供重复的 unknown 初始入口；多位置区分局部和全组 unknown。按 CONFLICT-003，普通本地状态中的语义感觉变更会原子撤销旧 safety、普通 Agent 和审批下游资格，而 R0/R1/R2/`undetermined`/`safety_action` 则拒绝直接本地修订；no-op 不改变草稿。GitHub Actions run `31307042209` 已成功重建 Backend and contracts 与 iPhone 16 / iOS Simulator 18.5 的 Swift 94、SDK build、Host boundary 和 internal Host smoke。该切片不新增安全规则、医学结论、网络、Provider、资料读取、持久化或正式写入；也不关闭 CONFLICT-004 的高风险非感觉事实修订发布阻断。

### PARTIAL-EV-005 P0 accessibility-size 结构回归

`4cc46e2` 在本地 iPhone 17 Pro / iOS 26.5 完成 targeted H015 1/0/0、多位置 unknown 1/0/0、Swift Core 94/94、iPhoneOS SDK build、静态 Host 检查与 full Host script exit 0；远端 run `31350639359` 在 iPhone 16 / iOS Simulator 18.5 完成全部 CI Host 步骤。它没有查询或操作位置摘要、焦点/重置、3D 回退提示，也没有验证 VoiceOver、完整最大字号、横屏、Switch Control、实际深色/高对比度、Reduce Motion、真机、性能、碰撞、资产许可或签名。

### PARTIAL-EV-006 可信助手与候选 3D 1.2.0

2026-08-13 未提交工作树在本地完成 Backend 204/204、Swift 103/103、generic iPhoneOS build、Host 静态门禁、baseline/diff、AppHost 资源隔离和 USDZ ARKit/跨层身份校验。候选 render/collision/map/correspondence/camera 与离线签名读回通过；历史候选 probe 已锁定 ready 后 8.5 秒不得被看门狗降级。该切片没有实现真实 Provider、开放式健康聊天、正式记录搜索、签名 instrumentation 配置或生产数据库；候选 3D 仍没有真实点击黄金集、性能、真机、解剖/权利批准或生产发布。当前工作树尚未提交/推送，不能外推为远端 CI 或受保护分支证据。

## 5. 不得外推

当前证据不能证明：

1. 临床红旗规则、行动内容或 SafetyBaseline 已获批准；
2. 真实 LLM Provider 的语义质量、地区、留存和隐私合规；
3. OIDC、近期认证、Consent/撤回、正式数据库、审计、导出删除和跨实例事务；
4. 默认/专业人体模型的作者链、商用权、真实文件签名、解剖准确度和设备性能；
5. Keychain、Data Protection、文件 durability、后台同步、真机 VoiceOver 和崩溃恢复；
6. 两类用户能在 30 秒完成、安全理解无误或产品具有诊断/治疗能力；
7. 报告、提醒、趋势、Profile、HealthKit、外部分享和发布运营已经完成。

## 6. 复现命令

```bash
./.venv311/bin/python -m pip install \
  -c backend/constraints-test.txt -e './backend[test]'
./.venv311/bin/python scripts/check_baseline.py
./.venv311/bin/python -m pytest \
  backend/tests/test_p2a_session_turn_projection.py --tb=short
./.venv311/bin/python -m pytest backend/tests --tb=short
./.venv311/bin/python -m compileall -q backend/src backend/tests scripts
./.venv311/bin/python -m pip check

cd ios/BodyCompanion
swift test
swift build --sdk "$(xcrun --sdk iphoneos --show-sdk-path)" \
  --triple arm64-apple-ios17.0 --target BodyCompanionIOS

cd ../..
python3 scripts/check_internal_ios_host.py
bash scripts/run_internal_ios_host_tests.sh
usdchecker --arkit \
  ios/BodyCompanion/AppHost/BodyCompanionInternal/Resources/BodyNeutralPrototype.usdz
```

远端创建后使用同一 workflow 重跑，记录 run URL、commit SHA 和必需状态检查；本地结果不得改写为云端通过。
