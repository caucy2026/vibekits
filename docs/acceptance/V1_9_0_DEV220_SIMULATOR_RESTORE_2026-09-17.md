# dev220 升级后仿真通道自动恢复候选

状态：**BLOCK（尚未公证及目标机验收）**。源码基线 `276d971` 加本工作区未提交修改。

## 修复

`HarnessSimulatorTargetRuntime` 在中继、SSH 或端点启动失败时，关闭本次未完成的端点和原生隧道门禁，但保留用户此前持久化的仿真授权，并以有上限的退避间隔自动重试。用户明确关闭仿真时取消重试并撤销授权。旧逻辑在升级恢复失败后将授权写为 `false`，可能令刚替换自身的 VibeKits 永久失去远程仿真入口。

## 验证

- `flutter test test/harness_simulator_target_runtime_test.dart test/app_center_test.dart test/app_update_service_test.dart`：36 项通过；新增“首次中继启动失败仍保留授权并自动重试”回归。
- `flutter analyze` 对上述源码与测试无问题。
- Universal macOS Release `1.9.0-dev.220+2220` 编译成功；macOS 12+ Harness 全功能兼容检查通过；Developer ID `26T5WV4GLP` 签名并严格验签 35 个 Mach-O 文件。
- 公证候选包：`/Volumes/ORICO/kemi-build-cache/app-release-gate/vibekits/macos/dev220-simulator-recovery/Vibekits-dev220-notarization.zip`，单一顶层 `Vibekits.app`，`315468662` 字节，SHA-256 `186a3653bb0a18ae19b7f2f723deae7afc0071c7cdb0ae679ff05bb1e4e5c24e`。

## 仍需完成

新版本是不同代码内容，尚未获 Apple 公证上传授权。设备 `1321656264` 的仿真通道当前连接被重置，不能上传；需要设备端先恢复已授权的仿真入口。之后公证、装订、最终 ZIP 复验、远程安装、重连及 Harness 启动检查均未完成。
