# TEST-IOS-P0-RUNTIME-01：内部 iOS App Host 与 Simulator 测试计划

| 属性 | 值 |
|---|---|
| 测试 ID | TEST-IOS-P0-RUNTIME-01 |
| 版本 | 0.1.0-draft |
| 状态 | Draft / 尚未执行 |
| 关联功能 | FEAT-IOS-P0-RUNTIME-01、FEAT-COMP-01 P0、FEAT-BODY-MAP-V1/V2 |
| 负责人 | iOS + QA + 无障碍负责人（待 GOV-01 指定） |
| 依赖 | IOS-01、PRIV-01、QA-01、BODY-01、TEST-BODY-MAP-V1/V2、TEST-COMP-01、EVIDENCE-DEVICE-01 |
| 发布意义 | 内部 Simulator smoke；不构成真机、签名、临床、生产 3D 或生产 App 验收 |

## 1. 目标

证明受版本控制的 `BodyCompanionInternal` 可以作为 iOS Simulator App 启动，并在不启用网络、Provider、真实资料读取、正式写入、持久化或产品分析的情况下，运行既有 P0 页面与完整 2D/列表回退。

## 2. 环境与数据

| 项目 | 规定 |
|---|---|
| Xcode | 当前受支持 Xcode；实际版本写入执行证据 |
| Destination | 明确的 iPhone Simulator UDID/名称和 iOS runtime；不得把 Simulator 记为真机 |
| 数据 | 仅空白/合成测试状态；不得使用真实身体信号、真实账号、真实截图/录屏或生产 Provider |
| Host 模式 | `DebugInternal` 或等价内部配置；UI test 默认禁用候选 3D |
| 网络 | 断言无应用发起的网络/Provider 请求；测试工具下载不属于产品网络能力 |
| 记录 | 仅保存命令、构建版本、成功/失败、截图中不含真实健康内容的合成状态 |

## 3. 自动化覆盖矩阵

| 测试 ID | 场景 | 断言 | 层级 |
|---|---|---|---|
| HOST-T-001 | 工程发现 | `xcodebuild -list` 有 project、App scheme、UI test target | 静态/构建 |
| HOST-T-002 | Simulator 编译与安装 | 生成 Simulator `.app`，可由 XCTest 启动 | 集成 |
| HOST-T-003 | 冷启动今天页 | “今天”“记录这次不适”和非诊断说明存在；无“已恢复/已保存” | UI |
| HOST-T-004 | 多入口一致 | 今天、记录、AI 身体助手都可进入同一位置草稿路径 | UI |
| HOST-T-005 | 2D/列表路径 | 不依赖候选 3D 选择一个合成部位，进入结构化描述 | UI |
| HOST-T-006 | 草稿继续 | 进入草稿后返回入口，再继续时保持同一进程内位置数和流程状态 | UI |
| HOST-T-007 | 新建确认 | 有草稿时“新建”先显示放弃对话框；取消不 reset；确认后才 reset | UI |
| HOST-T-008 | 普通 AI 关闭 | AI 身体助手明确显示“普通对话尚未接入”；不存在建议、行动或资料已使用断言 | UI |
| HOST-T-009 | 候选 3D 回退 | UI test 配置下显示 2D/列表或明确内部候选/回退提示；不得依赖碰撞命中 | UI |
| HOST-T-010 | 权限与网络负向 | 无 HealthKit/相机/麦克风/照片/通知权限提示、无 Provider/URLSession 入口、无分析 SDK | 静态 + 运行时 |
| HOST-T-011 | 存储负向 | 无 UserDefaults/Keychain/文件/数据库健康草稿写入；重启不宣称恢复 | 静态 + UI |
| HOST-T-012 | identifier 与动态文字基础 | 主要按钮、路径状态和确认操作有稳定 identifier/可见中文文字；不得只以颜色传达状态 | UI 静态 + Simulator |

## 4. 必须保留的现有回归

- `cd ios/BodyCompanion && swift test`；
- `BodyCompanionIOS` iPhoneOS SDK build；
- 后端完整测试与 `scripts/check_baseline.py`；
- TEST-BODY-MAP-V1/V2 的 Core 边界、P0 map-only 与 20 个总位置上限；
- TEST-COMP-01 的 P0 AI 关闭、草稿继续/新建与非诊断边界。

## 5. 无障碍与设备证据边界

Simulator smoke 可以证明 accessibility identifier、可见文案、无 3D 入口和基础布局没有在启动时崩溃；它**不能**替代：

- 开启 VoiceOver 的完整交互、焦点顺序或朗读正确性；
- 最大 Dynamic Type、横屏、Switch Control 或外接键盘体验；
- Reduce Motion 的系统行为；
- 真机 GPU、热、内存、触控、RealityKit 碰撞或候选资产性能；
- Team/证书/签名、真实设备安装或 App Store 审查。

这些项目仍按 EVIDENCE-DEVICE-01、TEST-BODY-MAP-V1/V2、IOS-01 和 GATE-06/08 跟踪。

## 6. 通过条件与停止规则

通过 Simulator Host smoke 的最低条件：HOST-T-001～012 全部通过、原有回归不退化、无新增 API/Schema/健康字段，且输出证据明确标记为内部 Simulator。

以下任一项失败即停止：2D/列表不能完成、草稿被静默丢弃或误称保存、普通 AI/建议被伪造、检测到网络/Provider/权限/持久化/分析入口、候选 3D 没有回退、或文档把 Simulator 外推为真机/生产。

## 7. 执行证据模板

```text
commit: <sha>
project/scheme: BodyCompanionInternal.xcodeproj / BodyCompanionInternal
destination: <simulator name + runtime + UDID>
configuration: DebugInternal
commands: <xcodebuild build-for-testing / test>
result: passed | failed
covered test IDs: HOST-T-001 ...
not proven: 真机、签名、VoiceOver 实操、最大 Dynamic Type、Reduce Motion、3D 性能/碰撞、资产许可、临床/生产发布
```

## 8. 变更记录

| 日期 | 变更 | 说明 |
|---|---|---|
| 2026-08-09 | 新建 TEST-IOS-P0-RUNTIME-01 | 将内部 App Host 的构建、启动、UI smoke、无网络/无权限/无持久化负向检查与真机不可外推边界固定下来。 |
