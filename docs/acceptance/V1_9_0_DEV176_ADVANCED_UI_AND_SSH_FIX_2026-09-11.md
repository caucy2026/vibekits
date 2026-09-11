# VibeKits v1.9.0-dev.176 高级页面与 SSH 修复验收记录

## 本次修复

- “本机 ID”改为单行紧凑展示；统一 ID 的用途只在鼠标悬停后通过圆角提示显示，移开立即消失。
- 局域网仿真只展示简短状态；SSH 地址、用户及连接方式放入悬停提示，主界面不再出现与当前能力无关的桌面类说明。
- 集群任务改为独立开关并默认开启。服务地址尚未配置时进入“等待配置服务器”，不联网、不领取任务，也不影响 Harness；配置表单按需展开。
- macOS SSH 启停不再依据 `systemsetup` 的退出码判断。原生桥接经系统管理员授权后固定调用 `launchctl` 管理 `com.openssh.sshd`，Dart 层仍以回环端口 22 的真实连通性作为最终成功条件。

## 自动门禁

- `flutter analyze`：0 问题。
- 集群配置、SSH、仿真运行时、MCP 工具桥和高级页面定向测试：70 项通过，1 项既有跳过。
- 高级页面精确 UI 用例验证：集群默认开启、未配置文案、悬停出现圆角说明、移出后说明消失。
- macOS 原生桥接源码门禁验证：必须包含 sshd enable/bootstrap/disable，禁止重新引入 `systemsetup -setremotelogin` 假成功路径。

## 构建门禁

- Release：`build/macos/Build/Products/Release/Vibekits.app`。
- 版本：`1.9.0.176 (2176)`，界面显示 `v1.9.0-dev.176+2176`。
- 主程序架构：`x86_64 arm64`。
- `codesign --verify --deep --strict`：通过；本地构建签名不等同于 Developer ID 公证发布包。

## 真机门禁

首次开启局域网仿真必须由本机用户在 macOS 系统授权框输入管理员密码。授权完成后，只有回环端口 22 实际监听、UI 显示“已开启”，并从另一台已授权设备通过统一 ID 建立固定 SSH 隧道，才算远端仿真闭环完成。

## 2026-09-11 本机授权实证

- macOS 管理员授权完成，`launchd` 成功加载 `system/com.openssh.sshd`。
- `127.0.0.1:22` 与本机 LAN 地址 `192.168.3.65:22` 均完成 TCP 连接和 OpenSSH 10.2 握手；监听范围为 IPv4/IPv6 `*:22`。
- 清除一个失去父进程的旧 Harness 实例，以及占用统一 ID 服务锁的 dev.172 旧中继后，dev.176 独占运行：Harness 位于 `127.0.0.1:3080`，未授权 HTTP 请求返回 401，鉴权门禁正常。
- dev.176 中继状态为 `routingId=1554650784`、`callable=true`、`rendezvousOnline=true`、`registrationKeyConfirmed=true`；仿真安全门禁为 idle，连接列表为空。
- 受控 MCP 端点 `127.0.0.1:32147` 与系统 SSH `127.0.0.1:22` 均真实监听；主界面状态显示“局域网仿真可连接”。
- 最终运行截图：`/private/tmp/vibekits-dev176-final-running.png`。

系统数据盘一度仅余约 113 MiB，导致 Keychain 明确返回 `No space left on device`，同时留下旧 Node 进程。两个约 291 MiB 的旧临时包审计目录已无删除地移动至 `/Volumes/ORICO/vibekits-temp-offload-20260911/`；旧进程退出并释放占用后，系统数据盘可用空间恢复至约 12 GiB，不再阻塞本次 SSH、Harness 和仿真状态验收。
