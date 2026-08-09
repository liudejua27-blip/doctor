# TRACE-01 当前需求—实现—验证追踪矩阵

| 属性 | 值 |
|---|---|
| 文档 ID | TRACE-01 |
| 版本 | 2.7.0-draft |
| 状态 | Active traceability |
| 负责人 | 产品架构 + QA 负责人 |
| 目的 | 将长期需求直接映射到核心设计、机器契约、当前实现和发布门禁 |

## 1. 使用规则

- 产品语义以 PROD/UX/TERM 为准，领域和权限以 DATA/SAFE/PRIV 为准，序列化以 OpenAPI/JSON Schema 为准。
- 样机实现只证明 BASELINE-01 和 EVIDENCE-01 明确列出的边界；`Prototype verified` 不等于发布验证。
- 发布前所有 P0 行必须为 `Verified`，并链接受保护 commit、CI、专业签字和同一 SafetyBaseline。
- 历史 P1A～P2D 名称只用于解释现有代码/测试/ADR，不再作为独立路线图或文档层级。

## 2. 产品功能追踪

| 需求 | 核心设计真源 | 机器契约 | 当前实现/测试 | 当前状态 | 发布门禁 |
|---|---|---|---|---|---|
| PRD-F01 30 秒结构化记录 | UX-01、IOS-01、DATA-01 | `ios-signal-intake`、`body-signal-event` | Swift typed intake 状态机；多位置感觉必须显式关联 Marker，新增位置不复制感觉；当前会话草稿统一“继续/确认放弃后新建” | Prototype verified | GATE-06/07/08 |
| PRD-F02 AI 追问与分析 | AGENT-01、SAFE-01、ADR-0002、ADR-0019、CONFLICT-001 | `agent-turn`、内部 handoff schemas | PydanticAI typed Agent、Safety-first、PolicyValidator；R2 仅安全/专业准备，普通 Agent 仅 R3 | Prototype verified; 情境化产品能力未实现 | GATE-03/04/07/08 |
| PRD-F03A 2D/默认 3D 定位 | BODY-01、IOS-01、FEAT-BODY-MAP-V1/V2、ADR-0003/0004/0018 | `body-location`、`body-asset-manifest` | 全身 2D/列表、原生 RealityKit loader、Zone/Pin/位置摘要状态、metadata gate；地图仅同步 `BodyLocation`，不覆盖结构化事实；TEST-BODY-MAP-V1/V2 | Implementation in progress | GATE-06/07/08 |
| PRD-F03B 专业 3D | BODY-01、IOS-01 | 专业 Asset/Anatomy Manifest | 无生产资产 | Planned P1 | 首发后独立门禁 |
| PRD-F04 八类身体信号 | TERM-01、DATA-01 | intake/event schemas | 客户端 typed 草稿与服务端严格适配 | Prototype verified | GATE-03/07/08 |
| PRD-F05 复查与趋势 | UX-01、DATA-01、API-01 | Event/CheckIn operations | 未形成正式数据闭环 | Planned | GATE-05/07 |
| PRD-F06 身体数字档案 | DATA-01、PRIV-01、API-01 | Profile/Episode operations | 授权读取样机；无正式 repository | Planned | GATE-04/05/07 |
| PRD-F07A 报告与系统分享 | UX-01、API-01、PRIV-01 | Report/Artifact operations | 未实现 | Planned | GATE-05/07/08 |
| PRD-F07B 外部受控链接 | UX-01、API-01、PRIV-01 | ReportShare operations | 未实现 | Planned P1 | 首发后独立门禁 |
| PRD-F08 安全分层 | SAFE-01、ADR-0002 | SafetyAssessment/SafetyBaseline | 确定性引擎结构已存在；临床内容未批准 | Production blocked | GATE-03/08 |
| PRD-F09A 资料权限 | AGENT-01、PRIV-01 | `agent-context`、Consent operations | typed scope/owner/expiry/allowlist 样机 | Prototype verified | GATE-04/07 |
| PRD-F09B HealthKit/文件 | AGENT-01、PRIV-01 | Connector capabilities | 未实现 | Planned P1 | 首发后独立门禁 |
| PRD-F10 修正/导出/删除 | DATA-01、PRIV-01、API-01 | revision/export/deletion operations | 未实现生产闭环 | Planned | GATE-04/05/07 |
| PRD-F11 情境化身体不适决策闭环 | FEAT-COMP-01、UX-01、AGENT-01、SAFE-01、PRIV-01、ADR-0019、CONFLICT-001 | 待 ADR 批准后新增上下文、资料收据、行动引用与报告显示类型契约 | P0 明亮中文入口/地图/结构化草稿壳已编译；多位置感觉显式关联与 R2 普通 Agent 抑制已落地；TEST-COMP-01 已定义；无情境化 API 或生产实现 | Draft / P0 prototype only | GATE-03/04/07/08 |
| PRD-F01/F03A 内部运行宿主 | FEAT-IOS-P0-RUNTIME-01、IOS-01、PRIV-01、QA-01 | 无新增契约；沿用 `body-location`、`ios-signal-intake@1.1`、`ios-draft-envelope@1.1` | 受版本控制 Xcode Host / Simulator UI smoke 计划；尚未执行 | Planned internal engineering prototype | GATE-02/06/07/08 仍打开 |

