# VibeKits dev.177 ID-only 整机仿真阶段记录

## 本阶段目标

被控机只打开一个“允许作为仿真机”开关。操作者只把被控机 VibeKits ID 告诉大模型；其余 P2P/中继、端口分配、MCP 初始化、工具发现、调用和断开均由软件自动完成。被调试对象是远端整台机器上的其他 App，不是 VibeKits 自身。

## 已落地

- 公共连接工具 `vibekits.simulator.connect` 只接收 `routingId`。
- 控制端新增连接、状态、目录、调用、断开五个操作；本地端口和远端固定端点不向调用方开放。
- 连接必须等到 `transport_connected` 后才初始化 MCP；仅 `listener_ready` 不算成功。
- 被控端开关启动固定回环 `127.0.0.1:32147` 和 RustDesk 易失门禁，不再依赖系统 SSH、Remote Login、账号、密码或密钥。
- 新增跨平台整机工具：进程筛选、系统日志、崩溃报告、应用启动/停止；既有资源采样、ADB、下载、文件、截图等工具继续来自同一权威目录。
- 关闭连接会终止受管隧道；关闭被控端开关会关闭端点和原生门禁。
- ARM64 与 x86_64 RustDesk helper 均重建成功，Universal helper SHA-256 为 `c47e1093f41eaa365cc04741799005662d2aa15e357425c5a8f8a9e824127f22`。
- macOS Release 候选构建成功，主程序和 helper 均为 `arm64 + x86_64`，界面显示 `v1.9.0-dev.177+2177`。

## 自动验证

- `harness_simulator_controller_test.dart`
- `harness_simulator_target_runtime_test.dart`
- `native_app_debug_service_test.dart`
- `harness_tool_bridge_test.dart`

上述定向回归共 49 项通过；`flutter analyze --no-pub` 为 0 问题。

## 尚未完成的发布门禁

- 同一台机器呼叫自身 ID 得到 `transport_connect_timeout`；自呼叫不能替代两台机器验收，也不作为产品场景。
- 仍需把 dev.177 候选安装到第二台 macOS/Windows 设备，在对端打开仿真开关后，仅使用其 ID 完成 P2P 和强制中继两轮验证。

## 双机实测后发现的阻断问题

- 目标 macOS 安装并打开仿真开关后，控制端以 ID `4456560334` 连接，直连和强制 HBBR 都停在 `listener_ready`，45 秒后 `transport_connect_timeout`。
- 根因不在目标网络或 ID 注册：标准 RustDesk ID 可连接，独立 Harness ID 也能被服务器路由并按预期拒绝桌面会话。后续代码审查确认 dev.177 同时存在两处实现错误：原生 helper 在本地端口真正绑定前上报 `listener_ready`；目标端又在专用仿真授权之前执行通用 IP 隧道权限检查。
- dev.177 因此不得作为 ID-only 仿真正式版本；修复进入 dev.178。此处此前记录的“先建空触发连接、再建立业务连接”方案已被真机反证并撤销；首个真实 MCP 请求应当直接触发唯一一次按需隧道握手。
- 每轮必须读取对端工具目录，定位一个非 VibeKits App，取得该 App 的进程、日志/崩溃和性能证据，并完成一次受控启动或停止。
- 真双机闭环完成前不发布到 KEMI 商场，不声称功能正式完成。
