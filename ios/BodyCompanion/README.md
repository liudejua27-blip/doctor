# BodyCompanion iOS prototype

iOS Swift Package 是原生 Core/界面样机，不是可发布 App。当前包括：

- 规范 `BodyLocation` 与 2D/3D 状态；
- SwiftUI 结构化身体信号录入；
- metadata-only `BodyAssetManifest` 运行时门禁；
- 默认关闭的研究元数据记录器；
- CryptoKit 密文草稿与同步状态机。

明确未实现：真实人体模型 loader、生产 anatomyMap、Keychain/Data Protection、文件 durability、后台同步、真实 API、签名安装、真机性能和完整 VoiceOver 验收。

## 运行

```bash
cd /Users/liuchongjiang/Documents/3D人体/ios/BodyCompanion
swift test
swift build --sdk "$(xcrun --sdk iphoneos --show-sdk-path)" \
  --triple arm64-apple-ios17.0 --target BodyCompanionIOS
```

当前 Swift Core 为 51 tests、0 failures；这不证明真实设备或生产资产。详细边界见：

- [IOS-01](../../docs/04_IOS_ARCHITECTURE.md)
- [BODY-01](../../docs/08_BODY_MAP_2D_3D.md)
- [BASELINE-01](../../docs/18_IMPLEMENTED_PROTOTYPE_BASELINE.md)
- [EVIDENCE-01](../../docs/16_EXECUTION_EVIDENCE.md)
