# FEAT-BODY-MAP-V2：原生 iOS 身体地图交互纵向切片

| 属性 | 值 |
|---|---|
| 文档 ID | FEAT-BODY-MAP-V2 |
| 版本 | 1.4.0-draft |
| 状态 | Active implementation spec / Prototype release gate open |
| 负责人 | iOS + 产品交互 + 3D 资产 |
| 关联需求 | PRD-F01、PRD-F03A、PRD-F04、SAFE-INV-06、SAFE-INV-09、NFR-A11Y-001、NFR-PERF-002 |
| 变更级别 | A：身体位置、用户确认、资产和无障碍语义同时变化 |
| 依赖 | FEAT-BODY-MAP-V1、BODY-01、IOS-01、TERM-01、ADR-0003、ADR-0004、ADR-0009、ADR-0018、OSS-01 |
| 实现入口 | `BodyMapModel`、`BodyMarking.swift`、`BodyMapScreen`、`BodySceneView` |
| 机器契约 | 复用 `body-location.schema.json`；本切片的 `BodyMark` 只属于未确认客户端状态，不新增公开 API |

## 1. 背景与结论

RehabMate 的成熟度来自一套完整的身体地图交互闭环，而不只是一个 3D 网格：旋转/缩放、前后左右视角、Zone 与 Pin 双模式、区域选中、精确针点、颜色区分、焦点视图、摘要列表、删除/清空和移动端面板布局。本切片将这些**位置交互行为**在 iOS 上做原生等价重写；感觉、程度和动作线索不在地图中复刻，改由地图后的结构化录入页统一处理。

等价的对象是行为和信息层级，不是上游实现或资产：

- SwiftUI 负责模式、摘要、编辑器、错误、确认边界和 VoiceOver；
- RealityKit 负责候选模型、相机、手势、命中证据和纯视觉覆盖；
- `BodyLocation` 仍是唯一位置候选，`BodyMark` 是它上面的未确认视图状态；
- Zone 只表达一次明确的位置草稿；重复点击只重新选中同一草稿，不循环改变视觉或业务状态；删除必须经显式按钮完成；
- 地图只产生 `BodyLocation` 候选；感觉、程度、诱发/缓解因素、功能影响和安全答案只能在后续 typed Signal Intake 中由用户显式填写与复核，地图不得投影或覆盖这些事实；
- 资产、区域映射和 3D 锚点继续遵守 BODY-01/ADR-0018 的版本、回退和供应链门禁。

因此“复刻”在本项目中定义为：**原生重做 RehabMate 的交互闭环，保留产品安全、位置本体、数据确认和资产门禁。** 直接复制 Web 源码、运行时、算法或上游人体模型仍然禁止。

## 2. 上游审计基线

