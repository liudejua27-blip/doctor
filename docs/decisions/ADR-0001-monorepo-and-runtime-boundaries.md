# ADR-0001：单仓库与运行时边界

- 状态：Accepted for design baseline
- 日期：2026-08-05
- 关联需求：PRD-F01、PRD-F02、PRD-F06
- 关联文档：ARCH-01、IOS-01、AGENT-01、API-01

## 背景

产品同时包含原生 iOS 体验、3D 资产、Python Agent、确定性安全规则、业务 API、机器契约和评测。若拆成多个无统一版本的仓库，跨端字段、人体位置版本、SafetyBaseline 和发布证据容易漂移；若把所有逻辑放入一个运行时，又会让 LLM、UI 与正式事实混在一起。

## 决策

采用一个逻辑单仓库（monorepo）管理文档、iOS、后端、资产流水线和评测，但保持严格运行时边界：

```text
ios app ── HTTPS ── API/application services ── domain repositories
                         ├── deterministic safety engine
                         ├── PydanticAI assessment agent
                         ├── approved content service
                         └── audit/consent services

anatomy asset pipeline ── signed manifests ── iOS asset catalog/CDN
docs/contracts ── generated clients + contract tests ── ios/backend
```

- iOS 不嵌入 Python/LLM，也不持有服务端授权真相。
- Agent 不直接连接数据库表，不承担红旗最终判断，不直接写正式档案。
- 应用服务编排认证、授权、安全、Agent、确认、幂等和持久化。
- 人体资产构建与运行时分离；手机只消费已验证 Manifest 和映射。
- 共享只发生在版本化契约、稳定 ID 与发布基线，不共享运行时内部模型。

计划目录：

```text
ios/
backend/
anatomy-assets/
docs/contracts/
docs/decisions/
evals/
```

## 否决方案

### 多仓库立即拆分

首发团队规模和契约成熟度不足，容易产生同步与权限摩擦。未来若团队/发布节奏独立，可在保持契约和基线自动校验的前提下拆分。

### 全部逻辑在 iOS 本地

无法安全管理模型密钥、统一规则/内容、跨设备档案和审计；版本碎片会让安全行为不可控。

### 全部体验做 Web/WKWebView

不能满足原生可访问性、性能、生命周期、资产和长期维护目标，也违背 RehabMate 仅作交互参考的边界。

## 后果

- 优点：同一变更可同时更新规格、Schema、客户端、服务端和测试；SafetyBaseline 可绑定一次构建中的全部对象。
- 代价：需要路径责任人、选择性 CI、生成代码检查和清晰模块边界，避免“单仓库 = 任意耦合”。
- 风险：仓库初期文档多于代码；这是有意的阶段设计，代码脚手架只有在 DoR 后创建。

## 验证与重新评估

- 首个纵向切片必须证明 OpenAPI 生成、iOS/API 契约测试和 SafetyBaseline 可在同一 CI 中校验。
- 当独立团队、访问隔离或发布频率使单仓库明显阻塞时，重新评估物理拆仓；逻辑边界保持不变。
- 任何拆分必须保留不可变契约版本、跨仓库兼容门禁和发布证据聚合。
