# PAD63 仿真启动后 5555 未就绪：dev.244 修复与验收

日期：2026-09-24。PAD63 历史设备 ID `6795854383`，历史 LAN 地址 `192.168.3.63:5555`。

## 现场证据

- 用户在 PAD63 点击“允许作为仿真机”后界面报“系统已请求启动 adbd，但端口 5555 未就绪”。控制端对历史 LAN 地址的 ADB 连接为 `Connection refused`；按设备 ID 调用 `vibekits.simulator.connect` 返回 `remote_disabled`。因此当前不能远程读取 PAD63 的进程、辅助组件版本或实时 UID，也不能宣称该设备已恢复。
- 昨日 PAD63 验收曾记录辅助组件 `userId=1000`，但这是历史证据，不能替代当前安装状态。PAD75 上 dev.243 辅助组件 v4/UID1000 的运行中断链恢复通过，仍不能覆盖“adbd 进程正在运行但仅有 USB 模式”的情况。
- 源码中辅助组件先设置 `service.adb.tcp.port=5555`，再发 `ctl.start adbd`；当 `adbd` 本来就在运行但未监听 TCP 时，启动请求返回成功而端口仍关闭。主程序等待回环 5555 后报错并保持仿真门禁关闭。错误状态下 PAD 开关使用持久授权值显示为已开启，再点会关闭授权，不会弹出 2580 密码框。

## 修复

- 辅助组件 v5：若 5555 已监听则保持连接不动；否则写入 TCP 端口后先停再启 `adbd`，使进程重新读取端口配置。主程序的 `ensureAdbd` 要求最低 v5，自动升级旧版辅助组件。仅 Android 路径受影响，桌面 SSH/仿真路径不变。
- PAD 开关在错误状态显示为未就绪，再点击执行重新开启并要求密码；旧的持久授权不会伪装成已连接。
- 正式平台签名候选主 APK：`1.9.0-dev.244+2244`，文件 `dist/candidates/Vibekits-1.9.0-dev.244+2244-android-pad63-kemi-signed.apk`，86,829,813 字节，SHA-256 `960c34ab0af5f9dd4bc607abbda20f850f99b8a2becdd29129b3971f8dcc0570`。APK v2 签名有效，证书 SHA-256 `c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8`；内嵌辅助组件版本 5、版本名 1.4，签名相同。

## 已通过验证

- PAD75 覆盖安装 dev.244 成功，辅助组件 v5 安装成功。预置 50 秒独立救援后，用系统 UID 将 `service.adb.tcp.port` 设为 `-1` 并重启 `adbd`，原 ADB 会话断开；约 10 秒后 5555 已重新监听、`init.svc.adbd=running` 且救援未触发。临时救援文件已清理。
- 相关 Dart 静态分析无问题，`harness_simulator_target_runtime_test.dart` 12 项通过。此前 PAD75 设备 ID 远程 ADB 已实测，但这次 dev.244 的 63 号目标端仍未连通，不能将 PAD75 的结果写为 PAD63 验收。

## PAD63 仍需闭环

2026-09-24 用户在设备本地重新打开 ADB 后，已在 PAD63 覆盖安装正式平台签名的 dev.245（versionCode 2245）和辅助组件 v5（UID 1000）。通过设备 ID `6795854383` 建立 P2P/中继会话，返回 `connected=true`、`mcpReady=true`、`adbReady=true`，远程 ADB 隧道实际读取到 `KEMI Vibe Pads S1`、主程序 2245、辅助组件 v5/UID 1000。PAD63 当前远程 ADB 闭环通过；**没有在 PAD63 人为关闭 ADB**，USB-only 故障恢复仍以 PAD75 的实机结果为依据。

## dev.245：ADB 失联后保留诊断通道

- Android 启动时如果系统辅助组件暂时不能恢复 5555，仍保留已鉴权的仿真控制端点和 MCP 端点，状态明确显示“诊断通道可连接，ADB 尚未就绪”；后台探测期间也不再因 ADB 失联关闭原生仿真门禁。macOS、Windows、Linux 的 SSH 启动路径未改。
- PAD75 已覆盖安装 dev.245 和辅助组件 v5。人为停用辅助组件并关闭 adbd 后，设备 ID `9464730211` 仍返回 `connected=true`、`mcpReady=true`、`adbReady=false`；远程调用 `vibekits.simulator.status` 可读到 ADB 恢复失败原因，调用 `vibekits.system.resources` 实际取得 Android CPU/内存采样。证明 ADB 消失后控制端不再完全失明。
- 该极端试验中辅助组件被人为设为 `disabled-user`，预置的独立救援脚本未恢复它；PAD75 当前 ADB 仍不可用，须在设备本地重新启用辅助组件/ADB。**不能据此宣称已具备无条件远程重启 ADB。**普通 USB-only 的 adbd 端口故障由辅助组件 v5 自动恢复，前节 PAD75 实测通过。
- 当前 Android 没有 SSH 服务端，连接状态 `sshReady=false`。现有 SSH 工具是控制端客户端，不能当作 PAD 的备用 SSH。若要求在辅助组件也被禁用时完全远程自救，需要另行交付经鉴权的、独立于 ADB 的 PAD 端系统控制服务，并在真机上验证；不得把 MCP 只读诊断冒充系统命令执行。
- dev.245 签名候选：`dist/candidates/Vibekits-1.9.0-dev.245+2245-android-pad63-kemi-signed.apk`，86,829,813 字节，SHA-256 `a70c608b1571d22c82a14acd676b487ceb7f41fb1e119e2fa1cc2b57fb196f87`。`harness_simulator_target_runtime_test.dart` 12 项通过。

## PAD63 关闭 ADB 后恢复实测

2026-09-24 在 PAD63 dev.245 / 辅助组件 v5 / 仿真已开启状态下，通过已鉴权 ADB shell 将 `service.adb.tcp.port` 设为 `-1` 并重启 `adbd`，原远程 shell 按预期断开。随后同一设备 ID 的仿真连接仍返回 `mcpReady=true` 和 `adbReady=true`；在新远程 ADB shell 中实际读到 `service.adb.tcp.port=5555`、`init.svc.adbd=running`、设备型号 `KEMI Vibe Pads S1`。这是 PAD63 本机的 ADB TCP 关闭后自动恢复闭环。该测试没有卸载或停用系统辅助组件；辅助组件被禁用时的无条件远程自救仍未实现。
