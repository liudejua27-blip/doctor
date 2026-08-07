# TERM-01 统一术语与数据字典

| 属性 | 值 |
|---|---|
| 文档 ID | TERM-01 |
| 版本 | 1.0.0-draft |
| 状态 | Baseline Draft |
| 负责人 | 产品架构 + 临床安全 |
| 原则 | 其他文档引用这里的术语，不自行创造近义状态 |

## 1. 产品与范围

| 术语 | 稳定英文名 | 定义 | 禁止误用 |
|---|---|---|---|
| AI 身体伴侣 | `AI Body Companion` | 产品名；身体信号记录与恢复决策助手 | 不称 AI 医生、诊断器 |
| 身体信号 | `BodySignal` | 用户主观感觉或与身体状态相关的观察，如疼、紧、麻、疲劳 | 不自动等同疾病或损伤 |
| 身体信号记录段 | `BodySignalEpisode` | 有明确起止和主题的一段持续记录，可含多个位置与多次复查 | 不等同病历或诊断 |
| 身体信号事件 | `BodySignalEvent` | Episode 中一次追加式记录，如首次记录、复查、修正、缓解 | 不覆盖历史事件 |
| 身体报告 | `BodyReport` | 将用户确认事实、趋势、安全行动和来源组织成的摘要 | 不称诊断报告或治疗方案 |
| 复查 | `CheckIn` | 对活动 Episode 的后续结构化记录 | “缓解”必须由复查产生，不是颜色状态 |

## 2. 事实、推断与确认

