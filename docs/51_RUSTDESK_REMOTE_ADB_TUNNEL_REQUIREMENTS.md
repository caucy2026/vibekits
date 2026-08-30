# RustDesk 远程 ADB 隧道开发与验收要求

状态：代码与本机联调完成，待真实远端设备验收
调用方：Vibekits 1.9
提供方：KEMI/RustDesk desktop
目标平台：macOS、Windows

## 1. 目标

当 Vibekits 用户已经通过 RustDesk/KEMI 连接一台远端电脑后，Vibekits 可以请求 RustDesk 复用该已认证 peer 的连接能力，建立一个本地 loopback TCP 端点：

```text
Vibekits adb -H 127.0.0.1 -P <localPort>
  -> RustDesk P2P/direct 或 hbbr relay
  -> 远端 RustDesk Host 127.0.0.1:5037
  -> 远端 ADB server
```

不得向 Vibekits 返回、记录或持久化 RustDesk 密码、`connToken`、会话密钥或中继密钥。

## 2. 进程与信任边界

1. Vibekits 不直接连接 RustDesk 私有 IPC，也不解析其二进制消息格式。
2. Vibekits 只启动用户配置或自动发现的同一个 RustDesk 可执行文件，并使用下面的 CLI。
3. CLI 子进程只充当 RustDesk IPC 客户端；隧道必须由持有 Flutter 出站会话的 RustDesk GUI 进程创建和管理。
4. 不能把 broker 放在独立 `--server` 进程的 main IPC 中，因为该进程看不到 Flutter GUI 的活跃出站 session map。
5. RustDesk GUI 使用专用 `_vibekits_adb` IPC listener。listener 必须在 accept 时校验同一 OS 用户、同一登录 session，并校验客户端是当前 RustDesk 的同路径可执行文件。socket/pipe 不得允许其他本地程序直接调用。
6. macOS/Linux socket 及父目录只允许当前用户访问；Windows named pipe 必须设置显式 ACL，并复用/扩展现有 executable identity 校验。

## 3. CLI 契约

### 3.1 打开隧道

```text
RustDesk --vibekits-adb-tunnel-open --peer-id <peerId> [--session-id <sessionId>]
```

成功时退出码为 `0`，stdout 只输出一行 JSON：

```json
{"schemaVersion":1,"ok":true,"operation":"open","state":"ready","host":"127.0.0.1","port":15037,"leaseId":"opaque-random-id","peerId":"123456789","sessionId":"rustdesk-ui-session-uuid"}
```

要求：

- `host` 必须是 `127.0.0.1`。
- `port` 必须是实际已监听且大于零的动态本地端口，不能只返回预留但尚未监听的端口。
- 远端目标必须在 RustDesk 内部硬编码/强制规范化为 `127.0.0.1:5037`。CLI 不接受任意 `host` 或 `remotePort`。
- `leaseId` 使用不可预测随机值，不包含密码、peer 密钥或 `connToken`。
- `peerId` 必须对应一个已存在且当前连接中的 `DEFAULT_CONN` 出站控制会话。
- 如果同一 peer 已有有效 ADB lease，可以幂等返回原 lease，或明确创建独立 lease；行为必须有测试覆盖。

### 3.2 查询隧道

```text
RustDesk --vibekits-adb-tunnel-status --lease-id <leaseId>
```

成功示例：

```json
{"schemaVersion":1,"ok":true,"operation":"status","state":"ready","host":"127.0.0.1","port":15037,"leaseId":"opaque-random-id","peerId":"123456789","sessionId":"rustdesk-ui-session-uuid"}
```

允许的状态为 `starting`、`ready`、`closed`、`failed`。Vibekits MVP 可以不主动轮询，但 RustDesk 端应提供可测试的状态或保证 open 只在 ready 后返回。

### 3.3 续租隧道

```text
RustDesk --vibekits-adb-tunnel-heartbeat --lease-id <leaseId>
```

成功响应使用 `operation: "heartbeat"` 并返回当前 `ready` lease。Vibekits 每 10 秒发送一次 heartbeat；RustDesk lease TTL 为 45 秒。heartbeat 不得在后台隐式伪造，过期、桌面会话断开或 connection round 变化都必须关闭转发任务。

### 3.4 关闭隧道

```text
RustDesk --vibekits-adb-tunnel-close --lease-id <leaseId>
```

成功示例：

```json
{"schemaVersion":1,"ok":true,"operation":"close","state":"closed","leaseId":"opaque-random-id"}
```

关闭必须幂等；未知或已关闭的 lease 不得关闭其他隧道。

### 3.5 错误格式

业务失败使用非零退出码，stdout 仍只输出一行可解析 JSON，stderr 可写诊断但不得包含凭据：

