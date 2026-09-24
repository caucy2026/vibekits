# PAD63 远程 ADB 常驻验收（1.9.0-dev.251）

## 目标与范围

仅 Android PAD：初装仿真关闭；用户打开后，直到用户主动关闭，重启仍保持打开；界面退出时只保留低占用服务，控制端仅凭设备 ID `6795854383` 可恢复远程 ADB。关闭时撤销仿真并停止独立服务。Mac、Windows、Linux 实现未改动。

## 实现

- `PadSimulatorBootReceiver` 读取用户开启时同步写入的 `simulator_service.enabled`；只有 true 才在开机后启动 `:vibekits_harness` 前台服务，不启动 Flutter 界面。
- UI 退出时，后台服务提供仅限本机回环的控制与 MCP 最小端点；用原生连接表验证调用者和端口。UI 返回后交还原有完整端点。
- 后台服务每 15 秒检测本机 5555；端口失效时通知已安装的系统权限 ADB 辅助组件恢复 adbd。用户关闭时取消检测、关闭最小端点与服务绑定。
- 关闭状态下的设置页检查不再拉起后台服务；`stop` 完成后解除绑定。

## 真机证据

2026-09-24，KEMI Vibe Pads S1（PAD63）：

1. KEMI 签名 APK `1.9.0-dev.251` / `versionCode=2251` 安装成功；签名证书 SHA-256 为 `c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8`。
2. 用户先前已主动打开仿真。安装候选版并重启后，不手动启动应用，设备 ID 连接返回 `connected=true`、`mcpReady=true`、`adbReady=true`、`toolCount=1`、远程 ADB 序列号 `127.0.0.1:60813`。
3. 从该远程 ADB 实际执行 shell，返回型号 `KEMI Vibe Pads S1`、`service.adb.tcp.port=5555`、`init.svc.adbd=running` 和 `versionCode=2251`。
4. `ps -A` 中应用主进程不存在，仅有 `com.vibekits.vibekits:vibekits_harness` 与系统权限 ADB 辅助组件。服务的 PSS 约 30 MB。
5. 前一候选版 dev250 的同一服务架构中，在主进程不存在时强制关闭 5555/adbd；约 20 秒后服务自动恢复 5555，重新通过设备 ID 连接并实际执行远程 ADB shell 成功。dev251 只补充关闭时解除绑定，恢复逻辑未变。
6. `flutter test test/harness_simulator_target_runtime_test.dart`：12 项全部通过。`git diff --check` 通过。

## 尚未做破坏性真机操作

本轮没有在 PAD63 上主动关闭仿真开关：该机没有独立 SSH/USB 回退通道，关闭会同时停用 5555，导致无法远程重新打开。关闭路径已按代码核对，但“关闭后资源完全归零”未做此设备的实机闭环。设备目前保持用户要求的开启状态。