| 术语 | 稳定英文名 | 定义 |
|---|---|---|
| 用户确认事实 | `UserConfirmedFact` | 用户明确查看并确认写入的结构化事实 |
| 未确认输入 | `UnconfirmedInput` | AI 提取、设备导入或草稿中尚未获用户确认的内容 |
| AI 推断 | `AIInference` | 模型基于事实产生的解释或归纳，必须标明不确定性和来源 |
| 可能相关因素 | `PossibleContributor` | 与一个或多个确认事实相关的非诊断性影响因素，不代表病因 |
| 来源引用 | `FactProvenance` | 声明事实来自用户自报、设备、文件、专业人员或 AI 提取 |
| 用户确认 | `UserConfirmation` | 对明确对象、版本和后果的主动同意；不是一次登录后的永久授权 |
| 修正 | `Revision` | 保留原记录并追加更正原因和新版本，不做静默覆盖 |
| 结构化录入草稿 | `SignalIntakeDraft` | iOS 将位置和身体信号事实组组织成可复核的客户端投影；不是正式 Event、Approval 或报告 |
| 事实来源 | `SignalFactSource` | `user`、`agent_candidate`、`profile`、`system`；说明事实从哪里进入当前草稿 |
| 事实状态 | `SignalFactStatus` | `user_entered`、`candidate`、`reviewed`、`unknown`；说明用户是否复核，不与来源合并 |
| 感觉位置关系 | `location_marker_ids` | 某个感觉由用户明确关联的 `BodyLocation.marker_id` 集合；缺失时服务端不得复制到所有位置 |
| iOS 录入服务端适配结果 | `IOSSignalIntakeAdapterResult` | P1E 内部结果；表示需安全预检、可进入 Agent、安全行动、仅离线或拒绝；不代表正式写入 |
| iOS 录入 Application handoff | `IOSSignalIntakeApplicationHandoff` | P1F 内部结果；Application Service 先运行本次服务端 Safety，再决定是否把未确认 `AssessmentDraft` 交给后续 Agent；不运行 Agent、不创建正式资源 |
| P1G Agent handoff | `P1GAgentHandoffResult` | P1F `ready_for_agent` 后的内部 PydanticAI 结果；只返回未确认候选或固定回退，不改变 Safety、不写正式资源 |
| Structured prompt | `StructuredAgentPromptBuilder` | 将 typed `AssessmentDraft` 包在固定数据区中交给 Agent；数据不是指令，不含完整 raw text/身份/安全答案原文 |
| P1H Agent Turn Application | `AgentTurnApplicationService` | P1F/P1G 之后绑定 session/turn/sequence/draft revision/前驱和幂等的内部应用服务；只保存进程内脱敏 result，不是公开 AgentTurn、数据库或消息历史 |
| Agent Turn Application result | `AgentTurnApplicationResult` | P1H 的强类型 transient 结果；携带未确认候选或固定回退，不携带身份、原话、prompt 或正式资源引用 |
| P2A Session/Turn Projection | `P2ASessionTurnProjectionService` | 将已验证 P1H result 投影为 typed Session/Turn 快照的内部样机；owner 只在服务端索引中存在，不是公开 API、正式 Session 持久化或 Event |
| SessionTurnProjectionResult | `SessionTurnProjectionResult` | P2A 的稳定投影结果；包含 Session/Turn revision、sequence、前驱和未确认候选/回退，不包含 raw、身份或正式资源引用 |
| P2B ConfirmationIntent Application | `P2BConfirmationIntentApplicationService` | 将 P2A `draft_ready` 与用户八组事实复核、安全结果和 EpisodeSelection 复验后创建 pending ApprovalIntent 的内部应用边界；不执行 approve、不写 Event/Episode、不修改 P2A |
| ConfirmationIntentApplicationResult | `ConfirmationIntentApplicationResult` | P2B 的稳定脱敏结果；只含 pending ApprovalIntent 元数据与拟议 `approval_required/awaiting_approval` lifecycle projection，不含候选正文、raw、Safety answers 或用户身份 |
| ApprovalRequiredProjection | `ApprovalRequiredProjection` | P2B 提议的 application-origin lifecycle Turn 元数据；不是已持久化 AgentTurn，也不表示 Event 已保存 |
| Confirmation request digest | `request_digest` | 对 owner、P2A 投影、确认字段、安全版本/状态和 EpisodeSelection 的规范化摘要；只用于 P2B 单进程重放/冲突，不保存 raw 正文 |
| P2C Approval Decision Application | `P2CApprovalDecisionApplicationService` | 将 P2B pending ApprovalIntent 与服务端当前 revision、typed approve/deny 复验后委托原型 Approval/Event store；只返回 terminal metadata/prospective lifecycle，不修改 P2A、不新增公开 API |
| ApprovalDecisionApplicationResult | `ApprovalDecisionApplicationResult` | P2C 脱敏终态结果；executed 只能含一个 event ref，其他终态无 result refs，不含 raw/candidate/Safety/身份 |
| ApprovalDecisionLifecycleProjection | `ApprovalDecisionLifecycleProjection` | P2C 终态的 prospective application lifecycle；revision/sequence 只表达单调关系，不等于 Session/Turn 已持久化 |
| P2D Confirmation Transaction Contract | `P2DConfirmationTransactionContract` | 正式 repository 的内部 `prepare → commit → read_back` 语义；固定 owner/source/revision、有限 write set、全有/全无和读回关系；当前只允许 metadata-only prototype |
| ConfirmationTransactionReceipt | `ConfirmationTransactionReceipt` | P2D 脱敏事务回执；只含 outcome、Session/Approval ID、digest、revision、lifecycle、有限 write set、合法 result refs 和原子性标记，不是正式 Event/Session/Approval |
| Transaction write set | `ConfirmationTransactionWriteSet` | 一次确认决定允许修改的 Session、lifecycle Turn、Approval、必要 Event/Episode 绑定和 audit metadata 集合；不能由 Agent 或客户端扩大 |
| Authoritative read-back | `AuthoritativeReadBack` | commit 后从服务端权威存储重新读取并校验状态/版本/结果引用；不能用内存 plan 直接当作完成事实 |
| P1-C 体验研究记录 | `P1CUXResearchRecord` | 只包含任务、版本、入口模式、时间、错误类别、停止规则、理解结果、回退和研究员澄清次数的脱敏内部元数据；不含身体内容、原话、身份、音视频或模型内容 |
| P1-C 研究记录器 | `P1CResearchRecorder` | 默认关闭、进程内、metadata-only 的 Swift Core 原型；不是产品分析 SDK、健康档案、研究仓或临床证据 |
| 研究停止规则 | `P1CStopRule` | P1-C 中阻止继续任务或阻止 `completed` 的固定安全/隐私/无障碍条件；触发后只能记录 `stopped` 或删除 |
| Turn 前驱 | `in_reply_to_turn_id` | 当前 Turn 明确回复的上一 Turn；继续请求必须指向 ledger 当前 `awaiting_user` Turn，不得猜测或静默合并 |
| Turn 幂等摘要 | `request_digest` | 对 session/turn/sequence/revision/typed handoff/授权投影计算的 `sha256:` 摘要；只用于单进程重放和冲突判断，不保存原始请求正文 |
| 资产发行清单 | `BodyAssetManifest` | 版本化的非健康 metadata：资产身份、来源/许可证、哈希/签名状态、坐标/拓扑、artifact/LOD、区域映射、审核、性能和回退；不包含用户身体事实 |
| 资产运行时门禁 | `BodyAssetRuntimeGate` | 在 RealityKit loader 前执行的 fail-closed metadata 校验；只返回 eligibility 或 2D/列表回退，不读取/下载模型文件 |
| 资产发布状态 | `BodyAssetReleaseStatus` | `candidate`、`approved`、`blocked`、`retired`；表示资产发行状态，不表示医学安全、临床准确或用户位置已确认 |
| 资产变体 | `BodyAssetVariant` | `default_neutral`、`professional_muscle_joint`、`body_map_2d`；视图入口与资产清单身份，不改变 `BodyLocation` 语义 |

