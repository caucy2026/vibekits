# PAD63 仿真后台服务 dev.247 验收记录

日期：2026-09-24。目标：仿真开启后由独立、低内存的服务承载设备 ID 中继，离开界面后继续运行，不把约 485 MB 的 Flutter 界面进程当作唯一后台保障。

## 已定位

- dev.245 在 PAD63 实测：主进程约 485,670 KB PSS，中继独立进程约 30,815 KB PSS；`HarnessRelayService` 只被主进程绑定，`startForegroundCount=0`。返回桌面后暂时仍可连，但系统回收主进程后没有常驻保障。
- Android 官方 `connectedDevice` 前台服务要求声明 `FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_CONNECTED_DEVICE`、服务类型，以及 `CHANGE_NETWORK_STATE` 等前置条件；已按此改动 Android Manifest。
- dev.246 将中继改为独立前台服务，并只在仿真门禁启用后启动；关闭门禁时停止。Kotlin release 编译通过，正式平台签名 APK 版本 2246 安装到 PAD63 后，首次自动恢复发生在 Android 不允许后台启动前台服务的时机，日志为 `startForegroundService() not allowed due to mAllowStartForeground false`；服务未启动，不能视为通过。
- dev.247 修复此启动时序：后台恢复遇到系统限制时不再中断仿真门禁，待 Activity 进入前台再提升中继服务。Kotlin release 与完整 Flutter release 构建通过，平台证书 SHA-256 为 `c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8`。候选 APK：`dist/candidates/Vibekits-1.9.0-dev.247+2247-android-pad63-foreground-kemi-signed.apk`，SHA-256 `0bcc30a2aa8f8be140334547f902e45960f6061638026d858c6d9b24ccb5b5d5`。

## 当前阻塞与未通过项

- 早先安装 dev.247 前 PAD63 短暂离线，随后恢复 LAN ADB。已在 PAD63 覆盖安装 dev.247，`versionCode=2247`，不清数据。启动后设备 ID `6795854383` 返回 `connected=true`、`mcpReady=true`、`adbReady=true`。
- 服务在约 17 秒后成功提升为 Android 前台服务，`isForeground=true`、通知 ID 32148。按 HOME 后，独立中继进程 PSS 约 30–31 MB，远程 `vibekits.simulator.status` 和 ADB shell 均实际成功。此项后台保活通过。
- **完整仿真仅靠服务常驻仍未通过**：按 HOME 后用 `am kill com.vibekits.vibekits` 模拟系统回收 Flutter 界面进程，中继服务进程仍在、`isForeground=true`，但新设备 ID 会话无法访问 `127.0.0.1:32148`，返回 `Failed to access remote ...32148`。根因是仿真控制与 MCP HTTP 监听仍属 Flutter 主进程。重新打开 APP 后约数秒按 ID 连接恢复 `mcpReady=true`、`adbReady=true`；测试结束已返回桌面，服务仍在前台。
- 要满足“只有低内存服务常驻且完整仿真可用”，还需把控制/MCP 监听及其所需工具执行能力迁入服务进程，或实现经过真机验证的后台按需启动机制；不得用仅有中继存活冒充完整仿真通过。关闭门禁撤销、进程被回收后的完整 MCP/ADB、服务内存上限均是发布门禁，未通过前不发布此候选。
