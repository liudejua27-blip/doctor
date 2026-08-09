# TEST-BODY-MAP-V1：2D/3D 身体定位测试计划

| 属性 | 值 |
|---|---|
| 关联需求/功能 | FEAT-BODY-MAP-V1、FEAT-BODY-MAP-V2、PRD-F03A、SAFE-INV-09、NFR-A11Y-001 |
| SafetyBaseline | 不调用 SafetyEngine；位置非诊断边界必须保持 |
| 负责人 | iOS + QA + 3D 资产 |
| 环境 | Swift Core、iOS SDK、最低支持 iPhone、RealityKit prototype harness |
| 状态 | Draft / local Core and iOS build evidence recorded; device gate open |

## 1. 测试目标和风险

要证明 2D、3D 和列表只产生同一位置契约的候选；最严重失败包括左右侧错误、前后表面错误、3D 世界坐标被持久化、未批准资产进入运行时、3D 失败阻断 2D、VoiceOver 无等价路径，以及把视觉区域误报为医学组织。

## 2. 覆盖矩阵

| 测试 ID | 需求/不变量 | 层级 | 场景 | 期望 | 自动化 |
|---|---|---|---|---|---|
| TEST-BODY-001 | PRD-F03A | Unit | 2D 前视图区域边界 | 返回稳定 region/laterality/surface/normalized anchor | 是 |
| TEST-BODY-002 | PRD-F03A | Unit | 2D 后视图同一区域 | 不改变 marker UUID；surface 为 posterior | 是 |
| TEST-BODY-003 | SAFE-INV-09 | Contract | 位置编码 | 不含疾病、组织或病因字段 | 是 |
| TEST-BODY-004 | NFR-A11Y-001 | Unit/UI | 列表选择左右侧 | 与图形路径生成相同契约 | 是/待真机 |
| TEST-BODY-005 | PRD-F03A | Unit | 2D/3D 切换 | UUID、region、laterality 保持 | 是 |
| TEST-BODY-006 | ADR-0004 | Unit | 3D evidence 缺法线/重心不一致 | 返回 nil/回退，不崩溃 | 是 |
| TEST-BODY-007 | ADR-0018 | Unit | 未批准/blocked/retired manifest | 不加载模型，返回 fallback | 是 |
| TEST-BODY-008 | ADR-0009 | Static | 禁止 RehabMate 实现/资产扫描 | 无 Web/Three.js/GSAP/body.glb 生产引用 | 是 |
| TEST-BODY-009 | PRD-F03A | Device | 最低设备 3D 冷启动/旋转/缩放 | 达到 signpost 目标或回退 2D | 待真机 |
| TEST-BODY-010 | NFR-A11Y-001 | Accessibility | VoiceOver/Reduce Motion/Dynamic Type | 无 3D 完成选择，动画可关闭 | 待真机 |
| TEST-BODY-011 | PRD-F01 | Integration | 选位置后进入结构化描述 | 未确认位置保留，未自动填感觉 | 待联调 |
| TEST-BODY-012 | PRD-F03A | Recovery | 3D loader/命中/内存失败 | 提示原因，保留草稿，2D/列表可继续 | Unit + Device |
| TEST-BODY-013 | PRD-F03A | Simulator probe | 显式内部候选 Bundle 加载 | 先观察当前 Scene 的 `onLoadAttempted` 运行时确认，再只接受内部候选状态+列表入口，或加载/初始化错误、8 秒超时后的固定 2D 回退+列表入口；不点击网格、不创建位置事实 | 是 / 非真机 |
| TEST-BODY-014 | PRD-F03A | Unit | 3D attempt 状态权威 | 只有当前 `request3D()` attempt 的 `onLoadAttempted` 后 `onReady` 可以进入 3D ready；初始/2D interactive、跳过确认、切回 2D 后的旧回调或被新请求替代的旧回调均不得改变当前状态 | 是 |

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

- 本地 Core 全量：82 tests、0 failures；其中 V2.5 覆盖 canonical location 投影、同 ID 位置语义替换后的感觉复核，以及删除最后一个关联位置时不保留空感觉关系；`scripts/check_baseline.py`：61 Markdown、345 links、16 Schema、36 OpenAPI paths、1 候选资产清单、禁止源码引用 0；
- iOS `BodyCompanionIOS` 与 `BodyCompanionPrototype` generic iOS Debug build：绿色（无签名）；
- 真机性能与无障碍证据：未运行前不得标记通过；
- 资产权利/解剖签字：未完成前保持候选状态；
- 发布评审：必须绑定 commit SHA、AssetManifest、区域目录和同一测试结果。
- `TEST-BODY-013` 只补充候选 Scene 已进入加载入口且其最终成功/回退路径可达；它不关闭 TEST-BODY-009/010/012 的真机、性能、命中、无障碍或资产审批要求。