## 3. 身体位置

| 术语 | 稳定英文名 | 定义 |
|---|---|---|
| 解剖标记 | `AnatomicalMark` | 用户在 2D/3D 上表达主观位置的标记 |
| 身体位置 | `BodyLocation` | 可跨视图持久化的区域、侧别、表面和可选精确锚点 |
| 区域标记 | `RegionMark` | 以稳定 `region_id` 表达的一片身体区域 |
| 精确针点 | `PointMark` | 使用资产局部表面锚点表达的精确触点 |
| 规范身体区域 | `CanonicalBodyRegion` | 与具体模型无关、经版本管理的身体区域身份 |
| 侧别 | `Laterality` | `left`、`right`、`midline`、`bilateral`、`unspecified`；相对用户身体；未知或不适用均显式为 `unspecified`，不得猜为中线 |
| 表面 | `BodySurface` | `anterior`、`posterior`、`medial`、`lateral`、`superior`、`inferior`、`circumferential`、`unspecified`；未知时不得按当前镜头方向猜测 |
| 深度 | `BodyDepth` | `superficial`、`deep`、`joint_nearby`、`unspecified`；只表达用户主观感觉，不代表组织定位 |
| 表面锚点 | `SurfaceAnchor` | 资产、拓扑、面索引、重心坐标、局部点/法线和规范表面坐标的组合 |
| 映射置信度 | `MappingConfidence` | 跨 2D/3D/资产版本映射的可靠程度；低置信必须由用户确认 |

位置标记只表达用户指出的位置，不表示症状来源、受损组织、神经支配或医学诊断。

## 4. 身体信号维度

| 维度 | 英文键 | 语义规则 |
|---|---|---|
| 感觉类型 | `sensations[].code` | 疼痛/不适的主观感觉；与诱发动作分离，可多选，允许 `other` 和 `unknown` |
| 当前强度 | `sensations[].intensities[context=current]` | 回答当时 0–10；缺失是未填写，0 是明确没有 |
| 时间窗最重强度 | `sensations[].intensities[context=peak]` | 指定时间窗内最强程度，必须同时保存 `window` 语义 |
| 起始 | `temporal.onset` | 开始时间、突然/逐渐及相关活动；不强迫虚假精确时间 |
| 时间模式 | `temporal` | 持续、间歇、活动后、晨间、夜间等结构化特征 |
| 诱发/加重因素 | `aggravating_factors` | 会引出或加重身体信号的动作、姿势或负荷 |
| 缓解因素 | `relieving_factors` | 用户观察到会减轻信号的行为或情境；不是系统治疗结论 |
| 功能影响 | `functional_impacts` | 对走路、跑步、训练、睡眠、工作、日常活动的影响 |
| 背景信息 | `background_facts` | 近期负荷、工作姿势、既往 Episode、设备记录等 |

v1 感觉代码的唯一序列化集合如下；显示文案、分组顺序和适用场景仍需临床内容审核：

- 疼痛质感：`aching`（酸/胀/隐痛感）、`dull_pain`（钝痛）、`sharp_pain`（尖锐痛）、`stabbing`（针刺/刀刺感）、`throbbing`（搏动感）、`tenderness`（触压敏感）、`pressure`（压迫感）；
- 感觉变化或传播：`burning`（灼热感）、`electric`（电击感）、`radiating`（向外延伸/放射感）、`tingling`（麻刺感）、`numbness`（麻木）、`reduced_sensation`（感觉减弱）、`itching`（瘙痒）；
- 运动/组织感受：`tightness`（紧绷）、`stiffness`（僵硬）、`cramping`（抽筋/痉挛感）、`catching`（卡住感）、`clicking`（弹响感）；
- 主观控制/功能感受：`weakness`（主观无力感）、`instability`（不稳感）、`giving_way`（打软/支撑不住感）、`movement_fear`（因不适产生的动作担忧）；
- 用户可观察表现：`swelling`（肿胀）、`redness`（发红）、`warmth`（发热/温度升高感）、`bruising`（瘀青）；
- 负荷与恢复感受：`fatigue`（局部疲劳）、`heaviness`（沉重感）、`post_activity_soreness`（活动后酸痛）；
- 兜底：`other`（其他，必须保留用户原话）、`unknown`（尚说不清，不能改成 `other` 或默认某种感觉）。

