# VibeKits dev.178 ID-only 仿真隧道修复验收

日期：2026-09-11

## 问题

dev.177 双机测试固定停在 `listener_ready`，随后 45 秒超时。标准 RustDesk 能连接同一目标，专用 Harness ID 也能被服务器路由，排除了网络、HBBS/HBBR 和 ID 注册故障。代码审查与实测定位到两个产品代码缺陷：helper 在监听 socket 真正绑定前发布假就绪；目标端在专用仿真授权之前执行通用 IP 隧道权限检查。

## 修复

- helper 先同步绑定 `127.0.0.1:<ephemeral-port>`，绑定成功后才发布 `listener_ready`，消除假就绪竞态。
- 临时转发不再写入 RustDesk peer 的持久 `port_forwards` 配置，重复连接不会因历史端口而被静默跳过。
- 首个真实 MCP 请求直接触发按需 P2P/HBBR 连接；不再额外建立空触发连接，避免双握手和第二次竞态。
- 对专用 `VibekitsHarness` 身份，已打开的仿真开关仅放行固定 `127.0.0.1:32147`（MCP）与 `127.0.0.1:22`（系统 SSH）目标，并在该窄范围内优先于通用 IP 隧道权限；任意其他端口仍按原权限拒绝。
- 原生端口转发错误会回传给受管进程，不再一律伪装成无信息的 45 秒超时。
- 超时或失败仍由 tunnel lease 统一关闭，不允许后台遗留转发进程。

## 自动回归

- Rust 定向回归 `vibekits_harness_relay::tests`：4/4 通过。
- Flutter `harness_simulator_controller_test.dart`：4/4 通过，明确验证首个真实 MCP 请求直接激活隧道。

## 双机门禁

- 目标机：VibeKits ID `4456560334`，已由设备所有者打开局域网仿真。
- 待把同时包含控制端与目标端修复的 dev.178 候选安装到两台 Mac 后执行：连接、远端 `tools/list`、`vibekits.device.processes`、主动断开与本地监听回收。
- 远程协助和局域网仿真继续使用独立授权开关；一个开关不得隐式开放另一个能力。
