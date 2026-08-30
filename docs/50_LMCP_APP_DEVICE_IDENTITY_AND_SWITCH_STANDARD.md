# LMCP/2 APP 设备身份、MCP 开关与远程等价调用标准

版本：2.0  
状态：第三方 APP 必须遵守的接入规范  
目标：其他 APP 只要完整实现本文，VibeKits 就能自动发现、读取接口并像调用本机工具一样调用它。

## 1. 完成后的用户体验

每个 APP 在自己的设置页或主界面显示一行：

```text
[APP名称@主机名-硬件识别码]   MCP [开关]
```

例如：

```text
KEMI-PAD@PAD-53-A18F09C27B   MCP [开]
```

- 开：启动 MCP 服务、发布 `announce`、响应 `initialize/tools/list/tools/call`；VibeKits 自动出现该设备。
- 关：先发布 `goodbye`，再停止接受新调用并关闭服务；VibeKits 立即移除该设备。
- APP 异常退出或断电：没有心跳后最多 12 秒从列表移除。
- 开关只控制“本 APP 是否对外提供 MCP”，不能关闭 APP 自己发现其他 MCP 的能力。

普通工具调用不需要逐项审批。只有 APP 暴露 `serviceRole=harness-controller`、允许外部智能体远程向本机 Harness 下任务时，才由被调用端审批。

## 2. 唯一身份和显示名称

每个实例必须同时提供三个不可混淆的标识：

| 字段 | 规则 | 示例 |
|---|---|---|
| `app.id` | 开发者反向域名，发布后稳定 | `com.kemi.pad` |
| `hardwareCode` | 设备稳定硬件材料的 SHA-256 前 10 位大写十六进制；不能直接广播原始序列号 | `A18F09C27B` |
| `instanceId` | `<app.id>:<hardwareCode>`；同一硬件上同 APP 多实例再加安装槽 ID | `com.kemi.pad:A18F09C27B` |

显示名称必须为：

```text
<app.name>@<hostName>-<hardwareCode>
```

硬件材料建议按平台选择 TPM/设备安装 ID/主板 UUID/系统设备 ID之一，与 `app.id` 加盐后做 SHA-256。禁止广播 MachineGuid、IMEI、MAC、主板序列号等原值。无法取得硬件材料时，首次安装生成 128 位随机安装 ID 并安全持久化；卸载重装后变化是允许的。

VibeKits 自己遵守同一规则，当前名称为 `VibeKits@<hostName>-<hardwareCode>`。

## 3. MCP 开关状态机

```text
OFF
 └─用户打开→ STARTING → 服务监听成功 → announce → ON
ON
 ├─每4秒 announce/heartbeat
 ├─接口变化→ catalogRevision++ → announce
 └─用户关闭→ DRAINING → goodbye → 拒绝新调用 → 等待在途调用/取消 → OFF
```

要求：

1. 开关状态持久化，APP 重启恢复上次选择。
2. 只有端点真正监听成功后才能显示“开”。
3. `goodbye` 至少发送一次；丢包时仍由 12 秒 TTL 兜底。
4. 关闭后 `tools/call` 必须拒绝新请求，不能只隐藏 UI。
5. 在途调用最多等待配置的排空时间，然后返回结构化取消结果。
6. 接口服务崩溃时开关显示异常/关闭，不得继续广播在线。

## 4. LMCP/2 在线和离线报文

APP 打开开关后，每 4 秒向 `239.255.42.99:47831/UDP` 发送不超过 1200 字节的 UTF-8 JSON：

```json
{
  "protocol": "lmcp-discovery",
  "protocolVersion": "2.0",
  "messageType": "announce",
  "instanceId": "com.kemi.pad:A18F09C27B",
  "hardwareCode": "A18F09C27B",
  "app": {
    "id": "com.kemi.pad",
    "name": "KEMI-PAD",
    "displayName": "KEMI-PAD@PAD-53-A18F09C27B",
    "version": "3.2.0"
  },
  "catalogEndpoint": {
    "transport": "https-streamable-http",
    "port": 9443,
    "path": "/mcp"
  },
  "callEndpoint": {
    "transport": "https-streamable-http",
    "port": 9443,
    "path": "/mcp",
    "serviceRole": "tool-provider"
  },
  "mcp": {
    "protocolVersions": ["2025-06-18"],
    "catalogRevision": "42",
    "capabilityDigest": "sha256:...",
    "changeNotifications": true
  },
  "ttlSeconds": 12,
  "sentAt": "2026-08-30T10:00:00Z"
}
```

