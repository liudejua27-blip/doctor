# TEST-BODY-MAP-V2：原生 iOS 身体地图交互测试计划

| 属性 | 值 |
|---|---|
| 文档 ID | TEST-BODY-MAP-V2 |
| 状态 | Active implementation spec / V2.6 text-list Area semantics implemented / device run blocked |
| 关联功能 | FEAT-BODY-MAP-V2、FEAT-BODY-MAP-V1、PRD-F03A、SAFE-INV-06、SAFE-INV-09、NFR-A11Y-001 |
| 负责人 | iOS + QA + 3D 资产 |
| 环境 | Swift Core、iOS SDK、最低支持 iPhone、RealityKit prototype harness |
| 通过解释 | 自动化通过只证明状态/契约；真机、资产和临床门禁仍需独立证据 |

## 1. 测试目标

证明原生 iOS 具备 RehabMate 用户期待的交互闭环，同时不把上游实现、资产或危险语义带入生产：

- Zone/Pin 双模式可共存且互不丢失；
- Zone 重复选择只重新选中已有草稿，删除必须是显式动作；不创建“已缓解”等健康事实；
- Pin 数量、颜色、选择优先级、位置摘要和删除规则稳定；
- Body Map 只产生 `BodyLocation`，不能写入或覆盖结构化感觉、程度、因素或感觉—位置关系；
- 旋转、缩放、四视角、焦点和回退可恢复；
- 位置仍是版本化 `BodyLocation`，无世界坐标持久化；
- 2D/列表/VoiceOver 与 3D 等价；
- 未批准资产和上游禁止内容为零引用/零加载。

## 2. 自动化覆盖矩阵

| 测试 ID | 层级 | 场景 | 期望 |
|---|---|---|---|
| TEST-BODY-V2-001 | Unit | Zone 首次选择 | 创建一个 `zone` mark，状态为 `marked`，选中并聚焦区域 |
| TEST-BODY-V2-002 | Unit | 同一区域重复选择 | 保持同一个 `marked` marker，重新选中并聚焦，不循环到另一视觉状态、不删除、不产生 Check-in |
| TEST-BODY-V2-003 | Unit | Zone/Pin 切换 | 两种 mark 均保留，切换不重置摘要或选中事实 |
| TEST-BODY-V2-004 | Unit | Pin 新增 | 创建局部锚点绑定的 Pin，颜色 token 只用于视觉 |
| TEST-BODY-V2-005 | Unit | Pin 命中优先 | 选择已有 Pin，不追加重复 Pin |
| TEST-BODY-V2-006 | Unit | 位置总上限 | 第 21 个 Zone 或 Pin 被拒绝，已有 Zone + Pin 合计 20 个不变，typed draft 不发生截断 |
| TEST-BODY-V2-007 | Unit | 位置摘要边界 | 位置摘要只读/删除 Zone 或 Pin、区域、侧别、表面与来源；不存在感觉、动作线索或程度字段 |
| TEST-BODY-V2-008 | Integration | 结构化程度边界 | `SignalIntakeScreen` 中允许用户主动选择 0 和 10；未填写与 0 可区分，地图不能写入程度 |
| TEST-BODY-V2-009 | Unit | 删除/清空 | 只删除当前草稿，选中和焦点状态同步清理 |
| TEST-BODY-V2-010 | Unit | Scene 重建 | 从 `BodyMapModel.marks` 重建同样的 Pin/Zone 视觉，不依赖 Scene 内存 |
| TEST-BODY-V2-011 | Contract | 3D 命中证据 | 缺法线、三角/重心不成对或资产版本缺失时拒绝映射并回退 |
| TEST-BODY-V2-012 | Static | 生产源码扫描 | Web 运行时、上游资产、禁止算法和世界坐标持久化引用为 0 |
| TEST-BODY-V2-013 | Unit | 2D/3D 共享位置 | 相同区域/侧别生成可比较的 `BodyLocation`，marker ID 不因显示模式改变 |
| TEST-BODY-V2-014 | Unit | 3D gate 失败 | `BodyMapModel` 进入 2D fallback，已有 marks 保留 |
| TEST-BODY-V2-015 | UI | 视角与焦点 | front/back/left/right 及返回全身按钮可操作且不删除草稿 |
| TEST-BODY-V2-016 | UI | 窄屏编辑器 | 选中 mark 自动打开系统 Sheet；中/大屏保持可访问的内联编辑；删除后安全关闭 |
| TEST-BODY-V2-017 | UI | 上限/回退反馈 | 第 21 个 Zone 或 Pin、3D gate 失败和无稳定命中都有固定文本/VoiceOver 反馈；已有 marks 保留 |
| TEST-BODY-V2-018 | Unit | 单次位置同步 | 一次 mark 变化（包含文字目录 Area 选择）只触发一次 typed draft revision；地图只同步位置，不能重写感觉与位置关系 |
| TEST-BODY-V2-019 | Unit | 同 ID 位置替换与删除关系收敛 | `SignalIntakeModel` 接受的 canonical location 必须投影回地图；同 `marker_id` 的内容替换使感觉复核/全局未知失效但不复制感觉；删除最后一个关联 marker 时移除该未确认感觉，不留下空关系 |
| TEST-BODY-V2-020 | Simulator probe | 显式内部候选 3D 加载/回退 | 先观察当前 Scene 的 `onLoadAttempted`，再只接受“内部候选状态 + 共享文字列表入口”或“加载/初始化错误、8 秒超时后的固定 2D 回退 + 同一入口”；不得通过点击网格推导位置、碰撞或区域准确性 |
| TEST-BODY-V2-021 | Unit | 3D attempt 状态权威 | 仅当前 Scene attempt 的 `onLoadAttempted` 后 `onReady` 可标成 ready；初始/2D interactive、直接改 mode、切回 2D 或被新请求替代的失效 attempt 不得显示“候选已加载” |
| TEST-BODY-V2-022 | Unit/UI | 文字部位选择边界 | 本地中英文目录搜索只显示静态当前视图选项；无结果不改变草稿；无论当前 Zone/Pin 模式，选择均创建单个 `zone` 的 `Area + region_mask_id + body_part_search`，不生成代表性 Point；2D/候选 ready/回退都能进入同一列表 |

