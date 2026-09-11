# VibeKits v1.9.0-dev.175 本机统一 ID 与系统 SSH 仿真验收记录

## 需求对齐

- “设置 → 高级”首项固定展示本机统一 ID，并提供复制按钮。
- 远程协助与局域网仿真只使用同一个 ID。
- macOS 打开“允许作为局域网仿真机”时，由 macOS 官方管理员授权框开启 Remote Login（系统 SSH）；VibeKits 不读取或保存管理员密码。
- App 启动恢复只读检查 SSH 状态；系统 SSH 未开启时自动把过期授权状态恢复为关闭，绝不在启动阶段弹管理员授权框。
- RustDesk 传输层只允许统一 ID 隧道访问目标机回环 `127.0.0.1:22` 与 `127.0.0.1:32147`，拒绝其他目标，且不启用桌面共享。
- MCP 状态返回真实 `sshEndpoint`、`sshUsername`、阶段与错误。

## 已完成门禁

- Flutter 定向回归 95 项通过，包含 ID 置顶、低高度滚动、底部按钮、仿真状态、MCP 与传输控制。
- `flutter analyze --no-pub`：0 问题。
- Rust `simulator_gate_is_limited_to_mcp_and_system_ssh_loopback_targets`：1/1 通过。
- arm64 与 x86_64 Harness helper 分别编译成功，已合并为 Universal Mach-O；SHA-256：`7e6cd52dbfa2a9a8b68d11175159c6b3e98e4b07dc46e145301788b94c377d83`。

## 仍需真机确认

重新构建并启动 dev.175 后，需要本机用户在首次开启仿真机时完成 macOS 管理员授权；随后核对本机端口 22、UI SSH 状态，以及另一台设备通过统一 ID 建立 SSH 固定隧道。未完成这三项前不得声称远端仿真闭环完成或正式发布。

## 本机 UI 实证

- 最终候选冷启动未弹管理员授权，Harness 正常显示：`/private/tmp/vibekits-dev175-cold-start.png`。
- “设置 → 高级”首项显示统一 ID `1554650784`：`/private/tmp/vibekits-dev175-id-first.png`。
- 页面可滚动，仿真开关明确说明“由 macOS 请求管理员授权并启用系统远程登录（SSH）”：`/private/tmp/vibekits-dev175-system-ssh-switch.png`。
- App 与内置 helper 均为 `x86_64 arm64`；App 内经临时签名后的 helper SHA-256 为 `f7ea319d431efa48f9c02c0093d120f56e84d93356fa205f64e68da992bacce2`。
