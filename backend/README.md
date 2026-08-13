# Backend prototype

后端是隔离样机，不是生产 API。当前验证的边界包括：

- 确定性 SafetyEngine 先于普通 Agent；
- PydanticAI typed deps/output 和 PolicyValidator；
- scope/owner/expiry/allowlist 约束的只读资料上下文；
- iOS typed intake 的严格适配；
- Session/Turn/ConfirmationIntent/Approval 的 revision、前驱和幂等；
- fake repository 中有限 write set、全有/全无和 read-back 关系。

明确未实现：真实 Provider、OIDC、Consent、PostgreSQL、分布式锁/幂等、生产审计、公开纵向 API 和临床评测。

## 运行

```bash
cd /Users/liuchongjiang/Documents/3D人体
./.venv311/bin/python -m pip install -c backend/constraints-test.txt -e './backend[test]'
./.venv311/bin/python scripts/check_baseline.py
./.venv311/bin/python -m pytest backend/tests --tb=short
./.venv311/bin/python -m compileall -q backend/src backend/tests scripts
./.venv311/bin/python -m pip check
```

当前本地聚合结果为 204 tests、0 failures；P2A 默认时钟由测试 fixture 冻结，过期边界继续显式注入时间。该结果仍不等于真实 Provider、数据库或临床安全已验证，详细证据见 [EVIDENCE-01](../docs/16_EXECUTION_EVIDENCE.md)。

架构、契约和当前实现说明：

- [AGENT-01](../docs/05_AGENT_ARCHITECTURE.md)
- [API-01](../docs/07_API_CONTRACT.md)
- [BASELINE-01](../docs/18_IMPLEMENTED_PROTOTYPE_BASELINE.md)
- [FRAME-01](../docs/17_FRAMEWORK_IMPLEMENTATION_BLUEPRINT.md)
