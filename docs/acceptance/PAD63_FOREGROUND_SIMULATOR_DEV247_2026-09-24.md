# PAD63 仿真后台服务 dev.247 验收记录

日期：2026-09-24。目标：仿真开启后由独立、低内存的服务承载设备 ID 中继，离开界面后继续运行，不把约 485 MB 的 Flutter 界面进程当作唯一后台保障。

## 已定位

- dev.245 在 PAD63 实测：主进程约 485,670 KB PSS，中继独立进程约 30,815 KB PSS；`HarnessRelayService` 只被主进程绑定，`startForegroundCount=0`。返回桌面后暂时仍可连，但系统回收主进程后没有常驻保障。
- Android 官方 `connectedDevice` 前台服务要求声明 `FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_CONNECTED_DEVICE`、服务类型，以及 `CHANGE_NETWORK_STATE` 等前置条件；已按此改动 Android Manifest。
- dev.246 将中继改为独立前台服务，并只在仿真门禁启用后启动；关闭门禁时停止。Kotlin release 编译通过，正式平台签名 APK 版本 2246 安装到 PAD63 后，首次自动恢复发生在 Android 不允许后台启动前台服务的时机，日志为 `startForegroundService() not allowed due to mAllowStartForeground false`；服务未启动，不能视为通过。
- dev.247 修复此启动时序：后台恢复遇到系统限制时不再中断仿真门禁，待 Activity 进入前台再提升中继服务。Kotlin release 与完整 Flutter release 构建通过，平台证书 SHA-256 为 `c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8`。候选 APK：`dist/candidates/Vibekits-1.9.0-dev.247+2247-android-pad63-foreground-kemi-signed.apk`，SHA-256 `0bcc30a2aa8f8be140334547f902e45960f6061638026d858c6d9b24ccb5b5d5`。

## 当前阻塞与未通过项

- 安装 dev.247 前 PAD63 的 LAN ADB 连接变为 `device offline`，重连 192.168.3.63:5555 超时；设备 ID `6795854383` 返回远端离线；同一 LAN 地址两次 ICMP 均超时。dev.247 **尚未装入 PAD63，也未真机验收**。当前设备最后确认安装的是 dev.246，且当时仿真门禁未恢复。
- 前台常驻改动只保证独立中继进程约 30 MB 的生命周期；MCP 与仿真控制监听仍在 Flutter 主进程。若系统杀死主进程，不能宣称完整 MCP 仿真仍在线。要满足“只有低内存服务常驻且完整仿真可用”，还需把这两个监听和必要工具执行能力迁入服务进程，并测量内存及真机杀进程恢复。
- PAD63 恢复在线后，先覆盖安装 dev.247，再验证开启、通知/`isForeground`、返回桌面、主进程退出后的按 ID 连接与实际 MCP/ADB、关闭门禁撤销、进程 PSS。未通过前不发布此候选。
