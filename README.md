# AI Body Companion（AI 身体伴侣）

> 当前状态：方案、框架、契约和样机基线已完成；生产纵向闭环尚未完成。

AI Body Companion 面向运动和久坐办公人群，把“哪里不舒服、什么感觉、何时出现、哪些动作加重或缓解、影响什么”转化为用户确认、可追踪、可比较、可行动的身体信号数据。产品不诊断、不处方、不排除严重疾病，也不替代医生。

## 技术方向

- iOS：SwiftUI + RealityKit 原生实现；2D 是完整路径，3D 是增益输入。
- Agent：固定 `pydantic-ai-slim==2.23.0`，只负责强类型理解、最小追问、未确认草稿和受控只读工具。
- 安全：确定性规则先于普通 LLM；权限、确认、正式写入和审计位于 Agent 之外。
- 资产：真实人体模型必须通过作者链、许可、哈希/签名、解剖、性能和无障碍门禁。
- 开源：[PydanticAI](https://github.com/pydantic/pydantic-ai) 是 Agent 框架；[RehabMate](https://github.com/HUANGCHIHHUNGLeo/RehabMate) 只提供交互思想，不复制其 Web 技术栈、区域算法或人体资产。

## 文档入口

1. [文档总索引](docs/README.md)
2. [产品需求](docs/01_PRODUCT_REQUIREMENTS.md)
3. [系统架构](docs/03_SYSTEM_ARCHITECTURE.md)
4. [iOS 架构](docs/04_IOS_ARCHITECTURE.md)
5. [Agent 架构](docs/05_AGENT_ARCHITECTURE.md)
6. [安全与临床边界](docs/09_SAFETY_AND_CLINICAL_CONTENT.md)
7. [当前交付路线图](docs/13_DELIVERY_ROADMAP.md)
8. [当前追踪矩阵](docs/14_TRACEABILITY_MATRIX.md)
9. [已实现样机基线](docs/18_IMPLEMENTED_PROTOTYPE_BASELINE.md)
10. [当前验证证据](docs/16_EXECUTION_EVIDENCE.md)

早期总体方案和 32 份已完成的一次性 Feature/Test 切片已经归并并删除。长期规范、ADR、Schema、许可证据和测试代码仍保留。

## 当前代码

- `backend/`：Safety、PydanticAI typed Agent、授权上下文、确认/幂等/事务边界样机。
- `ios/BodyCompanion/`：身体位置、结构化录入、AssetManifest、研究元数据和离线草稿 Core 样机。
- `docs/contracts/`：OpenAPI 与 16 个 JSON Schema。
- `.github/workflows/ci.yml`：后端/契约与 iOS 双作业 CI；Action 固定完整 SHA。
- `scripts/check_baseline.py`：本地与 CI 共用的文档、契约、依赖和禁止引用门禁。

这些实现使用进程内/fake repository、TestModel/FunctionModel 和 metadata-only 资产门禁，不能作为生产业务能力。

## 最短下一步

P2A 受控时钟回归、后端 189 个测试、Swift 51 个测试、本地 CI 等价检查和首个 Git 分支/提交基线已建立。当前没有远端，因此云端 CI 首跑、默认分支和保护规则仍待远端创建后完成。

1. 配置远端，运行首次 GitHub Actions，并把绿色检查设为默认分支必需状态。
2. 完成实名责任角色、首发地区和产品边界决策。
3. 关闭临床安全、Provider/Consent、正式数据库、真实资产/设备和端到端验证门禁。

完整顺序见 [REL-01](docs/13_DELIVERY_ROADMAP.md)。
