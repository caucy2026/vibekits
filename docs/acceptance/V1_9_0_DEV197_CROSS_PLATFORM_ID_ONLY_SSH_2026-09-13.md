# VibeKits dev.197 跨平台仅凭 ID 远程仿真闭环

日期：2026-09-13

版本：`1.9.0-dev.197+2197`

状态：协议与 Windows 58 → Mac 双路径真机闭环通过；正式安装包门禁仍在进行，尚未发布。

## 本轮修复

1. 仿真控制端的全部 MCP 请求携带本机 VibeKits routing ID。目标端只在固定回环仿真端点、调用方 ID 为 6～16 位数字且 `peerId` 完全相同时，预授权 `vibekits.device.ssh_authorize` / `vibekits.device.ssh_revoke`；安装和卸载仍要求目标机人工批准。
2. 首次 SSH 主机身份采集不再依赖 Windows 旧版 `ssh-keyscan`。控制端在已认证 RustDesk 固定隧道内，使用双方支持的 `curve25519-sha256` 与 `ssh-ed25519` 取得主机公钥，随后用 `ssh-keygen` 计算指纹，并与 MCP 身份响应严格比对；通过后，正式 SSH/SCP 一律使用 `StrictHostKeyChecking=yes`。
3. MCP 超时错误带出 `initialize`、`notifications/initialized`、`tools/list` 或 `tools/call` 阶段，避免再次把应用工具等待批准误判为传输失败。
4. 新增双端真实测试入口。控制端完成工具目录、进程查询、SSH 命令、文件上传和 SHA-256 校验后，通过 SSH 写入一次性 PASS 标记；目标端收到标记后关闭 MCP、撤销本轮管理公钥并回收中继。

## 自动回归

- `harness_simulator_controller_test.dart`
- `harness_simulator_target_runtime_test.dart`
- `lan_mcp_tool_server_test.dart`

组合结果：`14/14` 通过。额外两个真实入口在默认测试中保持显式跳过，避免普通 CI 意外访问真机。

全量 Flutter 回归结果：`857` 项通过、`21` 项仅在显式真机或联网条件下运行的测试按门禁跳过、`0` 项失败，进程退出码为 `0`。这些跳过项不作为 63、PAD 75、目标 Mac 或正式安装包的通过证据。

## Windows 58 → Mac 真实证据

- Windows 58 控制端 VibeKits ID：`8296293831`。
- Mac 目标 VibeKits ID：`1554650784`。
- 目标端仅监听回环 MCP `127.0.0.1:32147`，系统 SSH 由仿真开关统一准备。
- 默认 P2P/自动回退路径：`tools=204`、进程响应键 `3`、`sshReady=true`、上传 `28` 字节、SHA-256 一致，双端测试通过。
- 强制 HBBR 路径：同样完成 204 个工具目录、进程查询、SSH 命令与 28 字节文件哈希闭环，双端测试通过。
- Windows `ssh-keyscan` 的真实故障证据为 `unsupported KEX method sntrup761x25519-sha512@openssh.com`；切换到固定兼容 KEX/HostKey 算法后闭环通过。
- 两轮结束后：Mac `32147` 无监听、一次性 PASS 文件不存在、`authorized_keys` 无 `8296293831` 管理条目、Mac 原生连接表为空；Windows 会话 0 的三个测试中继残留进程已精确终止并复核为 `0`。用户会话中的 VibeKits 进程未操作。

## 证据边界与剩余门禁

本轮 Mac 数据面使用已签名、公证的 dev.196 Universal helper，MCP/SSH 业务逻辑来自 dev.197 当前源码测试进程。因此它证明跨平台 RustDesk P2P/HBBR、MCP、自动 SSH 密钥交换、严格主机身份和文件通路真实可用，但不能替代 dev.197 正式 App 的签名、公证和安装验收。

仍需完成：

1. dev.197 Universal macOS 12+ 正式构建、Developer ID 签名、公证、DMG 安装和启动。
2. dev.197 Windows Release 增量构建、安装和启动；没有可用 Authenticode 签名时不得作为已签名正式候选发布。
3. 目标 Mac `4456560334` 安装精确 dev.197 后，仅打开一个仿真开关，完成 Mac → Mac 的同等 SSH/SCP/App 日志闭环。
4. 远程协助首次证书配对、项目/会话同步、命令反馈与停止生命周期的独立双机门禁。
5. 63 与 PAD 75 恢复网络可达后补真机验证；当前历史证据仍是 `No route to host`，不得记为通过。
