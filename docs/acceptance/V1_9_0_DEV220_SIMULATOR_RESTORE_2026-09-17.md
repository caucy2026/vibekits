# dev220 升级后仿真通道自动恢复候选

状态：**候选（尚未公证及目标机验收）**。源码已纳入 `713aea4`；此改动针对潜在的升级恢复缺陷，尚未证明是设备 `1321656264` 此前断线的根因。

## 修复

`HarnessSimulatorTargetRuntime` 在中继、SSH 或端点启动失败时，关闭本次未完成的端点和原生隧道门禁，但保留用户此前持久化的仿真授权，并以有上限的退避间隔自动重试。用户明确关闭仿真时取消重试并撤销授权。旧逻辑在升级恢复失败后将授权写为 `false`，可能令刚替换自身的 VibeKits 永久失去远程仿真入口。

## 验证

- `flutter test test/harness_simulator_target_runtime_test.dart test/app_center_test.dart test/app_update_service_test.dart`：36 项通过；新增“首次中继启动失败仍保留授权并自动重试”回归。
- `flutter analyze` 对上述源码与测试无问题。
- Universal macOS Release `1.9.0-dev.220+2220` 编译成功；macOS 12+ Harness 全功能兼容检查通过；Developer ID `26T5WV4GLP` 签名并严格验签 35 个 Mach-O 文件。
- 公证候选包：`/Volumes/ORICO/kemi-build-cache/app-release-gate/vibekits/macos/dev220-simulator-recovery/Vibekits-dev220-notarization.zip`，单一顶层 `Vibekits.app`，`315468662` 字节，SHA-256 `186a3653bb0a18ae19b7f2f723deae7afc0071c7cdb0ae679ff05bb1e4e5c24e`。

## 仍需完成

新版本是不同代码内容，尚未公证或部署。设备 `1321656264` 已由设备所有者重新启动 dev219 并恢复仿真连接；这证明不能凭先前连接重置判断 dev219 启动失败。dev220 的公证、装订、最终 ZIP 复验、远程安装和目标机回归均未完成。
