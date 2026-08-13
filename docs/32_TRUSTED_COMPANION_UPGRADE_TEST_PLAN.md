# TEST-TRUSTED-COMPANION-01：可信身体助手升级测试计划

| 属性 | 值 |
|---|---|
| 关联需求/功能 | FEAT-TRUSTED-COMPANION-01；PRD-F01/F03A/F11-P0；SAFE-INV-02/05/06/07/09 |
| SafetyBaseline | 未建立；只允许内部 prototype 合成数据 |
| 负责人 | QA、iOS、后端、3D 资产负责人（待 GOV-01 指定） |
| 环境 | Python 3.11、Swift 6、iOS Simulator、Xcode/RealityKit、Blender 5.1.2、Apple USD Tools 0.25.2 |
| 状态 | Active implementation test plan；生产门禁未关闭 |

## 1. 测试目标和风险

本计划验证体验重组没有移除现有安全/草稿/2D 回退语义，后端不会把空规则目录判为 R3，以及 3D 命中没有把重心坐标误写为纹理 UV。最高风险是：开放式 AI 假能力、空安全目录放行模型、3D 锚点坐标空间混用、2D Zone 被伪装成精确点、候选资产被误标为可发布。

不在本计划证明范围：临床规则正确性、真实 Provider、OIDC/Consent、PostgreSQL、跨设备同步、真机性能、资产商用/解剖批准、完整 VoiceOver 与生产发布。

## 2. 被测版本

- commit：本轮完成后记录，不得预填；
- Schema：现有 `body-location`、`body-asset-manifest`、OpenAPI v1；
- Agent：`pydantic-ai-slim==2.23.0`，本功能不增加模型调用；
- 资产：`body-neutral-procedural-v1@1.2.0` / `body-neutral-procedural-topology-v2`；SHA-256 `3120c9de64d26c98aed073776107e154c0450b52d7e289aa61fa6dc63fc45d5f`；
- 数据：只用合成身体位置、事实和无身份查询词。

## 3. 覆盖矩阵

| 测试 ID | 需求/不变量 | 层级 | 场景 | 期望 | 自动化 |
|---|---|---|---|---|---|
| TCU-T-001 | TCU-AC-001/002 | UI | 无草稿与有草稿首页 | 主动作进入现有地图；继续/放弃语义保持 | Simulator smoke |
| TCU-T-002 | TCU-AC-003、SAFE-INV-02/06 | UI/Static | AI 页 | 普通对话锁定；安全在前；候选待确认；无建议结果 | Simulator + source scan |
| TCU-T-003 | TCU-AC-008 | UI/Accessibility | accessibility size、暗色、Reduce Motion | 可滚动、布局不遮挡、无持续动画依赖 | Simulator/manual；不得外推完整无障碍 |
| TCU-T-004 | TCU-AC-004 | Unit/Safety | available + empty rules | unavailable/undetermined；普通 Agent=false | Python |
| TCU-T-005 | SAFE-INV-02 | Integration | empty catalog + injected runner | runner 调用次数保持 0，返回 fixed safe failure | Python |
| TCU-T-006 | PRIV-INV | Unit/Static | Agent metadata | 只含版本等无敏感值；无伪造 `include_content` 开关 | Python + source scan |
| TCU-T-006A | SAFE-INV-02/05 | Unit/Safety | 重复规则 ID、hit ID 错配、matched 无 tier、evaluator 异常 | 整体 unavailable；无部分 hit、无 Agent、无异常/健康正文回显 | Python |
| TCU-T-006B | SAFE-INV-02/05 | Unit/Safety | 非布尔 available/scenario、过长 version、非规则对象、`model_construct` 伪造 hit、matched 空 evidence refs | 固定 unavailable/undetermined，不抛异常、不保留 hit、Agent=0 | Python |
| TCU-T-006C | TCU-AC-004B | Unit/Integration | R0/R1 matched + 低优先级 undetermined | 应用服务立即 escalated；action/content/message 来自最高风险规则，非 clarification；Agent=0 | Python |
| TCU-T-007 | ADR-0003/0004 | Unit/Build | triangle hit conversion | `uv2 → (u,v,1-u-v)`；triangle/barycentric 成对；surface UV=nil | Swift + iPhoneOS build |
| TCU-T-008 | ADR-0003 | Unit | 非法重心、非单位法线、缺配对 | fail closed，不创建 3D location | Swift Core |
| TCU-T-009 | TCU-AC-006 | UI | candidate 禁用/加载失败 | 2D/列表仍可选择并继续 | Simulator smoke |
| TCU-T-010 | TCU-AC-007 | Unit/UI | Canvas Zone 与 Pin | Zone=Area+region mask；Pin=Point；surface identity 不折叠 | Swift Core + Simulator |
| TCU-T-011 | ADR-0018 | Asset/Contract | asset package + manifest | ARKit USD 校验成功、哈希一致、stable entity 集合完整、candidate 门禁拒绝生产 | Script + Swift/Python contract |
| TCU-T-012 | Canonical Body Space | Asset | root/轴/单位/尺寸 | Y-up、米、脚底根原点与清单一致；资产基准不由运行时 bounds 猜测 | USD inspection + source scan |
| TCU-T-013 | Asset reproducibility | Supply chain | 同环境连续生成三次 | canonical USDZ SHA 一致；生成脚本无第三方资产输入 | Script |
| TCU-T-014 | Regression | Unit/Contract | 全量后端、Swift、文档 | 原有安全、确认、草稿和禁止引用测试继续通过 | CI/local |
| TCU-T-015 | 视觉身高边界 | Unit/Build | 米/厘米档位、越界或无效输入 | 仅 `1.35–2.20m` 生效；不改变资产基准、锚点或持久化事实 | Swift + source scan |
| TCU-T-016 | TCU-AC-006A | Unit/UI | ready 后加载看门狗届时 | 保持 `threeDReady`；仅未就绪的当前 attempt 回退 2D | Swift Core + Simulator probe |
| TCU-T-017 | ADR-0018 | Contract/Supply chain | 删除/替换 render、独立 collision、region map、surface correspondence、camera preset、manifest self-hash 或离线签名任一产物；或把候选资源放回可复用 Swift Package | Schema/Swift/baseline/asset readback 全部 fail closed，candidate 只能回退 2D | JSON Schema + Swift + Python + AppHost static gate |
| TCU-T-018 | ADR-0018 | Asset/CI | Manifest/Swift/USD custom identity 任一漂移 | 自动门禁失败；`usdchecker --arkit`、根/坐标、实体集、三角数和 ZIP 对齐同时读回 | macOS CI + local |

