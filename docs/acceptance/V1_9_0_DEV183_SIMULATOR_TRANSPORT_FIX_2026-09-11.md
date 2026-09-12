# VibeKits dev.183 统一 ID 仿真传输修复验收记录

日期：2026-09-11
候选版本：`1.9.0-dev.183+2183`

## 修复范围

dev.181/182 的独立 Harness ID 已能通过 HBBS/HBBR 到达被控端，但固定 `127.0.0.1:32147` 连接在成功路由后仍进入通用桌面 Connection Manager IPC 等待。`VibekitsHarness` 没有桌面 CM，因此控制端最终只能得到 MCP/transport 超时。

本次修复把固定仿真端点的自动授权放到通用桌面 IPC 之前，并严格限制为：

- 独立进程命名空间 `VibekitsHarness`；
- 用户已明确打开、且只存在于进程内存的仿真授权位；
- 固定回环端点 `127.0.0.1:32147` 或内部保留的 `127.0.0.1:22`；
- 正确的 routing ID。

自动授权路径先让通用登录响应函数连接固定目标、建立审计对象并发送成功响应，再读取最终 `authorized` 状态；禁止预先设置授权位导致响应函数短路。桌面、文件传输、终端、摄像头及任意网络代理均不经过该路径。

控制端同时修正为并发执行首个真实 MCP 初始化与 `transport_connected` 等待。真实 MCP TCP 请求是按需端口转发的启动信号；连接只有在 MCP 初始化和原生传输均成功后才对外可见。原生失败可直接返回，不再统一伪装为 MCP 超时。

## 自动化结果

- Rust `vibekits_harness_relay` 定向测试：4/4 通过；覆盖命令映射、显式易失授权位、固定回环目标和 HBBS 确认后才公开 ID。
- Flutter 控制端及被控端定向测试：11/11 通过；覆盖按 ID 连接、强制中继、工具目录、调用、断开、默认关闭不显示伪异常、升级替换旧 helper 和端点释放。
- 4 个相关 Dart 文件静态分析：0 问题。
- `git diff --check`：RustDesk 与 VibeKits 本次文件均无空白错误。

## 精确候选与本机真实闭环

- Rust helper ARM64、Intel x86_64 均从同一修复源码构建；Universal SHA-256：`2c974e79386e96abb653c24862635ac61c1bf0f5673f39825b5d16ab5b801f97`。
- macOS App：主程序和 helper 均为 `x86_64 arm64`，最低系统版本门禁为 macOS 12。
- Developer ID：`Developer ID Application: zhen ji (26T5WV4GLP)`；36 个 Mach-O 深度严格验签通过；内置 Node ARM/Intel 实启与 DSH 启动门禁通过。
- 已签名精确候选后台启动，工具桥 PID/路径匹配，打开开关后报告 `ready=true`。
- 直连轮：只输入本机 routing ID，完成原生登录、MCP 初始化、读取 191 个实时工具和断开。
- 强制 HBBR 轮：同一 ID 完成原生登录、MCP 初始化、读取 191 个实时工具和断开。
- 关闭授权后 `32147` 无监听；专用 stop 命令返回 `state=stopped`；App、隧道和 helper 无残留进程。
- 交付 ZIP：`Vibekits-1.9.0-dev.183+2183-macos-universal-developer-id.zip`，SHA-256 `37542043aca5096c52b71880685a7669bbb01862c923cca0293929b1c1bfe78b`。

## 仍未通过的硬门禁

复核关闭授权的真实拒绝路径时，dev.183 虽然正确拒绝了连接，但 MCP 套接字关闭先于原生登录错误完成，控制端得到泛化的 `transport_failed`，没有稳定返回 `remote_disabled`。因此 dev.183 ZIP 已作废，不得交付或发布；错误优先级修复和重新构建进入 dev.184。

上述证据证明同一精确候选的服务器与客户端协议能够完成直连和强制中继闭环，但自呼叫不能替代两台物理机器。ID `4456560334` 的目标机仍运行 `dev.181+2181`，不含本次被控端登录顺序修复。

必须把 dev.183 精确候选安装到目标 Mac，核对版本、签名和 routing ID 后分别完成 P2P 与强制中继两轮；每轮读取实时工具目录、调用只读设备工具、验证结果来自目标机、断开并检查零残留。该双机门禁通过前，不得标记正式完成，不得发布 KEMI 商场。