| 项目 | 锁定事实 | 采用结论 |
|---|---|---|
| 源仓库 | [HUANGCHIHHUNGLeo/RehabMate](https://github.com/HUANGCHIHHUNGLeo/RehabMate) | 仅行为/布局参考 |
| 锁定提交 | [`1378a752dfb0d656a27a73c234269f9f5be2c3ca`](https://github.com/HUANGCHIHHUNGLeo/RehabMate/tree/1378a752dfb0d656a27a73c234269f9f5be2c3ca) | 复现和审计锚点，不随 `master` 漂移 |
| 代码许可 | MIT；仓库声明不覆盖 `assets/body.glb` | Swift 原生重写；若未来复制实质代码须另行登记版权 |
| 上游人体文件 | 4,152,216 bytes；Git blob SHA-1 `adbf4de165f5698b770e36d33fa953a2210f968c`；raw 文件 SHA-256 `ffd98cc59f128d1c162e1d63af905e4f459b6e18618a7c853b1cbe8a43cf0ce2` | 禁止进入本项目生产、测试包和截图素材 |
| 上游资产声明 | CharacterZone / CC BY 4.0，但作者链需继续核验 | 不作为默认或专业模型 |
| 成品站 | `https://rehab-body-map.vercel.app/` | 本轮内置浏览器加载超时，未将未验证视觉细节写入规格；源码事实优先 |

## 3. 用户目标与验收标准

### 3.1 目标

用户在 3D 页面内可以：

1. 在 Zone/Pin 两种输入模式间切换，切换不丢失另一种模式的草稿；
2. 拖动旋转、双指缩放，并用前、后、左、右快捷视角恢复方向；
3. Zone 模式点选一个稳定区域后看到高亮并进入焦点视图；再次点选同一区域只重新选中该草稿，不生成医学结论、不改变草稿语义也不删除；
4. Zone 与 Pin 合计最多创建 20 个可区分的位置（Pin 可在任意可命中的表面创建精确点）；再次点击已有点优先选择该点，而不是创建重复点；
5. 在摘要面板中选择一个标记，查看位置来源、部位、侧别和精确点状态，并可显式删除；随后进入结构化描述页填写感觉、程度和触发因素；
6. 在手机窄屏以底部可收起的摘要/编辑区域使用，在大屏以侧栏/内联区域使用；
7. 3D 不可用时继续使用 2D/部位列表完成相同的未确认位置录入。
8. 达到位置总上限或 3D 回退时看到可读、可被 VoiceOver 读出的即时反馈，不需要猜测“为什么没有新增”。

### 3.2 验收标准

| ID | Given / When / Then |
|---|---|
| BODY-V2-AC-001 | Given 已有 Zone 草稿，When 切换到 Pin，Then Zone 草稿仍可见；切回 Zone 不改变其 marker ID、区域和侧别。 |
| BODY-V2-AC-002 | Given Zone 模式命中一个稳定实体，When 首次点击，Then 产生一个 `region_id + laterality` 的 `BodyMark`；When 再次点击，Then 只选中同一 marker，高亮和焦点可返回全身，不改变/删除该草稿。 |
| BODY-V2-AC-003 | Given Pin 模式命中表面，When 点击，Then 新增一个绑定资产版本的 `BodyLocation`；不能保存世界坐标或把实体名直接当作本体。 |
| BODY-V2-AC-004 | Given 已有 Pin 被命中，When 再次点击，Then 先选中已有 Pin 并打开摘要，不创建重复 Pin。 |
| BODY-V2-AC-005 | Given Zone 与 Pin 合计数量为 20，When 再添加任一类型，Then 保留已有 20 个、typed draft 使用相同 20 个 ID，并展示可理解的上限提示。 |
| BODY-V2-AC-006 | Given 3D 点击或模型失败，When 回退，Then 2D/部位列表和已有未确认草稿完整保留。 |
| BODY-V2-AC-007 | Given 用户打开地图摘要，When 未进入结构化描述页，Then 地图不展示或写入感觉、程度、动作线索或安全事实，也不自动填入默认感觉。 |
| BODY-V2-AC-008 | Given 用户点击“下一步：描述你的感受”，When 填写 0–10 程度，Then 仅由 typed `SignalIntakeDraft` 保存未确认程度；`nil` 与用户主动选择 0 不同，没有确认动作不能创建正式 Event。 |
| BODY-V2-AC-009 | Given VoiceOver、Dynamic Type 或 Reduce Motion，When 完成位置选择，Then 不依赖 3D 动画或颜色，列表、文字状态和固定控件提供等价路径。 |
| BODY-V2-AC-010 | Given 资产 gate 未通过，When 请求 3D，Then 不读取生产模型，显示候选/回退状态并保持安全入口。 |
| BODY-V2-AC-011 | Given 窄屏选中一个 mark，When 打开编辑，Then 使用系统 Sheet/Detent 展示编辑器；大屏保持内联编辑；删除或清空后 Sheet 安全关闭。 |
| BODY-V2-AC-012 | Given Zone 与 Pin 已合计达到 20 个或 3D 发生回退，When 用户再次操作，Then 显示明确原因，VoiceOver 能读出，且不丢失已有未确认 marks。 |
| BODY-V2-AC-013 | Given 用户切换 2D/3D 或编辑位置 mark，When 状态同步到 Signal Intake，Then 每个用户动作只产生一次位置草稿修订，不覆盖结构化页已填写的感觉、程度、因素或感觉—位置关系。 |

## 4. 客户端状态契约

`BodyMark` 不进入 `body-location.schema.json`，也不作为正式身体事实。它只在当前记录会话中存在，承载位置选择和纯视觉状态；只将 `location` 同步给后续 typed Signal Intake。正式写入前必须经过用户事实复核、服务端安全检查和确认/审批链。

| 字段 | 语义 | 可写入正式档案 |
|---|---|---|
| `kind` | `zone` 或 `pin`，表示用户选择方式 | 作为来源元数据，可选 |
| `location` | 规范 `BodyLocation` 候选 | 只有用户确认后 |
| `zoneVisualState` | `none` 或 `marked` 的纯视觉状态 | 不可；不表示缓解/恶化；不得作为重复点击循环 |
| `colorToken` | 纯视觉区分，非业务含义 | 不可 |
| `selectedMarkID`、`focusedRegionID` | 当前 UI 状态 | 不可 |

状态变更必须满足：

- RealityKit 只能发出 `BodyHitEvidence`，不能直接改 `BodyMark` 或档案；
- `BodyMapModel` 是状态唯一所有者，Scene 只是镜像；
- `BodyMapModel` 只能新增、选择和删除位置候选；不得拥有感觉、程度、动作/功能线索、因素或安全字段，也不得把它们投影回 `SignalIntakeDraft`；
- 删除/清空只删除未确认草稿；正式 Event 的删除/修正继续走 DATA-01/API-01；
- 清空最后一个位置不隐式删除结构化页已填写的其他未确认事实；流程必须回到位置步骤、使旧安全失效，并把保留事实明确显示为可继续或经确认放弃的当前会话草稿；
- 任何未知资产、未知区域或低置信映射都回退到 2D/列表并要求用户复核。

## 5. 交互规则

### 5.1 Zone 模式

- 区域由项目自己的稳定 `BodyRegionCatalog`/资产实体映射提供；不从任意网格顶点推断。
- 第一次点击创建 `marked` 视觉状态并聚焦；重复点击只重新选中同一 marker。删除只能通过摘要/编辑器中的显式删除动作完成，不能由点击循环触发。
- Zone 标记按 `region_id + laterality` 去重，保留同一 marker ID；位置编辑器只可查看位置语义或删除，不可填写感觉和程度。
- “返回全身”只恢复相机和高亮，不删除位置草稿。

### 5.2 Pin 模式

- 命中已有 Pin 时先选择 Pin；命中身体才创建新 Pin。
- Zone 与 Pin 合计最多 20 个；超限不能只拒绝 Pin 或由 typed intake 截断。Pin 的颜色从固定无语义 token 循环，文字、编号和选中轮廓同时表达。
- Pin 使用命中局部位置/法线/资产版本生成 `BodyLocationAnchor3D`；不能把世界坐标作为持久化事实。
- Pin 不自动聚焦到某个医学结构；用户可以从摘要主动选择“聚焦此点”。

### 5.3 编辑器与摘要

- 面板显示 Zone/Pin、区域名称、侧别、表面、是否有精确点和位置来源；提供“下一步：描述你的感受”而不是地图内健康事实编辑。
- 感觉、程度、动作线索与自由描述统一在 typed Signal Intake 展示。结构化程度控件不提供默认值；用户主动选择 `0` 与尚未回答不同。
- 删除只删除当前未确认 marker；清空需要显式按钮，不能由误触手势触发。
- 摘要面板窄屏使用系统 Sheet/Detent 语义，不能以不可聚焦的自绘区域替代按钮。
- 窄屏选中 mark 后自动打开系统编辑 Sheet；Sheet 只镜像 `BodyMapModel`，关闭后不产生确认或正式 Event。
- 位置总上限、3D 回退和无稳定命中必须以固定文本反馈；反馈不能使用“安全”“缓解”等医疗语义。

## 6. 失败、离线与无障碍

| 场景 | 必须行为 |
|---|---|
| 资产 gate/加载失败 | 回退 2D/列表，保留 marker 草稿；不可伪造 3D 成功 |
| 命中无稳定区域 | 不静默猜测；提示选择列表或 2D 区域 |
| 网络/Agent 不可用 | 位置和结构化表单继续可用；不写 `NoRuleTriggered` 作为安全结论 |
| 设备性能不足 | 降级 3D 视觉或回退 2D；不丢位置事实 |
| VoiceOver | 以“区域/针点、部位、侧别、表面、当前编辑状态、删除”逐项读出 |
| Reduce Motion | 不执行飞行、持续旋转、扫描和闪烁；直接切换相机/焦点 |
| Dynamic Type/RTL | 不改变本体 ID/侧别；控件保持可读和可触达 |

普通日志、崩溃和遥测不得记录原始健康话语、感觉正文或完整档案。可记录的仅是脱敏交互元数据、失败类别、资产版本和耗时。

## 7. 性能与发布门禁

本切片新增行为不关闭既有 GATE-06/07/08：

- 最低支持设备触控到高亮 p95 <100ms；
- 3D 交互维持目标帧率，达不到时自动 2D 回退；
- Pin/Zone 摘要状态在视图销毁/重建后可从 `BodyMapModel` 重放；
- 所有生产资产仍必须通过来源、签名/哈希、解剖/视觉审核、区域图、真机性能、VoiceOver 和回滚证据；
- 本切片只允许内部候选模型和明确 prototype flag，不能因“交互等价”把 candidate 改成 `approved`。

## 8. 追踪与变更

| 对象 | 关联 |
|---|---|
| 产品与领域 | PRD-F01、PRD-F03A、PRD-F04、BODY-01、TERM-01 |
| iOS 与安全 | IOS-01、SAFE-01、PRIV-01、ADR-0004、ADR-0009 |
| 资产与许可 | OSS-01、BODY-ASSET-01、ADR-0018 |
| 测试 | [TEST-BODY-MAP-V2](23_REHABMATE_NATIVE_PARITY_TEST_PLAN.md)、QA-01、TRACE-01 |
| 回滚 | 关闭 3D/Parity flag；保留 2D、列表和未确认草稿 |

| 日期 | 变更 |
|---|---|
| 2026-08-08 | 根据锁定的 RehabMate commit 建立原生行为等价切片；明确视觉状态不等于缓解，不复制 Web/算法/资产 |
| 2026-08-08 | V2.1 补齐窄屏系统 Sheet、上限/回退反馈和单次草稿投影验收；不改变 BodyMark 未确认语义 |
| 2026-08-09 | V2.2 删除与 BODY-01/IOS-01 冲突的 Zone 三态点击循环：重复点击只选中已有草稿，删除改为显式动作。 |
| 2026-08-09 | V2.3 清除地图内感觉/程度/动作线索与 typed draft 覆盖路径：Body Map 只写 `BodyLocation`，多位置事实关系只在结构化录入页创建。 |
| 2026-08-09 | V2.4 统一 Zone + Pin 的 20 个位置总上限；地图和 typed draft 共享同一上限，超限显式拒绝且不截断。 |