关闭时发送相同身份的离线报文；无需携带端点和能力：

```json
{
  "protocol": "lmcp-discovery",
  "protocolVersion": "2.0",
  "messageType": "goodbye",
  "instanceId": "com.kemi.pad:A18F09C27B",
  "sentAt": "2026-08-30T10:01:00Z"
}
```

广播不得包含 Token、密码、私钥、任务参数和业务数据。VibeKits 以 UDP 数据包源 IP 为准，不信任报文自行声明的 IP。

### 4.1 多个 APP 同机监听：必须共享端口

生产环境所有 APP 都使用同一发现地址 `239.255.42.99:47831/UDP`。同一台电脑可能同时运行 VibeKits、KEMI、RustDesk Sidecar 和其他 MCP APP，因此实现不得独占 `47831`，也不得遇到冲突后私自改成另一个端口。

创建接收 socket 时必须按此顺序执行：

1. 创建 IPv4 UDP socket。
2. 在 `bind` **之前**设置 `SO_REUSEADDR=1`。
3. macOS、iOS、BSD 和支持该选项的 Linux 同时设置 `SO_REUSEPORT=1`；Windows 不要求 `SO_REUSEPORT`，并应关闭 `ExclusiveAddressUse`。
4. 绑定 `0.0.0.0:47831`，不能绑定 `239.255.42.99`，也不能只绑定某个临时 IP。
5. 枚举所有处于 up 状态、支持 multicast 的私网 IPv4 网卡，对每张网卡执行 `IP_ADD_MEMBERSHIP(239.255.42.99, interfaceAddress)`。
6. 开启 multicast loopback，确保同机 APP 可以互相发现。
7. 发送时把 `IP_MULTICAST_IF` 设为对应网卡；多网卡设备应在每张合格网卡各发送一次，而不是依赖默认路由猜测。
8. 接收循环持续运行；单个非法报文只能被丢弃，不能使 socket 退出。

Dart 实现参数：

```dart
final socket = await RawDatagramSocket.bind(
  InternetAddress.anyIPv4,
  47831,
  reuseAddress: true,
  reusePort: !Platform.isWindows,
);
socket.multicastLoopback = true;
socket.joinMulticast(InternetAddress('239.255.42.99'), interface);
```

Node.js 实现必须在创建 socket 时启用地址复用，不能在 bind 之后补设：

```js
const socket = dgram.createSocket({
  type: 'udp4',
  reuseAddr: true,
  reusePort: process.platform !== 'win32'
});
socket.bind({ address: '0.0.0.0', port: 47831, exclusive: false }, () => {
  socket.setMulticastLoopback(true);
  socket.addMembership('239.255.42.99', interfaceAddress);
});
```

Node.js 运行时必须实际支持 `reusePort`；如果所选 Node 版本忽略或不支持该选项，macOS 版本应升级运行时、使用设置 `SO_REUSEPORT` 的原生 helper，或让同厂商多个进程共用一个本机发现 broker，不能声称已经支持多 APP 并存。

Swift/Darwin 原生实现必须在 `bind()` 前对同一个 fd 同时调用：

```c
setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &one, sizeof(one));
bind(fd, 0.0.0.0:47831);
```

若仍收到 `EADDRINUSE/Address already in use`：

- 首先判定为 socket 创建顺序或参数错误，记录 `bindAddress`、`port`、`reuseAddr`、`reusePort`、平台和错误码。
- 关闭失败 socket，按上述顺序重新创建一次；不能在同一个已经 bind 失败的 socket 上继续操作。
- 第二次仍失败时，MCP 开关必须显示“发现监听异常”，不能显示正常在线。
- APP 可以使用独立发送 socket继续发 `announce`，使其他设备仍能发现自己；但必须明确标记本机发现能力降级。
- 禁止杀死其他 APP、禁止随机选择生产发现端口、禁止扫描端口。

