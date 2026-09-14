# VibeKits dev.210 无界面 Relay 与配对门禁（2026-09-14）

## 结论

`1.9.0-dev.210+2210` 已完成本机协议回归、静态检查、Universal macOS 12+ Release 构建和 Developer ID 深度签名。当前包尚未获得 Apple 公证票据，因此只允许作为签名测试候选，不得标记正式发布或上传 KEMI 商场。

## 本轮修复

1. 控制端首次配对先建立响应监听并写入配对请求，再等待 RustDesk P2P/HBBR 载体进入 `transport_connected`，避免需求驱动隧道在首个应用帧发出前一直等待。
2. 受管隧道关闭先发 `SIGTERM`；超时后必须 `SIGKILL` 并确认进程退出，禁止断开后遗留后台端口和连接。
3. 桌面端启动器新增 `HARNESS_HEADLESS_RELAY_REQUIRED` 硬门禁。即使旧配置或调用方显式传入 RustDesk/KEMI 远程办公主程序，也会在启动进程前拒绝；macOS/Linux 只接受 `vibekits-harness-relay`，Windows 只接受 `vibekits-harness-relay.exe`。
4. 清理本机遗留的 dev.205 测试候选、relay 和 KEMI 远程办公前台进程。新回归只使用假进程，不建立真机连接或桌面会话。
5. 真实远程应用验收新增可选的完整生命周期门禁：上传签名包、覆盖升级、启动、进程/日志/截图检查、按唯一身份卸载、确认应用消失、使用同一校验包恢复安装并重新启动。只有设置 `VIBEKITS_REAL_REMOTE_UNINSTALL_RESTORE=1` 才执行卸载，最终保持应用已安装、可运行。

## 已通过证据

- 远程协议与仿真组合回归：`108/108` 通过。
- 覆盖：首次密码校验与证书配对、证书固定和防篡改、授权范围、项目/会话快照、命令反馈、独立停止、断线与重连、直连/HBBR 参数、隧道强制回收、仅凭 ID 的 SSH 公钥引导、文件上传及主机指纹校验、PAD 控制端限制。
- `flutter analyze --no-pub`：`No issues found`。
- Release 构建：成功，App 约 `823.2 MB`。
- 兼容性脚本：App、Harness、ADB、7-Zip、GitHub CLI、Git、Flutter frameworks 全部为 `arm64 + x86_64`，最低系统为 macOS 12.0。
- Developer ID：`Developer ID Application: zhen ji (26T5WV4GLP)`；36 个 Mach-O 完成 Hardened Runtime、时间戳、Team ID 与深度严格验签；Harness Node 保留 JIT 权限并可启动 DSH。
- 签名候选：`dist/candidates/Vibekits-1.9.0-dev.210+2210-macos-universal-developer-id-signed.zip`
- SHA-256：`6174d54633a195df49d1c0de4e91c273fed0d0a053b9e53c0279ebc0f7f7aa41`
- ZIP 结构：单一顶层 `Vibekits.app`，无 `__MACOSX`。
- 远程应用生命周期验收脚本已通过编译和静态分析；当前未连接目标机，实际更新—卸载—恢复结果仍属于下方未通过门禁。

## 仍未通过的发布门禁

1. Apple 公证上传被当前工具审批阻断；尚无 `Accepted`、staple 或 Gatekeeper `Notarized Developer ID` 证据。
2. 目标 `4456560334` 尚未安装 dev.210，因此不能把旧 dev.207 的 `PAIRING_CHANNEL_CLOSED` 当成新版本结果。安装精确候选后仍需真实验证首次授权、第二次免授权、项目/会话同步、命令/反馈/停止，以及上传、卸载、安装、启动、日志和截图。
3. 63 真机 ADB 已恢复在线，型号为 `KEMI Vibe Pads S1`，但设备上没有安装 `com.vibekits.vibekits`。dev.210 Android Release 构建在下载 Gradle 8.14.3 时网络超时，未生成 APK，因此不得声称 63 已通过。
4. Windows 同源逻辑已有 Dart 回归覆盖，但本轮尚未在 Windows 58 的 D 盘重新构建并真实启动；不得声称 Windows Release 已通过。

## 下一步验收顺序

1. 获得精确 ZIP 的 Apple 公证上传授权，完成 `Accepted`、staple、Gatekeeper 和最终 ZIP 重封装。
2. 在目标 Mac 安装同一精确 dev.210，后台按 ID 完成配对与仿真闭环；全程不得启动远程桌面 UI。
3. 恢复 63 后验证 Android/PAD 控制端连接、命令和停止。
4. 在 Windows 58 的 D 盘用同一源码构建 Release，完成随包 relay、Harness、安装启动和共享逻辑门禁。
