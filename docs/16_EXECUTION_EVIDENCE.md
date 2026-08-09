# EVIDENCE-01 当前工程验证快照

| 属性 | 值 |
|---|---|
| 文档 ID | EVIDENCE-01 |
| 版本 | 2.8.0 |
| 状态 | Current local snapshot / Prototype-only |
| 工作区 | `/Users/liuchongjiang/Documents/3D人体` |
| 快照日期 | 2026-08-09 |
| 对应 Git | `codex/initial-git-ci-baseline` 受保护默认分支；PR #4 合并提交 `2bb8e8a`；复刻切片提交 `6f232b4`、证据绑定提交 `f6a6d5b`；P0 体验/边界提交 `e93fc75`、GATE-02 决策包 `a91f103`、内部 Host `5dddd83` |
| 本轮变更状态 | `5dddd83` 已在本地和远端 CI run `31295533318` 重建；其 iOS Host 结论仅限 Simulator，不构成真机或生产批准 |

## 1. 证据解释

本文件只保留当前可复现结果，不再累计每个临时切片的重复流水账。已实现边界见 [BASELINE-01](18_IMPLEMENTED_PROTOTYPE_BASELINE.md)，需求到证据关系见 [TRACE-01](14_TRACEABILITY_MATRIX.md)，发布门禁见 [REL-01](13_DELIVERY_ROADMAP.md)。

本轮 iOS Host 证据绑定提交 `5dddd83`：本地 iPhone 17 Pro Simulator 与远端 CI iPhone 16 Simulator 均已重建。进入外测前仍必须由受保护提交、SafetyBaseline、真实设备和所有发布门禁另行验证。

## 2. 当前验证结果

