# BodyCompanion iOS prototype

iOS Swift Package 是原生 Core/界面样机；它本身不是可发布 App。受版本控制的 `AppHost/BodyCompanionInternal.xcodeproj` 仅为内部 Simulator 提供可安装运行壳，不含签名、真实 Bundle ID、生产数据能力或发布资格。当前包括：

- 规范 `BodyLocation` 与 2D/3D 状态；
- SwiftUI 全身 2D 前/后地图、稳定区域目录和可访问部位列表；
- 本地中文/英文文字部位入口：仅从静态目录选择宽泛 Area/Zone，Pin 模式也不会伪造精确针点；
- RealityKit 原生候选模型 loader（仅 Debug prototype flag），旋转/缩放/预设视角和局部命中证据；
- 原生 Zone/Pin 双模式、Zone + Pin 合计最多 20 个位置、位置摘要/Inspector 和焦点视角；地图只产生 `BodyLocation`，感觉/动作线索/0–10 程度只在后续结构化录入中填写；重复 Zone 点击只选中已有草稿，删除必须显式完成；
- 窄屏选中 mark 的系统 Sheet/Detent 编辑、位置总上限和 3D 回退提示；
- SwiftUI 结构化身体信号录入：既有 32 个稳定感觉 code 以常用 10 项和可展开的 22 项呈现，感觉始终显式关联位置并保持未确认；普通本地安全状态下的语义感觉修订会使旧 safety/Agent/approval 失效，高风险安全行动中直接修订保持拒绝；
- 明亮中文的今天页、AI 身体助手入口、身体地图和结构化描述 P0 体验壳；AI 对话、资料读取和行动建议仍关闭；
- metadata-only `BodyAssetManifest` 运行时门禁；
- 默认关闭的研究元数据记录器；
- CryptoKit 密文草稿与同步状态机。
- `BodyCompanionInternal` 的本地/远端 Simulator UI smoke：默认关闭候选 3D、网络、Provider、权限、持久化和遥测；另有仅内部的显式候选 3D loader-entry/ready-or-fallback probe。

明确未实现：生产 approved 人体模型/anatomyMap、Keychain/Data Protection、文件 durability、后台同步、真实 API、签名安装、真机性能和完整 VoiceOver 验收。候选模型的权利、哈希和生产门禁见 [BODY-ASSET-01](../../docs/21_BODY_ASSET_PROVENANCE.md)。

## 运行

```bash
cd /Users/liuchongjiang/Documents/3D人体/ios/BodyCompanion
swift test
swift build --sdk "$(xcrun --sdk iphoneos --show-sdk-path)" \
  --triple arm64-apple-ios17.0 --target BodyCompanionIOS

cd ..
python3 ../scripts/check_internal_ios_host.py
bash ../scripts/run_internal_ios_host_tests.sh
```

### 内部可选环境变量

以下环境变量仅影响 `BodyCompanionPrototype`（macOS）启动行为，可用于快速切换 3D 身高档位分辨率：

- `BODY_COMPANION_HEIGHT_PRESET_SET`：逗号分隔身高档位（单位：米），如 `1.55,1.65,1.75,1.85`。
- `BODY_COMPANION_USER_HEIGHT_METERS`：已登录用户身高，优先单位米，可用于预选最近档位。
- `BODY_COMPANION_USER_HEIGHT_CM`：当用户身高仅有厘米值时可用，优先于无效的米值。

示例：

```bash
cd /Users/liuchongjiang/Documents/3D人体/ios/BodyCompanion
BODY_COMPANION_HEIGHT_PRESET_SET=1.55,1.65,1.75,1.85 \
BODY_COMPANION_USER_HEIGHT_METERS=1.72 \
swift run BodyCompanionPrototype
```

未设置 `BODY_COMPANION_HEIGHT_PRESET_SET` 时，Prototype 会使用默认档位集合（`1.55,1.65,1.75,1.85,1.60,1.70,1.80`）。

`4cc46e2` 的 Swift Core 94 tests、0 failures、远端 CI run `31350639359` 的 iPhone 16 / iOS Simulator 18.5 Host smoke、以及本地 iPhone 17 Pro / iOS 26.5 的 targeted H015 1/0/0（77.241s）、多位置 unknown 1/0/0（49.167s）和完整 `run_internal_host_tests.sh` exit 0（446.330s）均已通过。远端 smoke 成功日志不输出精确 XCTest 数。历史失败 run 仍保留用于回溯；所有结果仅为受控 Simulator 证据，不外推为真实设备、VoiceOver、完整 Dynamic Type、深色/高对比度、Reduce Motion、3D 性能/碰撞、签名或生产资产通过。详细边界见：

远端兼容性收据：SHA `9b6e10a` / run `31348638741` 的 `XCTIssue.isFailure` 编译失败已在 `4cc46e2` 改为跨版本 `XCTIssue.type == .assertionFailure`；随后 run `31350639359` 在 Xcode 16.4 / iPhone 16 / iOS Simulator 18.5 的 Host smoke 成功。仍仅为内部 Simulator 收据。

- [IOS-01](../../docs/04_IOS_ARCHITECTURE.md)
- [BODY-01](../../docs/08_BODY_MAP_2D_3D.md)
- [BASELINE-01](../../docs/18_IMPLEMENTED_PROTOTYPE_BASELINE.md)
- [FEAT-BODY-MAP-V1](../../docs/19_BODY_MAP_PRODUCTION_SLICE.md)
- [FEAT-BODY-MAP-V2](../../docs/22_REHABMATE_NATIVE_PARITY.md)
- [TEST-BODY-MAP-V2](../../docs/23_REHABMATE_NATIVE_PARITY_TEST_PLAN.md)
- [BODY-ASSET-01](../../docs/21_BODY_ASSET_PROVENANCE.md)
- [EVIDENCE-01](../../docs/16_EXECUTION_EVIDENCE.md)
- [FEAT-IOS-P0-RUNTIME-01](../../docs/28_IOS_P0_RUNTIME_HOST.md)
- [TEST-IOS-P0-RUNTIME-01](../../docs/29_IOS_P0_RUNTIME_HOST_TEST_PLAN.md)