```json
{"schemaVersion":1,"ok":false,"operation":"open","code":"peer_not_connected","message":"No active authenticated session for peer"}
```

至少支持：

- `invalid_arguments`
- `ipc_unavailable`
- `ipc_unauthorized`
- `peer_not_connected`
- `auth_context_unavailable`
- `tunnel_permission_denied`
- `remote_adb_unreachable`
- `local_bind_failed`
- `lease_not_found`
- `internal_error`

`schemaVersion` 固定为 `1`，`operation` 必须精确对应 `open/status/heartbeat/close`。错误 `message` 必须有统一长度上限并保持合法 UTF-8。

## 4. RustDesk 内部实现要求

1. GUI 专用 IPC handler 从 Flutter `sessions` 中按 peer/session 找到 `DEFAULT_CONN`。
2. 在取认证信息前再次检查会话仍处于 connected round；不能只检查 map 中存在对象。
3. 在 RustDesk 进程内部取得 `connToken/session_id`，创建 headless `PORT_FORWARD` session；凭据不能进入 CLI argv、stdout、文件或日志。
4. 本地 listener 只绑定 IPv4 loopback。open 只有在 listener 已成功绑定后才返回端口。
5. 远端 Host 继续执行现有 `enable-tunnel` / `Permission::tunnel` 校验。
6. lease 绑定 `peerId + authenticated session_id + connection round`。桌面会话断开、认证轮次改变、权限撤销、GUI 退出或显式 close 时必须释放 listener 和转发任务。
7. ADB 隧道不能被加入普通持久化 `port_forwards` 配置，重启后不得自动恢复。
8. 不得复用 Harness 只读状态协议承载 ADB 数据或控制命令。
9. 不得在持锁状态下跨 `.await`，不得创建嵌套 Tokio runtime；遵守 RustDesk `AGENTS.md`。

## 5. Vibekits 调用要求

1. 所有 ADB 命令通过统一 `AdbServerEndpoint` 组装；本机 endpoint 不添加参数，RustDesk endpoint 在设备选择器和命令之前添加：

```text
-H 127.0.0.1 -P <port>
```

2. 用户命令解析器继续禁止启动/停止/切换 ADB server，并锁定所选 serial。
3. UI 显示设备来源、peerId、lease 状态；不得把远端设备伪装成本机设备而不标识来源。
4. workspace dispose、用户切换来源、RustDesk 断开或 open 失败时调用 close。
5. 审计记录 peerId、设备 serial、命令类别和结果；不记录凭据或完整敏感 shell 内容。

## 6. RustDesk 交付物

- CLI open/status/heartbeat/close 实现与帮助/参数分派。
- GUI-owned `_vibekits_adb` IPC listener 和跨平台身份校验。
- headless ADB port-forward lease manager。
- 单元测试：参数、JSON、固定远端目标、随机 lease、幂等 close、未知 lease、未连接 peer、错误脱敏、session/round 失效清理。
- 至少在当前 macOS 主机完成 Rust 格式化、目标单测和 `cargo test --lib` 可编译验证；Windows 特有代码必须通过 cfg 检查或 CI。

## 7. 联调验收

1. RustDesk GUI 未运行：open 返回 `ipc_unavailable`，无崩溃。
2. GUI 运行但 peer 未连接：返回 `peer_not_connected`。
3. peer 已连接但远端 5037 不可用：返回或进入 `remote_adb_unreachable/failed`，不遗留 listener。
4. 远端执行 `adb start-server` 后，open 返回 ready endpoint。
5. 本地执行 `adb -H 127.0.0.1 -P <port> devices -l` 能列出远端设备。
6. `shell getprop`、`logcat`、小文件 push/pull 和测试 APK install 能工作。
7. close 后本地端口不可连接；再次 close 不影响其他会话。
8. 远程桌面断开后 lease 自动失效，本地端口关闭。
9. 非 RustDesk 进程直接访问 `_vibekits_adb` IPC 被拒绝。

## 8. 2026-08-30 当前验证结果

- RustDesk ADB 定向测试 6/6，`cargo check --locked --features flutter --bin rustdesk` 通过。
- Vibekits ADB endpoint、CLI adapter、命令注入和 workspace 生命周期定向测试 20/20。
- 同一 macOS Release App 可执行文件的四条 CLI 在 GUI 未运行时均只输出一行 JSON，精确返回对应 `operation`、`ipc_unavailable` 和退出码 3。
- RustDesk macOS Release App 与 Vibekits macOS Debug App 均已构建；Vibekits Debug App 已在本机实际启动并完成 Harness IPC 握手。
- 尚未具备第二台运行兼容 RustDesk 的已连接 peer 和该 peer 上可用的 `127.0.0.1:5037`，因此第 4–8 项真实远端 ADB 验收不能以模拟测试替代，仍保留为发布前硬门槛。
