# ADR-0006：iOS 未确认草稿的加密端口与同步边界

| 属性 | 值 |
|---|---|
| ADR ID | ADR-0006 |
| 状态 | Accepted for prototype / Production pending |
| 日期 | 2026-08-05 |
| 负责人 | iOS 负责人 + 隐私安全负责人 |
| 关联规范 | IOS-01 §9、DATA-01 §3.4/§13、API-01 §7.20、PRIV-01 §10/§13 |
| 关联功能 | FEAT-P4-IOS-OFFLINE-DRAFT-SYNC-SLICE |

## 背景

用户需要在断网时记录运动或日常生活中的身体感受。该数据属于高敏感健康信息；若使用 `UserDefaults`、明文文件或本地“已保存事件”标记，会造成泄露、误导和重复写入风险。另一方面，在尚未决定正式 Keychain/Data Protection/文件数据库方案前，不能把样机实现误称为生产存储。

## 决策

1. iOS Core 只定义强类型 `DraftEnvelope`、`DraftKeyProvider`、加密存储端口和 `DraftSyncQueue`；契约见 [`ios-draft-envelope.schema.json`](../contracts/ios-draft-envelope.schema.json)。
2. `DraftEnvelope` 只表达未确认输入、用户主观 `BodyLocation`、本地 draft revision 和同步状态；没有正式 Event、Approval、Report、诊断或组织损伤字段。自 P4 `schema_version=1.1` 起，每个降维后的感觉必须保留 code、可选用户标签和明确 `location_marker_ids`；关联只能指向同一 envelope 的唯一位置 ID。
3. P4 样机使用 CryptoKit AES-256-GCM、按账户隔离的进程内测试密钥和进程内密文仓，验证加密、认证失败、篡改失败、幂等删除和错误所有者隔离。该实现不可直接发布。
4. 每次同步操作使用稳定 `client_operation_id`，与未来 HTTP `Idempotency-Key` 一对一；accepted 结果只能是 `accepted_unconfirmed`。冲突保留本地 revision/digest 并要求用户处理，禁止最后写入覆盖。
5. 生产适配器必须替换 `DraftKeyProvider`/`EncryptedDraftStore`，并提供 Keychain 可访问性、Data Protection、原子写、设备锁定、备份迁移、密钥轮换、删除传播、后台任务和真机恢复证据。未完成前，P4 Feature Flag 关闭。
6. P4 `schema_version=1.0` 仅有无关联的 `sensation_codes`，无法安全重建多位置关系。当前进程内 prototype 不保存跨版本草稿，因此拒绝旧版本而不自动迁移；未来持久化实现必须先通过独立迁移和用户复核设计，禁止把一个感觉复制到所有位置。

## 未采用方案

| 方案 | 不采用原因 |
|---|---|
| `UserDefaults`/明文 JSON | 不满足健康数据静态保护和锁屏/备份边界 |
| 离线直接写 `BodySignalEvent` | 绕过服务端主体、Safety、Approval 和事务权威；会误导用户 |
| 客户端最后写入胜出 | 静默覆盖用户修订，无法解释冲突和删除 |
| 复用 RehabMate Web/GLB 存储或坐标 | 与 iOS RealityKit 生产边界、许可和位置语义冲突 |

## 后果与门禁

- 好处：离线记录和同步状态有清晰类型边界，Agent/正式档案不会因为本地缓存越权；错误密钥/篡改可 fail closed。
- 代价：生产实现仍需 Keychain、文件/数据库和服务器草稿 API，P4 样机不能作为 NFR-REL-001 通过证据；日期精度、过期策略和跨设备冲突须在正式契约中批准。
- 若未来新增远端草稿端点，必须另建 OpenAPI operation、权限/同意、ETag、保留期和删除回执设计；不得把 P4 队列自动接到 confirmed Event 写入。

## 验证入口

- [P4 功能规格](../18_IMPLEMENTED_PROTOTYPE_BASELINE.md)
- [P4 测试计划](../18_IMPLEMENTED_PROTOTYPE_BASELINE.md)
- [当前执行证据](../16_EXECUTION_EVIDENCE.md)
