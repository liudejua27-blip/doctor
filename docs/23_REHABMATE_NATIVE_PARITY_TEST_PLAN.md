# TEST-BODY-MAP-V2：RehabMate 原生行为等价测试计划

| 属性 | 值 |
|---|---|
| 文档 ID | TEST-BODY-MAP-V2 |
| 状态 | Active implementation spec / V2.1 automated slice implemented / device evidence pending |
| 关联功能 | FEAT-BODY-MAP-V2、FEAT-BODY-MAP-V1、PRD-F03A、SAFE-INV-06、SAFE-INV-09、NFR-A11Y-001 |
| 负责人 | iOS + QA + 3D 资产 |
| 环境 | Swift Core、iOS SDK、最低支持 iPhone、RealityKit prototype harness |
| 通过解释 | 自动化通过只证明状态/契约；真机、资产和临床门禁仍需独立证据 |

## 1. 测试目标

证明原生 iOS 具备 RehabMate 用户期待的交互闭环，同时不把上游实现、资产或危险语义带入生产：

- Zone/Pin 双模式可共存且互不丢失；
- 三层视觉状态只影响 UI，不创建“已缓解”等健康事实；
- Pin 数量、颜色、选择优先级、摘要编辑和删除规则稳定；
- 旋转、缩放、四视角、焦点和回退可恢复；
- 位置仍是版本化 `BodyLocation`，无世界坐标持久化；
- 2D/列表/VoiceOver 与 3D 等价；
- 未批准资产和上游禁止内容为零引用/零加载。

## 2. 自动化覆盖矩阵

| 测试 ID | 层级 | 场景 | 期望 |
|---|---|---|---|
| TEST-BODY-V2-001 | Unit | Zone 首次选择 | 创建一个 `zone` mark，状态为 `marked`，选中并聚焦区域 |
| TEST-BODY-V2-002 | Unit | 同一区域重复选择 | 状态按 `marked → reviewing → 删除` 变化，marker ID 保持或明确删除；不产生 Check-in |
| TEST-BODY-V2-003 | Unit | Zone/Pin 切换 | 两种 mark 均保留，切换不重置摘要或选中事实 |
| TEST-BODY-V2-004 | Unit | Pin 新增 | 创建局部锚点绑定的 Pin，颜色 token 只用于视觉 |
| TEST-BODY-V2-005 | Unit | Pin 命中优先 | 选择已有 Pin，不追加重复 Pin |
| TEST-BODY-V2-006 | Unit | Pin 上限 | 第 21 个 Pin 被拒绝，已有 20 个不变 |
| TEST-BODY-V2-007 | Unit | 摘要编辑 | 感觉、动作线索、0–10 程度写入未确认 mark；空感觉不自动填值 |
| TEST-BODY-V2-008 | Unit | 强度边界 | 允许 0 和 10，拒绝/钳制越界值；`nil` 与 0 可区分 |
| TEST-BODY-V2-009 | Unit | 删除/清空 | 只删除当前草稿，选中和焦点状态同步清理 |
| TEST-BODY-V2-010 | Unit | Scene 重建 | 从 `BodyMapModel.marks` 重建同样的 Pin/Zone 视觉，不依赖 Scene 内存 |
| TEST-BODY-V2-011 | Contract | 3D 命中证据 | 缺法线、三角/重心不成对或资产版本缺失时拒绝映射并回退 |
| TEST-BODY-V2-012 | Static | 生产源码扫描 | Web 运行时、上游资产、禁止算法和世界坐标持久化引用为 0 |
| TEST-BODY-V2-013 | Unit | 2D/3D 共享位置 | 相同区域/侧别生成可比较的 `BodyLocation`，marker ID 不因显示模式改变 |
| TEST-BODY-V2-014 | Unit | 3D gate 失败 | `BodyMapModel` 进入 2D fallback，已有 marks 保留 |
| TEST-BODY-V2-015 | UI | 视角与焦点 | front/back/left/right 及返回全身按钮可操作且不删除草稿 |
| TEST-BODY-V2-016 | UI | 窄屏编辑器 | 选中 mark 自动打开系统 Sheet；中/大屏保持可访问的内联编辑；删除后安全关闭 |
| TEST-BODY-V2-017 | UI | 上限/回退反馈 | 第 21 个 Pin、3D gate 失败和无稳定命中都有固定文本/VoiceOver 反馈；已有 marks 保留 |
| TEST-BODY-V2-018 | Unit | 单次草稿投影 | 一次 mark 变化只触发一次 typed draft revision；感觉与位置关系不重复 |

## 3. 真机与无障碍矩阵

| 测试 ID | 设备/条件 | 通过门槛 |
|---|---|---|
| TEST-BODY-V2-DEVICE-001 | 最低支持 iPhone 冷启动 | 2D 可用；候选 3D 在目标时间内可交互，否则稳定回退 |
| TEST-BODY-V2-DEVICE-002 | 连续旋转/缩放 5 分钟 | 无崩溃、无误落 Pin、无明显热失控；帧率和内存记录 signpost |
| TEST-BODY-V2-DEVICE-003 | VoiceOver | 不操作 3D 也能选择区域、编辑、删除、继续 |
| TEST-BODY-V2-DEVICE-004 | Dynamic Type 最大档 | 摘要和编辑器不遮挡主要操作，文本状态可读 |
| TEST-BODY-V2-DEVICE-005 | Reduce Motion | 不飞行/闪烁/持续旋转，焦点和视角直接切换 |
| TEST-BODY-V2-DEVICE-006 | 离线/资产失败 | 2D、列表和安全入口可用，未确认草稿不丢失 |

## 4. 安全、隐私和供应链门槛

- Zone 视觉状态不能被序列化为“已缓解”、趋势或安全等级；
- 未确认 mark 不能调用正式 Event 写接口；
- 普通日志/遥测不含用户原始健康文本；
- candidate、blocked、retired 或未知版本资产不得由 RealityKit loader 读取；
- RehabMate 源码、上游人体文件和禁止算法不进入生产源码/构建包；
- 真实资产通过法务、解剖/视觉、签名/哈希、性能和 VoiceOver 评审前，3D 能力默认关闭。

## 5. 停止规则

任一以下失败立即阻止外部测试或发布：左右侧错误、3D 失败导致 2D 不可用、未批准资产加载、Pin 超过 20、已有 Pin 被误复制、空感觉被默认填充、视觉状态被当作健康事实、VoiceOver 无等价路径、原始健康文本进入日志。

## 6. 结果记录模板

每次运行记录：commit SHA、设备/系统、资产 ID/版本、测试 ID、耗时/帧率/内存、失败类别、是否回退、是否生成健康数据（必须为否）和复核人。不要记录原始对话、用户身体内容或完整截图中的个人信息。

当前结果在 [EVIDENCE-01](16_EXECUTION_EVIDENCE.md) 和 [BASELINE-01](18_IMPLEMENTED_PROTOTYPE_BASELINE.md) 更新；本地 Core 绿色不等于真机、临床、隐私或生产通过。
