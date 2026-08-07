# ADR-0008：iOS 结构化录入的服务端适配边界

| 属性 | 值 |
|---|---|
| 决策 ID | ADR-0008 |
| 状态 | Accepted for prototype; production/API review required |
| 日期 | 2026-08-05 |
| 关联功能 | FEAT-P1D、FEAT-P1E |
| 关联规范 | DOC-00、DATA-01、AGENT-01、API-01、SAFE-01、PRIV-01、ADR-0002、ADR-0007 |

## 1. 背景

P1D 已在 Swift Core 中形成了严格的 `SignalIntakeDraft`，但客户端 JSON 还不能直接交给 PydanticAI 或现有 `AssessmentDraft`。如果没有单独的服务端适配层，容易发生三类越界：客户端安全状态被当成权威、多个位置被错误复制到每个感觉、未确认候选直接进入正式事件。

## 2. 决策

新增一个纯领域适配模块 `body_companion.domain.ios_signal_intake`：

1. 使用 `extra="forbid"` 的 Python/Pydantic 模型严格解析 `ios-signal-intake.schema.json`；
2. 先做 session/revision、位置关系、来源边界和必需事实校验，再按显式规则映射到 `AssessmentDraft`；P1D 当前没有服务端签发的 Profile source ID，因此 `profile` 身体事实一律拒绝；
3. 客户端安全字段只用于一致性/诊断，普通 Agent 必须等待 Application Service 传入本次服务端 `SafetyEvaluation`；
4. 以 `IOSSignalIntakeAdapterResult` 表达 `needs_safety_precheck`、`ready_for_agent`、`safety_action_required`、`offline_only` 和 `rejected`；
5. 适配器不创建 HTTP operation，不触碰 Event/Episode/ApprovalStore，不读取额外 Profile 或原始文件；
6. PydanticAI 仍只接收经过服务端安全和 P3 typed context 绑定的 `AssessmentDeps`，不接收客户端 DTO。

## 3. 被否决的选项

### 3.1 让 iOS 直接提交 `AssessmentDraft`

否决。客户端无法赋予服务端所有权、确认、规则版本或资料权限；这样会绕过 P1B/P2/P3 的边界。

### 3.2 让适配器相信客户端 `ordinary_agent_allowed`

否决。客户端状态可被篡改，也可能来自旧规则版本；安全必须在服务端按当前 SafetyBaseline 重新运行。

### 3.3 为 P1E 临时增加一个“保存事件”端点

否决。P1D/P1E 只解决 DTO 边界；任何写入必须继续走 P2 的两阶段确认和服务端事务，不能用方便联调的端点制造正式历史。

### 3.4 没有 marker 关系时复制到全部位置

否决。复制会把用户未表达的空间关系伪装成事实；适配器应拒绝并要求客户端补充明确关系。

## 4. 后果

正面：客户端与后端可以独立演进；安全、来源、确认和正式写入边界可测试；未来公开 API 不会被内部样机模型绑死。

代价：Swift 与 Python 需要共同维护 schema/fixture；P1D 必须补充每个感觉的 marker 关系；真实联调前仍需认证、Consent API、规则内容和版本化错误码。

## 5. 验证与回滚

- 依据 `TEST-P1E` 运行严格解析、门禁、来源、空间关系、无副作用和现有 PolicyValidator 测试；
- 任何适配失败只关闭 P1E 入口，保留 P1A 2D 位置和 P4 未确认草稿；
- 若未来公开 API 不兼容，新增明确 adapter/version，不修改既有 `AssessmentDraft` 或 `BodyLocation` 的稳定含义；
- P1E 样机不能生成有效 SafetyBaseline，也不能进入生产构建。
