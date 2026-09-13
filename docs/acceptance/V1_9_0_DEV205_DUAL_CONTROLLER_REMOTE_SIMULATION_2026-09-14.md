# VibeKits 1.9.0-dev.205 双控制端远程仿真验收

日期：2026-09-14

## 本轮目标

Windows 58 与 PAD 63 都作为控制端，仅凭统一设备 ID 连接同一台已允许远程仿真的 Mac。Windows 必须具备 MCP、SSH 命令和文件传输能力；Android PAD 必须能读取真实 MCP 工具目录并完成远端进程与文件自检。远程桌面不是本轮依赖，也不能替代仿真数据面。

## 根因与修复

受管 RustDesk 字节隧道在目标端走独立 Harness 快速路径，不启动远程桌面 Connection Manager。旧实现却只从 Connection Manager 查询控制端身份，导致真实隧道已经到达 `32147`，目标仍无法确认调用方，从而把首次 `ssh_authorize` 挂起等待界面批准并在 30 秒后断开。

dev.205 在 RustDesk Harness 服务进程内登记由原生握手得到的真实 `peer_id`、连接号和固定转发目标，并把该登记表合并进 Harness 连接状态。连接结束立即删除登记。授权判断仍依赖原生握手身份或既有受管 SSH 公钥，不信任可伪造的 HTTP 请求头，也没有放宽普通 LAN MCP 权限。

控制端同时把首次 `vibekits.device.ssh_authorize` 的等待窗口提升到两分钟，其余 MCP 调用仍保持八秒超时，避免真正需要用户首次批准时被短超时提前切断。

## 自动与实机证据

- RustDesk macOS 单测：`managed_tunnel_registry_survives_without_connection_manager`，1/1 通过。
- RustDesk Windows 58 Release 单测：同一用例 1/1 通过。
- VibeKits 共享回归：远程仿真控制器、Android 双屏合同和主页远程状态共 18/18 通过。
- macOS 候选：`1.9.0.205 (2205)`；主程序及内置 Harness Relay 均为 `x86_64 + arm64`，完整 macOS 12+ 运行时门禁通过。
- Developer ID：`Developer ID Application: zhen ji (26T5WV4GLP)`；36 个 Mach-O 深度严格验签通过，签名后 Node/DSH 实启通过。
- Apple 公证：`Accepted`，Submission ID `d28c4486-3056-4e3a-8d1b-dd628be02c98`；ticket 已 staple/validate，Gatekeeper 为 `Notarized Developer ID`。
- 最终 Mac ZIP：`/Volumes/ORICO/kemi-build-cache/vibekits-dev205/delivery/Vibekits-1.9.0-dev.205+2205-macOS-universal-notarized.zip`，311,597,307 bytes，SHA-256 `2465b92b35954b81ef6ca5f04f4953f70db12035273210b3d55fba745c3c5368`。
- PAD 63（`1.9.0-dev.204+2204`）连接目标 Mac ID `1554650784`：真实显示 `204 项工具`，并报告“进程与文件自检通过”。
- Windows 58 连接同一目标：强制 HBBR 与直连优先/自动回退两条路径均通过；每次均取得 204 项工具、SSH 就绪、远程命令、28 字节 SFTP 上传与远端 SHA-256 回读。
- 目标 Mac 原生连接表在 Windows 测试期间记录真实控制端 `peerId=8296293831`、`authorized=true`、`portForward=127.0.0.1:22`，证明授权来自原生 P2P 隧道身份而非请求头。
- Windows 新 Relay SHA-256：`CFE1F22B6D4B3CB09C13D1940634DDC69EF8C4434589DD31D012AB4E15C6F615`，已同步到构建包和源码运行时目录；旧文件保留为 `*.pre-dev205.exe` 便于回滚。

## 结论与剩余发布门禁

本轮“58 和 63 双向作为控制端仿真目标 Mac”已通过，且 Windows 的 SSH/文件能力与 PAD 的 MCP 能力均为真实设备证据。dev.205 Mac 已完成 Developer ID、公证、staple、Gatekeeper 和最终归档校验，可以作为本轮正式 Mac 交付候选。
