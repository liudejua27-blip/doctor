# TEST-BODY-MAP-V1：2D/3D 身体定位测试计划

| 属性 | 值 |
|---|---|
| 关联需求/功能 | FEAT-BODY-MAP-V1、FEAT-BODY-MAP-V2、PRD-F03A、SAFE-INV-09、NFR-A11Y-001 |
| SafetyBaseline | 不调用 SafetyEngine；位置非诊断边界必须保持 |
| 负责人 | iOS + QA + 3D 资产 |
| 环境 | Swift Core、iOS SDK、最低支持 iPhone、RealityKit prototype harness |
| 状态 | Active implementation spec / local Core、iOS build、文字部位 Area-only、完整感觉入口与候选 3D Simulator evidence recorded；`0105cd7` remote CI success；device gate open |

## 1. 测试目标和风险

要证明 2D、3D 和列表只产生同一位置契约的候选；最严重失败包括左右侧错误、前后表面错误、3D 世界坐标被持久化、未批准资产进入运行时、3D 失败阻断 2D、VoiceOver 无等价路径，以及把视觉区域误报为医学组织。

## 2. 覆盖矩阵

| 测试 ID | 需求/不变量 | 层级 | 场景 | 期望 | 自动化 |
|---|---|---|---|---|---|
| TEST-BODY-001 | PRD-F03A | Unit | 2D 前视图区域边界 | 返回稳定 region/laterality/surface/normalized anchor | 是 |
| TEST-BODY-002 | PRD-F03A | Unit | 2D 后视图同一区域 | 不改变 marker UUID；surface 为 posterior | 是 |
| TEST-BODY-003 | SAFE-INV-09 | Contract | 位置编码 | 不含疾病、组织或病因字段 | 是 |
| TEST-BODY-004 | NFR-A11Y-001、ADR-0003 | Unit/UI | 文字列表搜索/选择左右侧 | 中英文目录查询仅返回当前视图的静态选项；选择生成 `body_part_search` 的 `Area/Zone + region_mask_id`，即使 Pin 模式也没有 point | 是/待真机 |
| TEST-BODY-005 | PRD-F03A | Unit | 2D/3D 切换 | UUID、region、laterality 保持 | 是 |
| TEST-BODY-006 | ADR-0004 | Unit | 3D evidence 缺法线/重心不一致 | 返回 nil/回退，不崩溃 | 是 |
| TEST-BODY-007 | ADR-0018 | Unit | 未批准/blocked/retired manifest | 不加载模型，返回 fallback | 是 |
| TEST-BODY-008 | ADR-0009 | Static | 禁止 RehabMate 实现/资产扫描 | 无 Web/Three.js/GSAP/body.glb 生产引用 | 是 |
| TEST-BODY-009 | PRD-F03A | Device | 最低设备 3D 冷启动/旋转/缩放 | 达到 signpost 目标或回退 2D | 待真机 |
| TEST-BODY-010 | NFR-A11Y-001 | Accessibility | VoiceOver/Reduce Motion/Dynamic Type/对比度 | 无 3D 可通过“文字选择部位”入口搜索、选择 Area、继续；accessibility size 下状态、回退和主要动作不裁切且可分别聚焦；动画可关闭；深色/高对比度下文字不依赖浅色强调色 | Internal Host 结构 smoke + 待真机 |
| TEST-BODY-011 | PRD-F01 | Integration | 选位置后进入结构化描述 | 未确认位置保留，未自动填感觉 | 待联调 |
| TEST-BODY-012 | PRD-F03A | Recovery | 3D loader/命中/内存失败 | 提示原因，保留草稿，2D/列表可继续 | Unit + Device |
| TEST-BODY-013 | PRD-F03A | Simulator probe | 显式内部候选 Bundle 加载 | 先观察当前 Scene 的 `onLoadAttempted` 运行时确认，再只接受内部候选状态+列表入口，或加载/初始化错误、8 秒超时后的固定 2D 回退+列表入口；不点击网格、不创建位置事实 | 是 / 非真机 |
| TEST-BODY-014 | PRD-F03A | Unit | 3D attempt 状态权威 | 只有当前 `request3D()` attempt 的 `onLoadAttempted` 后 `onReady` 可以进入 3D ready；初始/2D interactive、跳过确认、切回 2D 后的旧回调或被新请求替代的旧回调均不得改变当前状态 | 是 |
| TEST-BODY-015 | PRD-F03A、NFR-A11Y-001 | UI | 共享文字入口 | 2D、候选 3D ready 与候选回退均能打开同一可搜索列表；无结果不改变位置草稿，选中后只显示待确认 Area 反馈 | 是 / 非真机 |