### 4.2 自动化测试必须与生产端口隔离

单元测试和 CI 不得默认绑定正式端口 `47831`。测试进程为每个测试 worker 分配一个保留范围端口，并通过构造参数或 `LMCP_TEST_PORT` 同时传给发送端和接收端：

```text
production: 47831
test worker 0: 49100
test worker 1: 49101
test worker N: 49100 + N
```

同一个测试用例应在同一端口创建至少两个发现实例，以验证共享绑定确实有效；不同测试 worker 不得复用端口。macOS CI 必须覆盖：两个实例同时 bind、双方收到公告、其中一个关闭不影响另一个、`goodbye` 立即移除。测试结束必须在 `finally/tearDown` 中 `stop/close` 所有 socket 和 timer。禁止只靠 `sleep` 后让进程退出回收资源。

## 5. 对方必须实现的标准 MCP 流程

发现后 VibeKits 自动执行：

```text
initialize
  → notifications/initialized
  → tools/list（分页直到 nextCursor 为空）
  → 订阅 tools/list_changed
  → 按任务 tools/call
```

服务端至少支持：

- `initialize`
- `ping`
- `tools/list`
- `tools/call`
- `notifications/tools/list_changed`（接口会动态变化时必须支持）

每个工具必须按下列结构描述：

```json
{
  "name": "kemi.device.status",
  "title": "读取 KEMI 设备状态",
  "description": "只读返回系统版本、运行时长、内存和前台应用。无需参数。",
  "inputSchema": {
    "type": "object",
    "properties": {},
    "additionalProperties": false
  }
}
```

`description` 必须让智能体不看源码也能知道什么时候调用、前置条件、结果、重要副作用和失败情形。`inputSchema` 必须完整声明类型、必填、默认值、枚举、范围和每个字段含义。服务端必须再次验证参数，不能相信调用方。

### 5.1 端点参数必须写到可直接连接

`catalogEndpoint` 和 `callEndpoint` 不能只写协议名称，必须包含 VibeKits 无需猜测即可连接的全部非秘密参数：

| 字段 | 必填 | 规则 |
|---|---:|---|
| `transport` | 是 | LMCP/2 固定为 `https-streamable-http`；兼容实现可另列 `ssh-stdio` |
| `port` | 是 | `1..65535`；必须是当前真实监听端口 |
| `path` | 是 | 以 `/` 开头，不含查询字符串、`..`、Token |
| `serviceRole` | 调用端点必填 | `tool-provider` 或 `harness-controller` |
| `instanceKeyFingerprint` | 是 | `sha256:<64个小写十六进制>`，对应当前实例 TLS/身份密钥 |
| `protocolVersions` | 是 | 至少包含双方支持的 MCP 协议版本 |
| `catalogRevision` | 是 | 单调变化的字符串或整数；任何工具 Schema 变化都必须改变 |
| `capabilityDigest` | 是 | 对规范化完整 `tools/list` 做 SHA-256，不是对广播报文做哈希 |

VibeKits 使用 UDP 包的源地址拼接连接 URL。例如源 IP 为 `192.168.3.53`、端口 `9443`、路径 `/mcp`，实际 URL 是 `https://192.168.3.53:9443/mcp`。APP 不得在报文里要求客户端改用另一个公网域名，也不得通过 30x 跳转把客户端带出私网。

连接后 VibeKits 发送的初始化请求：

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2025-06-18",
    "capabilities": {},
    "clientInfo": {"name": "VibeKits", "version": "2.x"}
  }
}
```

服务端必须返回自己实际采用的协议版本、能力和 `serverInfo`；不支持时返回标准 JSON-RPC 错误，不能返回 HTTP 200 加自定义字符串。

### 5.2 `tools/list` 必须完整且可分页

VibeKits 首次连接、`catalogRevision` 改变或收到 `notifications/tools/list_changed` 时调用：

```json
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
```

分页响应示例：

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "tools": [],
    "nextCursor": "opaque-next-page-token"
  }
}
```