## 3. 真机与无障碍矩阵

| 测试 ID | 设备/条件 | 通过门槛 |
|---|---|---|
| TEST-BODY-V2-DEVICE-001 | 最低支持 iPhone 冷启动 | 2D 可用；候选 3D 在目标时间内可交互，否则稳定回退 |
| TEST-BODY-V2-DEVICE-002 | 连续旋转/缩放 5 分钟 | 无崩溃、无误落 Pin、无明显热失控；帧率和内存记录 signpost |
| TEST-BODY-V2-DEVICE-003 | VoiceOver | 不操作 3D 也能打开文字部位入口、按中文/英文目录搜索、选择宽泛区域、编辑、删除、继续；列表不会生成 Pin |
| TEST-BODY-V2-DEVICE-004 | Dynamic Type 最大档 | 摘要和编辑器不遮挡主要操作，文本状态可读 |
| TEST-BODY-V2-DEVICE-005 | Reduce Motion | 不飞行/闪烁/持续旋转，焦点和视角直接切换 |
| TEST-BODY-V2-DEVICE-006 | 离线/资产失败 | 2D、列表和安全入口可用，未确认草稿不丢失 |

## 4. 安全、隐私和供应链门槛

- Zone 重复点击不能改变/删除草稿；删除只能由显式动作触发，且视觉状态不能被序列化为“已缓解”、趋势或安全等级；文字列表不得以代表性中心点或 Pin 模式伪造精确针点；
- 任何 Map 状态不得含有感觉、程度、动作线索、因素、功能影响或安全答案；这些字段只由 typed Signal Intake 显式产生；
- 未确认 mark 不能调用正式 Event 写接口；
- 普通日志/遥测不含用户原始健康文本；
- candidate、blocked、retired 或未知版本资产不得由 RealityKit loader 读取；
- RehabMate 源码、上游人体文件和禁止算法不进入生产源码/构建包；
- 真实资产通过法务、解剖/视觉、签名/哈希、性能和 VoiceOver 评审前，3D 能力默认关闭。

## 5. 停止规则

任一以下失败立即阻止外部测试或发布：左右侧错误、3D 失败导致 2D 不可用、未批准资产加载、Zone + Pin 合计超过 20 或被 typed draft 静默截断、已有 Pin 被误复制、空感觉被默认填充、视觉状态被当作健康事实、VoiceOver 无等价路径、原始健康文本进入日志。

## 6. 结果记录模板

每次运行记录：commit SHA、设备/系统、资产 ID/版本、测试 ID、耗时/帧率/内存、失败类别、是否回退、是否生成健康数据（必须为否）和复核人。不要记录原始对话、用户身体内容或完整截图中的个人信息。

当前结果在 [EVIDENCE-01](16_EXECUTION_EVIDENCE.md)、[EVIDENCE-DEVICE-01](24_DEVICE_VALIDATION_EVIDENCE.md) 和 [BASELINE-01](18_IMPLEMENTED_PROTOTYPE_BASELINE.md) 更新；本地 Core 绿色不等于真机、临床、隐私或生产通过。设备不可用时，必须把维度标为 `Blocked/Pending`，不得用 Simulator 或 SDK 编译替代真机证据。

`79f1f36` 的本地 iPhone 17 Pro / iOS 26.5 内部 Host 套件为 9 项通过：`TEST-BODY-V2-020` 先观察 loader-entry，实际到达 candidate-ready 并保留 3D 场景/列表；`TEST-BODY-V2-021` 由 Core 回归覆盖当前 attempt 与替代后旧回调失效。`ea85c68` 的远端 CI run `31301067572` 已成功重建完整 Host suite，但不把 ready/fallback 分支作为资产质量结论。

`9fc54d4` 的本地 Swift Core 为 87 项通过，Internal Host 为 10 项通过：`TEST-BODY-V2-018/022` 覆盖本地中英文文字目录、无结果不写草稿、一次位置同步只推进一次 revision，以及 Pin 模式下文字选择仍强制生成单个 `zone` 的 `Area + region_mask_id + body_part_search`，没有代表性 Point。候选显式 probe 的 ready-or-fallback 终态与默认 2D fallback 都能打开同一文字入口；不点击网格，文字流只创建未确认的宽泛 `BodyLocation`，不产生精确网格命中/3D 位置证据或已确认健康事实。远端 CI run `31303340128` 已成功完成后端/契约与 iOS internal Host 验证；所有真机、命中、性能、资产与无障碍维度保持 `Blocked/Pending`。
