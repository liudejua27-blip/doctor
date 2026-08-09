# BodyCompanion iOS prototype

iOS Swift Package 是原生 Core/界面样机；它本身不是可发布 App。受版本控制的 `AppHost/BodyCompanionInternal.xcodeproj` 仅为内部 Simulator 提供可安装运行壳，不含签名、真实 Bundle ID、生产数据能力或发布资格。当前包括：

- 规范 `BodyLocation` 与 2D/3D 状态；
- SwiftUI 全身 2D 前/后地图、稳定区域目录和可访问部位列表；
- 本地中文/英文文字部位入口：仅从静态目录选择宽泛 Area/Zone，Pin 模式也不会伪造精确针点；
- RealityKit 原生候选模型 loader（仅 Debug prototype flag），旋转/缩放/预设视角和局部命中证据；
- 原生 Zone/Pin 双模式、Zone + Pin 合计最多 20 个位置、位置摘要/Inspector 和焦点视角；地图只产生 `BodyLocation`，感觉/动作线索/0–10 程度只在后续结构化录入中填写；重复 Zone 点击只选中已有草稿，删除必须显式完成；
- 窄屏选中 mark 的系统 Sheet/Detent 编辑、位置总上限和 3D 回退提示；
- SwiftUI 结构化身体信号录入；
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

`9fc54d4` 当前 Swift Core 为 87 tests、0 failures；内部 Host 在本地 iPhone 17 Pro / iOS 26.5 通过 10 项 UI 流程，包含 2D 文字搜索、无结果不写草稿，以及候选 ready/fallback 的共享文字入口。文字选择始终是待确认 Area/Zone，不读取网络、资料、历史或 Agent，不写正式档案。远端 CI run `31303340128` 已成功完成后端/契约以及 iOS Swift tests、SDK build、Host boundary、internal Host smoke；历史基础 7 项和此前完整 Host suite 已在远端 run `31301067572` 中成功重建。任何远端 probe 只验证受控的有效终态，不把 ready/fallback 分支外推为真实设备、签名、无障碍、3D 性能/碰撞或生产资产通过。详细边界见：

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