有 `nextCursor` 时 VibeKits继续请求 `{"cursor":"opaque-next-page-token"}`，直到游标为空。游标必须是不透明短时值，不能包含凭据。服务端不得只返回“常用工具”；开关打开后所有允许 Harness 使用的工具都应在目录中。建议上限：单页 100 个工具、单页 1 MiB、Schema 深度 16、工具名 128 字符。

### 5.3 `tools/call` 参数和结果

VibeKits 直接使用 `tools/list` 的 `name` 与用户任务生成参数：

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "kemi.device.status",
    "arguments": {}
  }
}
```

服务端必须：

- 严格按该工具当前 `inputSchema` 验证 `arguments`。
- 未知字段在 `additionalProperties:false` 时返回参数错误。
- 以 MCP `content` 返回文本、结构化数据或资源引用；业务失败使用 `isError:true`，传输失败使用相应 HTTP/MCP 错误。
- 写操作支持调用方提供的幂等键时，应在 Schema 中明确字段名、有效期和重复调用语义。
- 长任务不要占用无限 HTTP 请求，应返回 `taskId`，再提供明确描述的 status/cancel 工具。
- 每个响应保留 `instanceId`、工具名、目录版本和服务端追踪 ID，便于 VibeKits 审计来源。

以下情况 VibeKits 会拒绝调用：工具不在当前目录、Schema 无效、目录摘要不匹配、实例指纹改变、设备已 `goodbye`/TTL 离线、端点跳出私网、响应超出限制。

## 6. 像本地工具一样远程调用

VibeKits 为远端工具生成内部路由键：

```text
lmcp://<instanceId>/<tool.name>
```

智能体每个新任务需要工具时读取最新三层快照，顺序为本 APP、本机、局域网。选中远端工具后，路由器使用发现会话调用 `tools/call`，并统一返回：

```json
{
  "ok": true,
  "instanceId": "com.kemi.pad:A18F09C27B",
  "tool": "kemi.device.status",
  "catalogRevision": "42",
  "content": [],
  "durationMs": 83
}
```

网络断开、目录版本变化和远端错误必须保留来源信息；不得悄悄改成本机 shell 执行。写入/设备控制是否允许由任务本身和工具风险控制，不做普通 MCP 的逐工具配对审批。

## 7. 第三方 APP 交付检查表

- [ ] 显示名称包含 APP 名、主机名和 10 位硬件识别码。
- [ ] `app.id`、`hardwareCode`、`instanceId` 重启后稳定。
- [ ] 有用户可见、可持久化的 MCP 开关。
- [ ] 打开发送 `announce`，关闭发送 `goodbye` 并停止服务。
- [ ] 实现标准 `initialize/tools/list/tools/call`。
- [ ] 每个工具具有完整描述和 JSON Schema。
- [ ] 接口变化更新目录版本并发出通知。
- [ ] 广播不包含秘密或业务数据。
- [ ] 两台真实设备验证上线、调用、关闭立即消失、断电 TTL 消失。
- [ ] 通过 VibeKits 的第三方 LMCP 合规测试后才标记完成。

## 8. VibeKits 当前实现对应关系

- 身份生成：`lib/features/dev_tools/domain/mcp_device_identity.dart`
- 开关和持久化：`McpExposurePreferences`
- `announce/goodbye`：`LanPeerDiscoveryService`
- 实时三层目录：`McpCapabilityDirectory`
- 界面：Harness 顶部设备名称、MCP 开关、本机 MCP 和局域网 MCP 列表

VibeKits 不再把六个扩展控件横向铺在 Harness 顶栏，也不把 Flutter 浮层叠在 Windows 原生 WebView 上。Harness Web 内容和一条 60px 的右侧工具轨采用物理分栏；工具轨纵向放置 MCP 开关、本机 MCP、局域网 MCP、飞书、日志和远程操作，只显示图标，悬浮后展示完整设备名、接口范围和当前状态。本机/局域网设备数量使用角标，轨道底部为后续功能保留位置。工具轨不得随主机名长度变化，不得遮挡 WebView，不得把控件挤向左侧。

本文是第三方 APP 的实现入口；总体能力图、权限和任务路由见 [VibeKits 三层实时 MCP 能力网络架构](49_REALTIME_THREE_TIER_MCP_FABRIC_ARCHITECTURE.md)。