## 3. 安全不变量追踪

| ID | 不变量 | 控制真源 | 当前证据 | 发布门槛 |
|---|---|---|---|---|
| SAFE-INV-01 | 不诊断、不处方、不排除严重疾病 | PROD-01、SAFE-01、PolicyValidator | 结构和样机测试 | 锁定集违规 0 |
| SAFE-INV-02 | 确定性规则先于普通 LLM | ARCH-01、AGENT-01、SAFE-01 | Application 顺序测试 | 所有路径 100% |
| SAFE-INV-03 | LLM 不得降低 SafetyTier | SAFE-01、ADR-0002 | validator 测试 | TierDowngrade=0 |
| SAFE-INV-04 | R0/R1 抑制普通建议 | SAFE-01 | 样机分支测试 | 违规 0 |
| SAFE-INV-05 | NoRuleTriggered 不等于安全 | TERM-01、SAFE-01 | 文案/状态约束 | 违规 0 |
| SAFE-INV-06 | 未确认内容不得写正式档案 | DATA-01、API-01 | typed confirmation/fake transaction | 非法写入 0；正式 DB 仍阻断 |
| SAFE-INV-07 | 失败仍保留固定安全和手动路径 | UX-01、SAFE-01 | fail-closed 样机 | 故障注入 100% |
| SAFE-INV-08 | 未同意资料不进入 Agent | AGENT-01、PRIV-01 | typed context 授权测试 | 越权 0；真实 Consent 待实现 |
| SAFE-INV-09 | 身体标记不代表病因/损伤 | BODY-01、SAFE-01 | 数据模型/文案约束 | 违规 0 |
| SAFE-INV-10 | 测试与部署绑定同一基线 | DOC-00、QA-01 | PR #1 在 `31234329478` 两个 job 成功后合并，合并后 CI `31234382019` 两个 job 成功；PR #2 复验路径也通过；SafetyBaseline 尚未建立 | 完全一致 |
| SAFE-INV-11 | 审核行动与营养/动作输出边界 | SAFE-01、DATA-01、FEAT-COMP-01 | TEST-COMP-01 已定义；无已审核内容或生产实现 | 未审核动作/具体食物/补剂/药物/剂量输出 0 |
| SAFE-INV-12 | R2 不得进入普通 Agent | SAFE-01、AGENT-01、CONFLICT-001 | Swift 状态机、Python validator/adapter/application handoff 与 JSON Schema 回归 | R2 普通 Agent/行动输出 0 |

## 4. 非功能追踪