## 4. 负向与停止规则

- 任一 empty/unavailable catalog 返回 R3、`NoRuleTriggered` 或调用普通 Agent：立即停止后端 Agent 路径；
- 任一 R0/R1/R2/undetermined 路径进入普通 Agent，或 UI 声称“安全”：立即停止受影响路径；
- 任一 3D `triangle_index` 无 barycentric、`TriangleHit.uv` 写入 surface UV、mesh/entity local 混用、版本不一致仍创建 marker：停止 3D marker，回退 2D；
- 资产哈希不一致、根变换与清单不一致、USDZ 不满足 ARKit 对齐、缺稳定实体、candidate 被标为 approved：停止打包；
- UI 移除 2D/列表、草稿明确放弃、AI 锁定或非诊断提示：停止内部 Host 发布。

## 5. 通过门槛与结果记录

| 指标 | 必须达到 | 可豁免 |
|---|---:|---:|
| 空安全目录普通 Agent 调用 | 0 | 否 |
| triangle/barycentric/UV 契约违规 | 0 | 否 |
| 2D/列表降级完成率（受控测试） | 100% | 否 |
| 既有后端/Swift/契约回归 | 100% 通过 | 否 |
| candidate 误标生产批准 | 0 | 否 |

执行后只在 EVIDENCE-01 记录真实命令、数量、环境和限制。Simulator 截图、`usdchecker`、编译或自动化通过均不能替代真机、完整辅助功能、临床、法务、资产或生产签字。

## 6. 变更记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-08-13 | 0.1.3 | 锁定 1.2.0 工具链/哈希/三次生成收据，并增加发布资产跨层读回脚本。 |
| 2026-08-13 | 0.1.2 | 增加非法目录/伪造 hit/空证据整体 fail-closed 与 R0/R1 行动优先集成测试。 |
| 2026-08-13 | 0.1.1 | 增加 3D ready 不可被超时任务二次失败的状态机锁定测试。 |
| 2026-08-13 | 0.1.0 | 建立前端状态、空安全目录、2D/3D 定位、资产和回退的共同测试计划。 |