V2 的行为等价、Zone/Pin 共存、Zone + Pin 合计 20 个位置上限、位置摘要/Inspector、焦点和已有点命中优先规则见 [TEST-BODY-MAP-V2](23_REHABMATE_NATIVE_PARITY_TEST_PLAN.md)。地图只产生位置候选；感觉、程度和因素的结构化编辑另由 P1D 验收。

## 3. 测试数据治理

区域目录使用合成的稳定 ID 和无健康正文的几何 fixture。人体资产必须带来源、哈希、许可证和 attribution；真实用户位置不可写入普通测试日志。golden hit set 只在资产/解剖审核后进入锁定分区。

## 4. 通过门槛

| 指标 | 必须达到 |
|---|---|
| 2D/列表契约一致性 | 100% |
| 左右/前后映射错误 | 0 |
| 未批准资产加载 | 0 |
| 世界坐标持久化 | 0 |
| 3D 失败后 2D 完整回退 | 100% |
| VoiceOver 无 3D 等价完成 | 100% |
| RehabMate 禁止实现/资产引用 | 0 |

## 5. 缺陷与停止规则

任何左右侧错误、未批准资产加载、位置被解释为病因/组织、2D 回退不可用、未知字段被静默接受或无障碍路径缺失，均停止外部测试。修复后必须重跑受影响测试以及跨视图回归。

## 6. 结果与签字

- `9fc54d4` 本地 Core 全量：87 tests、0 failures；除 canonical location 投影、同 ID 位置语义替换后的感觉复核、删除最后一个关联位置时不保留空感觉关系，以及候选 3D attempt 的 loader-entry/ready 与旧回调失效外，还覆盖本地中英文目录搜索、当前视图筛选、Pin 模式文字选择固定为 `Zone + Area + body_part_search + region_mask_id`、无 Point/3D anchor、重复选择不增加 typed draft revision；`scripts/check_baseline.py` 的最终收据见 EVIDENCE-01；
- iOS `BodyCompanionIOS` 与 `BodyCompanionPrototype` generic iOS Debug build：绿色（无签名）；
- `79f1f36`：本地 iPhone 17 Pro / iOS 26.5 的 9 项内部 Host UI 测试通过；`TEST-BODY-013` 实际观察到当前候选 Scene 的 loader-entry → candidate-ready → 3D 场景/列表入口，未点击网格、未创建位置事实；`TEST-BODY-014` 由 Core 回归锁定当前 attempt 与旧回调失效。`ea85c68` 的远端 CI run `31301067572` 已成功重建完整 Host suite；CI 不把 ready/fallback 分支外推为资产质量；
- `9fc54d4`：本地 iPhone 17 Pro / iOS 26.5 的 10 项 Internal Host UI 流程通过；`TEST-BODY-004/015` 验证 2D 文字搜索“膝”可选择“左膝附近”、无结果不写草稿，候选专属 ready-or-fallback 终态与默认 2D fallback 均保留同一文字入口；不点击网格，文字条目始终是宽泛 Area/Zone。远端 CI run `31303340128` 已成功完成后端/契约、Swift tests、SDK build、Host boundary 与 internal Host smoke；
- `0105cd7`：在同一内部 Simulator 完成 94 项 Swift Core、iPhoneOS SDK build、Host 静态检查和 12 项 UI 流程。它从既有位置入口进入结构化描述，展开“更多感觉（22 项）”并选择“麻木”，只保留带显式 marker 关联的未确认草稿；两位置时分别显示局部和全组 unknown 文案。该集成路径不点击网格、不产生 Point/3D anchor、不把位置解释为组织或病因。语义感觉修订的普通状态失效与高风险拒绝由 Core 覆盖；GitHub Actions run `31307042209` 已在 iPhone 16 / iOS Simulator 18.5 成功重建 Backend and contracts、Swift 94、SDK build、Host boundary 与 internal Host smoke；
- 真机性能与无障碍证据：未运行前不得标记通过；
- 资产权利/解剖签字：未完成前保持候选状态；
- 发布评审：必须绑定 commit SHA、AssetManifest、区域目录和同一测试结果。
- `TEST-BODY-013` 当前本地只补充候选 Scene 已进入加载入口且实际成功终态可达；它不关闭 TEST-BODY-009/010/012 的真机、性能、命中、无障碍或资产审批要求。