| NFR | 当前状态 | 仍缺证据 |
|---|---|---|
| NFR-PERF-001 首次可交互 | 只有 Core/metadata 样机；EVIDENCE-DEVICE-01 真机执行被设备/App target 阻塞 | 最低设备冷启动和资源加载 |
| NFR-PERF-002 高亮延迟 | 未真机验证；EVIDENCE-DEVICE-01 记录无 signpost/设备阻塞 | p95 触控/命中 signpost |
| NFR-PERF-003 3D 帧率 | 未真机验证；候选 manifest performance=pending | 默认资产最低设备持续交互 |
| NFR-REL-001 草稿恢复 | CryptoKit/内存样机；P4 1.1 保留感觉—位置关系并拒绝重复位置/悬空关联 | Keychain、文件、杀进程、后台同步 |
| NFR-REL-002 幂等/事务 | 进程内/fake repository 样机 | PostgreSQL、跨实例、崩溃恢复、read-back |
| NFR-A11Y-001 等价路径 | 2D/列表设计存在；EVIDENCE-DEVICE-01 记录真机执行阻塞 | VoiceOver、Dynamic Type、Reduce Motion 真机 |
| NFR-PRIV-001 最小数据 | typed scope 与禁日志规范 | 真实 Consent、Provider、遥测审计 |
| NFR-TRUST-CTX-001 资料范围可见性 | FEAT-COMP-01/ADR-0019 Draft；无生产实现 | 本次实际使用资料收据、拒绝可选资料完成率与真实审计 |
| NFR-COMP-001 契约兼容 | OpenAPI/16 schemas、Markdown 和禁止引用已有版本化检查器及 CI job | 生成客户端、相邻版本兼容和首次远端 CI 证据 |
| NFR-RUNTIME-001 内部 Simulator 可运行性 | FEAT-IOS-P0-RUNTIME-01 / TEST-IOS-P0-RUNTIME-01 已定义；尚无 App Host 执行证据 | Xcode project/scheme、Simulator build/install/UI smoke、零网络/权限/持久化扫描；不得外推真机、签名或无障碍通过 |

## 5. 参考项目采用追踪

| 来源 | 允许采用 | 禁止采用 | 当前状态 |
|---|---|---|---|
| PydanticAI `pydantic-ai-slim==2.23.0` | 公共 typed Agent/deps/output/tool/eval API | 私有 API、未锁版本、Agent 拥有安全/授权/写入 | 样机依赖锁定；真实 Provider 门禁未关闭 |
| RehabMate 锁定提交 | 旋转、视角、Zone/Pin、焦点、位置摘要/Inspector 和移动端布局行为 | Web/Three.js/GSAP/WKWebView、最近中心/`face.a`/三态健康语义、世界坐标针点、`body.glb`、地图内健康事实编辑 | FEAT-BODY-MAP-V2 原生重写；未复制上游生产代码/资产 |

## 6. API 与契约追踪

- API operation、权限、幂等、错误和兼容真源统一为 [API-01](07_API_CONTRACT.md) 与 [`openapi-v1.yaml`](contracts/openapi-v1.yaml)，本矩阵不再重复 36 个 operation 的逐行清单。
- 16 个 JSON Schema 的字段语义分别由 TERM-01、DATA-01、AGENT-01、BODY-01、PRIV-01 和 BASELINE-01 解释。
- 内部 prototype schema 不代表公开 endpoint；公开前必须经过 GATE-04/05/07。

## 7. 资产追踪

| assetId/version | 模式 | 作者链/许可 | anatomyMap | golden hit set | 性能/无障碍 | 状态 |
|---|---|---|---|---|---|---|
| [`body-neutral-procedural-v1@1.1.0`](21_BODY_ASSET_PROVENANCE.md) | 默认 3D（内部 prototype） | 本项目原创 Blender 生成；生产权利/解剖签字未完成 | prototype region metadata；下背/根变换/碰撞待复核 | 未测真机 | Candidate / internal only |
| `TBD-professional` | 专业 3D | 未取得 | TBD | TBD | TBD | Blocked P1 |

RehabMate `body.glb` 不得进入生产候选。任何 `TBD`、candidate、未知/撤回权利或缺少真实文件签名的资产都必须回退 2D/列表。

## 8. 当前证据和发布包

当前命令结果见 [EVIDENCE-01](16_EXECUTION_EVIDENCE.md)。正式候选必须额外生成并绑定 commit SHA：

- SafetyBaseline；
- requirements/schema diff；
- CI 测试和锁定评测；
- 设备性能与无障碍报告；
- 隐私/安全/临床/法务批准；
- SBOM、资产 manifests、回滚和事故演练。

空模板或本地历史结果不得标记为 Verified。

## 9. GATE-02 责任与产品边界追踪

| 门禁 | 真源 | 当前状态 | 关闭所需证据 | 关闭前保守行为 |
|---|---|---|---|---|
| GATE-02 责任、地区与外部边界 | [GOV-01](27_GATE_02_RESPONSIBILITY_AND_PRODUCT_BOUNDARY.md)、REL-01、PROD-01、SAFE-01、PRIV-01 | 决策包已建立，责任人/地区/批准均 `PENDING` | 具名责任矩阵、G2-DEC-001～008 的书面决策与产品/临床/隐私法务/安全批准，QA 交叉核验 | 仅内部原型；不外测、不接生产健康数据、不调用真实 Provider、不开放普通行动或对外医疗宣传 |