| ID | 检查 | 当前结果 | 证明范围 |
|---|---|---|---|
| EV-CURRENT-001 | `scripts/check_baseline.py` | `passed; markdown_files=61 checked_links=345 json_schemas=16 openapi_paths=36 openapi_schemas=111 asset_manifests=1 prohibited_source_matches=0` | 文档、契约清单、CI Action SHA/权限、依赖 pin、资产清单/Bundle SHA、退役路径和禁止源码引用的本地静态门禁 |
| EV-CURRENT-002 | P2A 聚焦回归 | `19 passed` | 默认时钟被 fixture 冻结；显式过期路径仍可测试 |
| EV-CURRENT-003 | Python 编译与依赖 | `compileall` 通过；`pip check` 无破损依赖 | Python 3.11 当前约束环境可导入；不证明其他平台/版本 |
| EV-CURRENT-004 | `cd ios/BodyCompanion && swift test` | `82 tests, 0 failures` | Swift Core 样机；包含 V2 Zone/Pin 位置状态、Zone + Pin 合计 20 个位置上限且超限不截断、地图仅同步位置、typed facts 不被地图覆盖、同 ID 位置语义替换的地图投影与感觉复核、删除最后一个关联位置时移除空感觉关系、R2 普通 Agent 抑制及反序列化/恢复拒绝、多位置感觉显式关联、位置变更使安全/普通 Agent/审批失效、恢复时地图投影一致性、P4 1.1 感觉—位置关系/唯一 ID/旧 code-only 版本拒绝、地图/草稿同步和草稿进入策略；不证明真机/签名/生产资产 |
| EV-CURRENT-005 | `./.venv311/bin/python -m pytest backend/tests --tb=short` | `194 passed` | 后端合成/内存样机全量绿色；包含 R2 许可与 JSON Schema 负例回归；不证明生产依赖 |
| EV-CURRENT-006 | 退役文档/旧链接/旧过程 OPEN ID 扫描 | `retired_slice_files=0 stale_retired_links=0 stale_open_process_ids=0` | 32 份过程文档已删除，非归并登记处不存在旧路径或旧门禁引用 |
| EV-CURRENT-007 | RehabMate 禁止生产实现扫描 | `0 matches` | iOS/后端源码未出现被禁止的 Web/算法/资产关键词；不替代许可证人工审计 |
| EV-CURRENT-008 | iOS SDK target build | `swift build --sdk $(xcrun --sdk iphoneos --show-sdk-path) --triple arm64-apple-ios17.0 --target BodyCompanionIOS` 构建通过；generic prototype build 亦通过 | 只证明 Swift Package/RealityKit 适配器编译，不证明签名安装/真机运行 |
| EV-CURRENT-009 | `.github/workflows/ci.yml` | Ubuntu 24.04 后端/契约 + macOS 15 iOS；官方 Action 固定完整 SHA；iOS job 新增 Host 静态扫描与 Simulator smoke | `5dddd83` 的 run `31295533318` 成功：Backend and contracts 19s；iOS package and internal host 7m11s，包含 Swift tests、iPhoneOS build、`check_internal_ios_host.py` 与 `run_internal_ios_host_tests.sh` |
| EV-CURRENT-010 | BODY-ASSET-01 候选资产 | USDZ SHA-256 `299d896513a8c7ef7e5d584495c9bc5ba78505da5f20c9dc2b50e0ef9d7e5668`；1.1.0 清单 schema 和 Bundle 读回通过 | 只证明文件与清单一致；candidate、未签名、未解剖/性能审核，不能发布 |
| EV-CURRENT-011 | 默认分支保护 | GitHub API 读回成功：`Backend and contracts`、`iOS Swift package` 为必需检查；strict=true、管理员强制、线性历史开启、禁止强推/删除；PR #1 与 PR #4 已合并 | 证明远端设置和两次 PR 合并路径；不证明所有后续变更或发布门禁自动安全 |
| EV-CURRENT-012 | FEAT-BODY-MAP-V2 上游行为基线 | RehabMate commit `1378a752dfb0d656a27a73c234269f9f5be2c3ca`、代码 MIT、上游 `body.glb` Git blob SHA-1 `adbf4de165f5698b770e36d33fa953a2210f968c` 和 raw SHA-256 `ffd98cc59f128d1c162e1d63af905e4f459b6e18618a7c853b1cbe8a43cf0ce2` 已记录；内置浏览器打开成品站超时 | 证明源审计锚点和采用边界；不证明成品站视觉加载或生产资产权利 |
| EV-CURRENT-013 | FEAT-BODY-MAP-V2.1 窄屏编辑与反馈 | `swift test --parallel`：`64 tests, 0 failures`；iOS SDK target 构建通过；窄屏编辑器使用系统 Sheet/Detent，Pin 上限和 3D 回退使用固定文本提示；不证明真机 Sheet/VoiceOver/动态字体行为 | 证明代码和 Core 回归已覆盖 V2.1 逻辑；设备、无障碍和生产门禁仍未关闭 |
| EV-CURRENT-014 | EVIDENCE-DEVICE-01 真机与候选资产审核 | `5dddd83` 已解除“无 Simulator App target”阻塞：本地 iPhone 17 Pro / iOS 26.5 的 7 项 UI smoke 与远端 iPhone 16 / iOS 18.5 的同一脚本均成功；两部登记 iPhone 仍 Offline/unavailable；USDZ `usdchecker`/ZIP/哈希及 CollisionGroup、triangle/barycentric、下背实体、根变换发现仍在 | 证明 Simulator Host 与候选文件结构；不证明 Sheet 的真机体验、VoiceOver、Dynamic Type、Reduce Motion、3D FPS/内存、碰撞黄金集、签名或生产批准；详见 [`EVIDENCE-DEVICE-01`](24_DEVICE_VALIDATION_EVIDENCE.md) |
| EV-CURRENT-015 | P0 明亮中文体验壳与录入完整性 | 本轮 `swift test` 的 82 项 Swift Core、既有 iPhoneOS SDK build 和 7 项本地 UI smoke 绿色。今天/记录/AI 身体助手入口统一显示进程内未确认草稿的继续或确认放弃后新建；3D 默认显式关闭并回退 2D；位置 Inspector 不含感觉/程度/动作线索；多位置感觉不自动复制；canonical location 保持地图与 typed draft 同步，同 ID 语义替换重新复核感觉，删除不保留空感觉关联；位置变更会清除旧 safety/普通 Agent/审批阶段；R2 不进入普通 Agent；P4 1.1 保留感觉与位置关系 | 证明 P0 路由、草稿状态、地图—结构化事实边界、列表回退、安全门和内部可运行壳未破坏；不证明 P0 视觉可用性、VoiceOver、Dynamic Type、Reduce Motion、签名安装、真机 3D、真实 AI 或医疗能力 |
| EV-CURRENT-016 | 内部 iOS App Host | `xcodebuild -list` 发现 App target、UI test target 与共享 scheme；`check_internal_ios_host.py` 通过；本地 `bash scripts/run_internal_ios_host_tests.sh` 在 iPhone 17 Pro / iOS 26.5 产生 `7 passed, 0 failures`；远端 run `31295533318` 及本轮 `a796f0b` 的 run `31296924827` 均成功运行同一脚本 | 只证明无网络/Provider/权限/持久化/遥测入口的内部 Simulator UI smoke；不证明系统权限弹窗、网络抓包、真机、无障碍、性能、资产许可或发布 |

