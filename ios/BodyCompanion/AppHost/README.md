# BodyCompanionInternal App Host

这是一个受版本控制、仅限内部的 iOS Simulator App Host。它只链接父目录 Swift Package 的 `BodyCompanionIOS`；候选 render/collision USDZ 与映射/相机 JSON 由本 target 显式复制进 App Bundle。可复用的 `BodyCompanionIOS` Swift Package 本身不再携带候选资产，生产 target 不会因链接 UI 库而隐式分发候选模型。

默认运行能力：2D/部位列表和进程内未确认草稿。候选 3D 只有在手动运行或专用 probe 显式设置 `BODY_COMPANION_ENABLE_CANDIDATE_3D=1` 才可尝试；默认 UI smoke 关闭它，专用 probe 则先确认当前 loader-entry 后只接受 ready 或安全回退。Host 不接入网络、Provider、正式写入、分享、Keychain、文件持久化、遥测或系统健康/媒体权限。

```bash
cd /Users/liuchongjiang/Documents/3D人体
python3 scripts/check_internal_ios_host.py
bash scripts/run_internal_ios_host_tests.sh
```

> 该 AppHost 入口不读取 `BODY_COMPANION_HEIGHT_PRESET_SET`；该环境变量仅在 `BodyCompanionPrototype`（macOS 可执行）中生效，用于快速调整 3D 身高档位集合。

如需固定目标，可在执行前设置 `BODY_COMPANION_SIMULATOR_UDID`；脚本只会选择可用的 iPhone Simulator，且不改变设备内容或启动任何生产服务。

通过只可记录为 `Simulator host smoke passed`。它不证明真机、签名、VoiceOver、最大 Dynamic Type、Reduce Motion、3D 性能/碰撞、资产许可、临床安全或生产发布。规范和完整测试范围见 [FEAT-IOS-P0-RUNTIME-01](../../../docs/28_IOS_P0_RUNTIME_HOST.md) 与 [TEST-IOS-P0-RUNTIME-01](../../../docs/29_IOS_P0_RUNTIME_HOST_TEST_PLAN.md)。
