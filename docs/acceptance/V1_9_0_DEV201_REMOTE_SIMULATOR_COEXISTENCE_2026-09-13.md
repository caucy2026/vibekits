# VibeKits 1.9.0-dev.201 远程仿真与并存验收记录

日期：2026-09-13

## 结论

dev.201 修正仿真目标启动顺序：固定回环 MCP 端点 `127.0.0.1:32147` 必须先真实监听，随后才开放原生 RustDesk 仿真隧道授权，避免控制端在目标仍准备时收到即时连接拒绝。

VibeKits 远程仿真保持独立：不依赖 KEMI 远程办公 App、桌面会话、进程、ID、配置、密码或 IPC。远程办公存在时仅可作为人工观察辅助；VibeKits 仍通过自己的 MCP、SSH/SFTP 和 ADB 通道完成工作。双方同时运行时不得互相启动、停止、切换或占用会话。

## 自动门禁

- macOS 全量 `flutter analyze`：0 issue。
- macOS 远程仿真启动、控制端、RustDesk Harness、生命周期组合：32 passed，真实双机用例按环境开关跳过。
- Windows 58 D 盘定向分析：0 issue。
- Windows 58 远程仿真、SSH、ADB、Harness 工具桥与 RustDesk Harness 组合：77/77 passed。
- 新增真实双机 ADB 验收步骤：设备目录、`getprop ro.product.model`、有界 logcat、push/pull 字节回环，以及显式提供测试 APK 时的覆盖安装。

## macOS 候选

- 版本：`1.9.0-dev.201+2201`。
- Universal：`x86_64 arm64`；最低系统：macOS 12.0。
- 36 个 Mach-O 使用 `Developer ID Application: zhen ji (26T5WV4GLP)` 签名；签名后本地 Harness 工具桥真实响应。
- Apple 公证：`Accepted`，Submission ID `b1793214-20e7-4dac-ad61-744fc83a2dd0`。
- staple/validate、深度验签和 Gatekeeper `Notarized Developer ID` 通过。
- ZIP：`/Volumes/ORICO/kemi-build-cache/vibekits-dev201/delivery/Vibekits-1.9.0-dev.201+2201-macOS-universal-notarized.zip`
- 大小：311,504,238 bytes。
- SHA-256：`ea3c5b5ac1c246d2b18918ba3c26dad781e5d196678545d5a50bd1e41b89a14e`。

## Windows 候选

- Windows 58 D 盘增量 Release 构建成功，耗时 795.4 秒。
- 包内版本 `1.9.0-dev.201+2201`；Git 2.55.0.windows.3、GitHub CLI 2.100.0、Lark CLI 1.0.92 和 41 项自包含运行时门禁通过。
- Session 0 使用独立数据目录真实启动 20 秒，进程保持运行并生成 164-byte Harness bridge；随后只关闭该测试进程。
- ZIP：`/Volumes/ORICO/kemi-build-cache/vibekits-dev201/delivery/Vibekits-1.9.0-dev.201+2201-windows-x64-final.zip`
- 大小：302,356,754 bytes。
- SHA-256：`6eacf24a03f7fec80e047e39551f30125b2f956206fe6a688939193d493fa1aa`。
- 当前 Windows 包未取得 Authenticode 证据；可作为已真实启动的测试候选，不得表述为已签名 Windows 正式包。

## 真实并存与剩余双机门禁

本机真实观察到 KEMI 远程办公主进程、连接管理器与 `VibekitsHarness` 中继同时持续运行；VibeKits 中继返回 routing ID `1554650784`、HBBS online、registration key confirmed，查询过程未启动、停止或切换远程办公会话。

目标 ID `4456560334` 的 P2P 优先与强制 HBBR 两轮实测都在连接固定目标 `127.0.0.1:32147` 时被目标端拒绝，说明目标机当前运行包没有让仿真 MCP 端点真实就绪，而不是单一线路选择问题。必须在该目标安装本页精确 dev.201 公证包、重新打开仿真开关后，继续完成两轮 MCP、SSH/SFTP、日志和 ADB 真机闭环；该证据取得前不得宣称远程仿真最终完成或发布到正式渠道。

## 独立运行与 PAD75 补充证据

- 2026-09-13 再次运行独立中继、仿真目标生命周期和远程控制会话组合测试，29/29 通过；覆盖只使用 App 内置 `vibekits-harness-relay`、拒绝 KEMI 远程办公可执行路径、独立 ID、固定端点、旧中继精确接管、配对后项目/会话状态同步和统一断开清理。
- 本机 VibeKits 独立中继返回 routing ID `1554650784`、`callable=true`、HBBS online、registration key confirmed；同一时间 KEMI 远程办公保持自己的进程和会话，VibeKits 查询未启动、停止或切换它。
- PAD75（`192.168.3.75:5555`）在线；旧版 VibeKits `1.9.0-dev.188+2188` 与 KEMI 远程办公同时运行且 PID 独立。63 当前不在线，因此 63 真机门禁仍为环境阻塞。
- 从提交 `c48c0f2` 的冻结源码在 ORICO 隔离目录构建 Android arm64 Release 成功，APK 版本 `1.9.0-dev.201+2201`、大小 146,107,136 bytes、SHA-256 `4332c85aa75e545d439efa7931cf67e48eda1391e0cef9591078d148b93da409`。
- PAD75 已安装 dev.188 的证书 SHA-256 为 `c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8`，本次隔离 APK 的证书为 `fc84f538928007fb20d1ee43b8fb6bde465708c694b86fdd6a012fef19e2d5aa`。两者不兼容，未执行会清除数据的卸载；该 APK 不得作为 PAD75 覆盖升级候选。
- 通过已授权 KEMI 远程办公 ID 尝试的只回环 SSH 辅助隧道在 45 秒内未建立。该结果只作为可选辅助通道状态记录，不影响 VibeKits 独立协议判定，也未停止或更改远程办公会话。