其中 `weakness` 只表示用户主观感觉；“新发/进行性客观无力”等安全含义必须通过独立的 `SafetySignal`/审核问法记录，不能仅凭该感觉代码触发或排除安全结论。

“走路痛、举手痛、转动痛”属于诱发因素，不属于感觉类型。

## 5. 安全术语

| 术语 | 英文名 | 定义 |
|---|---|---|
| 安全信号 | `SafetySignal` | 可能改变下一步行动等级的信息，不是疾病标签 |
| 命中规则 | `TriggeredRule` | 确定性规则在其版本和输入范围内满足 |
| R0 | `Emergency` | 立即急救/急诊行动；只用经审核固定内容 |
| R1 | `SameDayUrgent` | 当日或紧急专业评估 |
| R2 | `PromptProfessionalReview` | 尽快预约专业评估 |
| R3 | `SelfManagementAndMonitor` | 记录、审核过的低风险自我管理与观察 |
| 未命中规则 | `NoRuleTriggered` | 当前已知输入未命中当前规则集；不表示安全或排除风险 |
| 未解决安全信息 | `UnresolvedSafety` | 关键信息含糊/缺失，只能问审核问题或保守升级 |
| 严重漏检 | `CriticalMiss` | 按批准真值应为 R0 而系统未输出 R0 |
| 等级降级 | `TierDowngrade` | 任一组件把确定性规则结果改为更低等级 |
| 禁止医疗宣称 | `ProhibitedMedicalClaim` | 诊断、疾病概率、排除结论、处方或治疗指令 |
| 审核建议 | `ApprovedGuidance` | 带内容 ID、适用条件、证据与审核版本的内容 |
| 超范围模式 | `UnsupportedMode` / `unsupported` | 用户、人群、身体区域或场景尚未被当前审核范围覆盖；只保存确认事实、运行明确适用的安全规则并提供审核过的专业帮助入口，不假装进行普通分析 |
| 手动模式 | `ManualMode` / `manual` | 可选云端 AI 未授权/不可用但确定性安全完整时，用固定表单记录并可经两阶段确认写入不含 AI 解释的正式事实 |
| 降级模式 | `DegradedMode` / `degraded` | 规则、必要权限或验证不可完成时的 fail-closed 行为；只能保留未确认草稿 |
| 安全基线 | `SafetyBaseline` | 将范围、规则、内容、模型、Prompt、契约和测试版本绑定的不可变发布对象 |

最终应用层安全响应的持久化 `mode` 只使用 `emergency | urgent | normal | manual | unsupported | degraded`。这些模式由应用服务根据确定性规则、覆盖范围、同意和依赖状态组装，不是 LLM 自由选择的聊天语气；未知值必须进入更保守的失败路径，禁止映射为 `normal`。

## 6. Agent 与工具