## 3. 当前已证明

- PydanticAI 使用固定公共发行版；确定性 SafetyEngine 位于普通 Agent 之前。
- Agent 输出保持强类型、未确认，工具读取受主体/scope/expiry/allowlist 约束。
- iOS Core 能表达规范位置、结构化身体信号、2D 回退、密文草稿和同步状态。
- 确认链在进程内/fake repository 中验证了 revision、前驱、摘要、幂等、有限写集和 read-back 关系。
- BodyAssetManifest metadata gate 会对未知、未批准、blocked/retired 或交叉约束不完整的资产回退 2D。
- 机器契约和当前测试代码仍保留；删除的是重复的过程性 Feature/Test 文档。
- P0 明亮中文体验壳已连接到既有 2D/3D 位置与未确认结构化草稿路径；地图只产生位置，感觉、程度和因素只能在结构化页填写；没有新增真实资料读取、行动建议或正式写入。
- R2 已在 Swift/Python 状态机和机器契约中抑制普通 Agent；多位置的感觉关联、结构化删除与草稿继续/新建均需要明确用户动作；位置变化会使本地 safety、普通 Agent 与审批阶段失效，避免复用旧结果。
- 受版本控制的 `BodyCompanionInternal` 已可在本地和远端 Simulator 构建、安装、启动并通过 7 项 UI smoke；候选 3D、网络/Provider、权限、持久化、遥测和正式档案能力均显式保持关闭。

## 4. 已关闭项与剩余阻断

### CLOSED-EV-001 P2A 墙上时钟漂移

根因是 Session 使用固定 `2026-08-06` 创建，部分请求却回退到真实墙上时钟。现在 autouse fixture 冻结领域默认 `utc_now`，并新增省略请求 `now` 的回归；过期测试仍显式注入时间。P2A 19 个与后端全量 194 个测试均绿色。

### PARTIAL-EV-001 远端 CI 与保护分支

本地 `codex/` 分支、首个提交、Python 3.11 约束和 CI workflow 已建立；`origin` 已配置，PR #4 已合并到受保护默认分支提交 `2bb8e8a`，合并后两个 CI job 成功。`5dddd83` 的 run `31295533318` 还成功重建了新增的 iOS Host 任务；后续变更仍必须复用该 PR/required-check 路径。

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
```

远端创建后使用同一 workflow 重跑，记录 run URL、commit SHA 和必需状态检查；本地结果不得改写为云端通过。
