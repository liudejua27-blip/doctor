# EVIDENCE-01 当前工程验证快照

| 属性 | 值 |
|---|---|
| 文档 ID | EVIDENCE-01 |
| 版本 | 2.1.0 |
| 状态 | Current local snapshot / Prototype-only |
| 工作区 | `/Users/liuchongjiang/Documents/3D人体` |
| 快照日期 | 2026-08-08 |
| 对应 Git | `codex/initial-git-ci-baseline` 的首个基线提交；精确 SHA 以本文件所在 `HEAD` 为准 |
| 本轮变更状态 | `origin` 已配置；身体地图/候选资产切片目前在工作树，尚未创建新提交/推送，远端 CI 尚未运行 |

## 1. 证据解释

本文件只保留当前可复现结果，不再累计每个临时切片的重复流水账。已实现边界见 [BASELINE-01](18_IMPLEMENTED_PROTOTYPE_BASELINE.md)，需求到证据关系见 [TRACE-01](14_TRACEABILITY_MATRIX.md)，发布门禁见 [REL-01](13_DELIVERY_ROADMAP.md)。

首个基线提交由 `git rev-parse HEAD` 读取；本轮切片证据在提交前只代表当前工作树。它只证明本地可重建边界；进入外测前仍必须由远端 CI 在受保护提交上重建，并绑定 SafetyBaseline。

## 2. 当前验证结果

| ID | 检查 | 当前结果 | 证明范围 |
|---|---|---|---|
| EV-CURRENT-001 | `scripts/check_baseline.py` | `passed; markdown_files=49 checked_links=265 json_schemas=16 openapi_paths=36 openapi_schemas=111 asset_manifests=1 prohibited_source_matches=0` | 文档、契约清单、CI Action SHA/权限、依赖 pin、资产清单/Bundle SHA、退役路径和禁止源码引用的本地静态门禁 |
| EV-CURRENT-002 | P2A 聚焦回归 | `19 passed` | 默认时钟被 fixture 冻结；显式过期路径仍可测试 |
| EV-CURRENT-003 | Python 编译与依赖 | `compileall` 通过；`pip check` 无破损依赖 | Python 3.11 当前约束环境可导入；不证明其他平台/版本 |
| EV-CURRENT-004 | `cd ios/BodyCompanion && swift test` | `55 tests, 0 failures` | Swift Core 样机；不证明真机/签名/生产资产 |
| EV-CURRENT-005 | `./.venv311/bin/python -m pytest backend/tests --tb=short` | `189 passed` | 后端合成/内存样机全量绿色；不证明生产依赖 |
| EV-CURRENT-006 | 退役文档/旧链接/旧过程 OPEN ID 扫描 | `retired_slice_files=0 stale_retired_links=0 stale_open_process_ids=0` | 32 份过程文档已删除，非归并登记处不存在旧路径或旧门禁引用 |
| EV-CURRENT-007 | RehabMate 禁止生产实现扫描 | `0 matches` | iOS/后端源码未出现被禁止的 Web/算法/资产关键词；不替代许可证人工审计 |
| EV-CURRENT-008 | iOS SDK target build | `swift build --sdk $(xcrun --sdk iphoneos --show-sdk-path) --triple arm64-apple-ios17.0 --target BodyCompanionIOS` 构建通过；generic prototype build 亦通过 | 只证明 Swift Package/RealityKit 适配器编译，不证明签名安装/真机运行 |
| EV-CURRENT-009 | `.github/workflows/ci.yml` | Ubuntu 24.04 后端/契约 + macOS 15 iOS；官方 Action 固定完整 SHA | workflow 已版本化且本地语法/关键门禁检查通过；`origin` 已配置，尚无远端运行记录 |
| EV-CURRENT-010 | BODY-ASSET-01 候选资产 | USDZ SHA-256 `81171745e8813838376959e0910b2242c9bab422a42342c882ac8747ef5afe17`；清单 schema 和 Bundle 读回通过 | 只证明文件与清单一致；candidate、未签名、未解剖/性能审核，不能发布 |

## 3. 当前已证明

- PydanticAI 使用固定公共发行版；确定性 SafetyEngine 位于普通 Agent 之前。
- Agent 输出保持强类型、未确认，工具读取受主体/scope/expiry/allowlist 约束。
- iOS Core 能表达规范位置、结构化身体信号、2D 回退、密文草稿和同步状态。
- 确认链在进程内/fake repository 中验证了 revision、前驱、摘要、幂等、有限写集和 read-back 关系。
- BodyAssetManifest metadata gate 会对未知、未批准、blocked/retired 或交叉约束不完整的资产回退 2D。
- 机器契约和当前测试代码仍保留；删除的是重复的过程性 Feature/Test 文档。

## 4. 已关闭项与剩余阻断

### CLOSED-EV-001 P2A 墙上时钟漂移

根因是 Session 使用固定 `2026-08-06` 创建，部分请求却回退到真实墙上时钟。现在 autouse fixture 冻结领域默认 `utc_now`，并新增省略请求 `now` 的回归；过期测试仍显式注入时间。P2A 19 个与后端全量 189 个测试均绿色。

### PARTIAL-EV-001 远端 CI 与保护分支

本地 `codex/` 分支、首个提交、Python 3.11 约束和 CI workflow 已建立，`origin` 已配置且当前公开 refs 为空；本轮切片尚未提交/推送。首次 GitHub Actions 运行、默认分支、必需状态检查和保护规则仍无法在本地证明，必须在推送后关闭。

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
```

远端创建后使用同一 workflow 重跑，记录 run URL、commit SHA 和必需状态检查；本地结果不得改写为云端通过。