| 术语 | 定义 |
|---|---|
| `AssessmentSession` | 一次可暂停/恢复的结构化采集会话；业务状态存数据库，不依赖模型上下文 |
| `AgentTurn` | 会话中的一次用户输入、Agent 候选输出或 Application 生命周期结果；不等于正式身体档案，也不保存隐藏推理 |
| `AgentWorkflow` | Turn/Session 的流程种类；v1 只允许普通 `assessment` 与安全行动先展示后的 `post_escalation_record` |
| `post_escalation_record` | R0/R1 行动已优先展示后，由用户主动进入的无 LLM 事实复核流程；全程保留原安全 CTA，正式 Event 仍需两阶段确认 |
| `LifecycleTurnInput` | Application Service 为修订、重试和审批追加 Turn 的强类型输入；必须引用同 Session 的直接前驱 Turn，不得伪装成用户消息 |
| 处理投影 | `ProcessingProjection`；同一 Turn 在 `queued/running` 阶段受 revision/CAS 保护的可变运行视图，不是新事实版本 |
| 冻结 Turn | `FrozenTurn`；Turn 一旦进入 awaiting_user/draft_ready/escalated/approval_required/completed/failed 就不可改写，后续动作只能追加新 Turn |
| `AssessmentDraft` | Agent 生成的强类型未确认草稿；不是正式档案 |
| `RetainedSafetyAction` / `retained_safety_action` | Session 独立保留的 R0/R1（及适用的保守 R2）审核行动快照及其 API 字段名；post workflow 或 latest Turn 降级失败时仍必须置顶，不能被 Turn 动作交集过滤 |
| `ToolCall` | Agent 对显式注册、最小权限工具的请求 |
| `ApprovalIntent` | 服务端生成、绑定目标资源、动作摘要、版本、摘要哈希、有效期和后果的待确认意图 |
| 脱敏审批墓碑 | `RedactedApprovalIntent`；来源正文到期、撤回或清理后保留的最小审计对象，`redacted=true`，禁止摘要、Session、Turn 与执行结果正文 |
| `ApprovalRecoveryResult` | `GET /approvals/{id}` 的恢复信封；仅来源 TTL 内的未脱敏终态可携带 Decision/Session/Turn，墓碑必须全部为 null |
| 草稿修订 | `DraftRevision`；提交完整 typed AssessmentDraft 与旧 digest/revision，由 Application Service 重跑本体和安全规则并追加四类结果 Turn，不改写旧 Turn |
| Turn 重试 | `TurnRetry`；仅对 latest、retryable 且输入已保留的 failed Turn 追加 `turn_retry_started`，不改写失败历史、不自动批准副作用 |
| `DeferredRun` | 因用户确认或外部结果暂停的运行；服务端持久化后才能恢复 |
| `PolicyValidator` | 独立于 LLM 的确定性输出校验器，失败则丢弃模型输出并降级 |
| `FrameworkBlueprint` / `FRAME-01` | 参考项目到本产品模块、依赖方向、采用分类和实施门禁的文档真源；不等于代码或发布证据 |
| `ReferenceAdoptionClass` | `Runtime dependency`、`Pattern reference`、`Interaction reference`、`Prototype fixture` 或 `Prohibited reuse`；描述上游项目可以怎样影响本产品 |
| `Application Handoff` | Application Service 在结构化 DTO、安全评估、Agent 候选和正式领域对象之间进行的有界类型交接；不允许用自由 Mapping 绕过校验 |

## 7. 状态术语

### Marker 草稿

`provisional → editing → ready_for_review → confirmed`，任一未确认阶段可进入 `cancelled`。

### SignalIntake

`choosing_location → collecting_facts → safety_review → safety_action / agent_draft → review_facts → awaiting_approval`。规则不可用进入 `offline_draft`，错误进入 `failed`；`awaiting_approval` 仅表示准备服务端批准，不表示已创建正式 Event。

### Episode

Episode 生命周期只使用 `open | monitoring | resolved | closed`。允许转换为：`open→monitoring/resolved/closed`、`monitoring→open/resolved/closed`、`resolved→open/closed`、`closed→open`；表外转换拒绝，`resolved/closed→open` 必须由用户明确选择并审计。`improving | stable | worsening | fluctuating | unknown` 是某次 `BodySignalEvent.trend`，不是 Episode 状态。再次出现时默认创建带 `recurrence_of_episode_id` 的新 Episode（或由用户明确选择按 DATA-01 重开原 Episode），`recurrence` 不是覆盖旧 Episode 的状态值。

### 同步

- `localDraft`：仅设备上的未确认草稿。
- `pendingUpload`：已确认、等待服务端接受。
- `synced`：服务端已有对应版本。
- `conflict`：服务端版本发生变化，需要用户或确定性合并。
- `tombstoned`：逻辑删除标记；按保留政策处理，不代表立即物理清除。用于 Approval 时必须同时满足 `redacted=true` 的最小墓碑规则，不能借审计记录恢复健康正文。

## 8. 禁用近义词

| 禁用表达 | 使用表达 | 原因 |
|---|---|---|
| AI 诊断 | AI 身体信号分析 | 避免越界 |
| 病因 | 可能相关因素 | 不能把相关性写成因果 |
| 没有问题 / 安全 | 当前未命中已知规则 | 避免虚假排除 |
| 医疗报告 | 身体报告 | 不冒充医疗文件 |
| 疼痛点就是受伤点 | 用户标记的不适位置 | 位置不等于来源 |
| 自动保存 AI 结论 | 用户确认后写入事实 | 保持事实边界 |
| 已治愈 | 用户报告当前已缓解/已解决 | 避免治疗结论 |

## 9. 版本规则

- 增加不改变既有语义的术语可提升次版本。
- 改变术语含义、枚举或安全等级必须提升主版本并建立迁移方案。
- 本地化名称可以更新，但稳定英文键和 ID 不随翻译变化。
- 所有事件保存术语/Schema 版本，以便历史记录按当时语义解释。
