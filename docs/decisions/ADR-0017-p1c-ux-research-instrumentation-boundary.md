# ADR-0017：P1-C 体验研究记录边界

| 属性 | 值 |
|---|---|
| ADR ID | ADR-0017 |
| 状态 | Accepted for internal metadata-only prototype; research and privacy approval required |
| 日期 | 2026-08-06 |
| 负责人 | 用户研究 + iOS + 隐私/安全 + QA |
| 关联功能 | FEAT-P1C-30S-UX-SLICE |
| 机器契约 | `p1c-ux-research-record.schema.json` |
| 关联规范 | UX-01、IOS-01、PRIV-01、QA-01、ADR-0006、ADR-0007 |

## 背景

P1-C 需要验证用户能否在不掌握解剖术语的情况下表达位置、感觉、程度、时间、影响、安全行动和“未确认”边界。研究记录本身不能复制身体描述或录屏正文，否则内部可用性工具会成为新的健康数据采集面，也会违反普通日志最小化要求。

当前路线图还没有批准真实招募、录音、录屏、云端研究仓或外部 Provider。需要先建立一个可以在内部合成演练中验证的、默认关闭的 metadata-only 记录边界。

## 决策

1. 新增 Swift Core `P1CResearchRecorder`，只在显式 `P1C_30S_UX_PROTOTYPE` 开关开启时接受记录；默认关闭，进程结束即丢失。
2. 记录只允许 `participant_alias`、五个固定任务 ID、构建版本、固定入口模式、feature flags、开始/结束时间、固定错误类别、停止规则、三项理解结果、是否使用回退和研究员澄清次数。
3. 类型系统不提供原始身体位置、感觉、强度、时间文本、功能影响、原话、用户 ID、账号、录音、录屏、文件路径、地理位置、模型输出或健康摘要字段；它们不能通过“额外字典”扩展。
4. 停止规则一旦触发，任务不能被记录为 `completed`；`completed` 必须没有停止规则。研究员澄清只记录次数，不记录澄清内容。
5. 删除是幂等的：清空内存记录和活动任务，不导出、不上传、不恢复历史。JSON Schema 只描述 finalized metadata record，不代表研究证据或临床安全证据。

## 取舍与拒绝方案

- **直接把 `SignalIntakeDraft` 或原始输入写入研究记录**：拒绝，研究工具不得扩大健康正文保存面。
- **使用通用 analytics SDK 自动采集**：拒绝，SDK 字段和跨境/留存未知，且不能保证停止规则和删除语义。
- **把一次任务完成当作安全或诊断成功**：拒绝，P1-C 只测理解和可用性，安全/临床门禁独立存在。
- **在未获同意前录音、录屏或上传**：拒绝，当前只支持脱敏现场元数据。

## 不变量与后果

- `P1C_30S_UX_PROTOTYPE` 关闭时任何 start/record/finish 都 fail closed，不泄漏记录是否存在。
- 入口模式只表达 UI 路径（2D/3D/list），不表达身体事实或 3D 坐标。
- `position_understanding` 只表达用户复述是否正确，不表示位置医学准确；`safety_action_understanding` 只表达行动理解，不表示规则正确或临床安全。
- 研究记录不能进入普通产品日志、PydanticAI 上下文、Profile、Event、Report、P4 同步队列或公开 API。
- 当前只证明类型、Schema、删除和停止语义；真实研究协议、伦理/隐私、样本量、设备和无障碍证据仍未完成。

## 验证、停止与回滚

- 验证：`TEST-P1C` 的 10 个内部契约/隐私场景、Schema 校验、Swift Core 回归、未知字段拒绝和 JSON 禁止字段扫描。
- 停止：任何 raw health content、身份 ID、录屏/录音、跨账号数据、停止规则后 completed、关闭开关仍产生记录，立即关闭 Feature Flag。
- 回滚：关闭 `P1C_30S_UX_PROTOTYPE`，清空 recorder；P1D/P1A 的位置和录入能力保持 2D/列表可用。
- 进入真实研究前必须由用户研究、隐私法务、临床安全、QA 和无障碍角色签字，并单独更新 Feature/TEST/证据；本 ADR 不授权招募或采集真实健康内容。
