# LMCP/2 APP 设备身份、MCP 开关与远程等价调用标准

版本：2.0  
状态：VibeKits、KEMI传书和第三方 APP 唯一可执行互通规范
目标：另一台机器只需完整实现本文，即可让 VibeKits 与对端双向发现、固定实例证书、读取目录，并像调用本机工具一样互相调用。

本文中的 MUST/“必须”是上线门禁。LMCP/1 只保留接收兼容：显示为“仅发现、不可调用”；新版本不得把 `ssh-stdio` 伪装成 LMCP/2，也不得再正式发送 LMCP/1 公告。

### 一文交付规则

把第三方 APP 交给另一个开发团队时，**只交付本文，也只以本文验收**。本文是自包含合同，不要求接入方再组合阅读仓库中的能力目录、历史协议或联调记录。对方必须同时完成以下四层，不得只做“发现”或只复制一段 UDP JSON：

1. 身份与开关：稳定 `instanceId`、持久证书、风险确认和可撤销状态机；
2. 跨机发现：按本文固定参数在每张私网网卡上发送/接收 LMCP/2，并完成 Windows Private 防火墙规则；
3. 真实调用：HTTPS `/mcp`、TLS 指纹固定、`initialize → tools/list → tools/call`、目录摘要和错误语义；
4. 可理解工具：每个工具提供用途、完整 Schema、风险、成功结果、错误码和真实双机验收状态。

仓库中的 Harness 能力目录只是 VibeKits 当前构建的自动生成结果；LMCP/1 文件只是历史兼容资料。它们都不是接入前置条件，且出现冲突时一律以本文为准。

## 0. 固定生产参数（不要猜）

| 项目 | 唯一值 |
|---|---|
| 发现组 | IPv4 multicast `239.255.42.99` |
| 发现端口 | UDP `47831` |
| bind | `0.0.0.0:47831`，bind 前设置复用 |
| 公告周期 | 每 4 秒一次 |
| 应用 TTL | `ttlSeconds=12`；连续 12 秒无公告即离线 |
| IP multicast TTL | 1，只限当前二层/局域网，不经过路由器 |
| 正式 MCP 端口 | 优先 TCP `9443`；同机已占用时绑定动态私网端口并广播真实值 |
| MCP 路径 | HTTPS `POST /mcp` |
| 传输 | `https-streamable-http` |
| MCP 版本 | `2025-06-18` |
| 单个发现包 | 最多 1200 UTF-8 bytes，不是 1200 字符 |
| 单个 MCP 请求/响应 | 最多 1 MiB |

VibeKits 当前实现的 `catalogRevision` 是单调构建号 `2137`，APP 版本为 `1.9.0`。后续任何工具名称、描述、风险、annotations 或 JSON Schema 变化都必须提升构建号并重新计算摘要。

## 1. 完成后的用户体验

每个 APP 在自己的设置页或主界面显示一行：

```text
[APP名称@主机名-硬件识别码]   MCP [开关]
```

例如：

```text
KEMI-PAD@PAD-53-A18F09C27B   MCP [开]
```

- 开：用户首先确认权限与风险说明，然后启动 MCP 服务、发布 `announce`、响应 `initialize/tools/list/tools/call`；VibeKits 自动出现该设备。取消确认不得改变开关、持久化状态或网络状态。
- 关：先发布 `goodbye`，再停止接受新调用并关闭服务；VibeKits 立即移除该设备。
- APP 异常退出或断电：没有心跳后最多 12 秒从列表移除。
- 开关只控制“本 APP 是否对外提供 MCP”，不能关闭 APP 自己发现其他 MCP 的能力。

打开 MCP 是一次明确的“向局域网发布能力”授权，不等于永久放行所有副作用。只读调用可按用户选择的权限策略直接执行；写文件、向外发送文件、控制设备、修改账号/系统或破坏性操作必须进入 APP 的统一风险审批与审计。`serviceRole=harness-controller` 的远程任务还必须由被调用端单独审批。

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
 └─用户打开→ PERMISSION_PROMPT
                  ├─取消→ OFF
                  └─允许→ STARTING → 服务监听成功 → announce → ON
ON
 ├─每4秒 announce/heartbeat
 ├─接口变化→ catalogRevision++ → announce
 └─用户关闭→ DRAINING → goodbye → 拒绝新调用 → 等待在途调用/取消 → OFF
```

要求：

1. 新安装或授权记录损坏时默认 `OFF`；用户成功授权后持久化开关状态，APP 重启恢复上次选择。
2. `OFF/PERMISSION_PROMPT/STARTING/ON/DRAINING/ERROR` 必须有不同文字、图标或颜色，不能只用同一个图标的细微明暗表示。
3. 每次从关闭切到打开都必须弹出不可跳过的权限申请，至少展示：APP/设备身份、局域网可发现范围、实例证书指纹、将公开的完整工具名与用途、只读/写入/文件外发/设备控制风险、审计位置、关闭和撤销方法。取消后保持 `OFF`，不能先启动再补问。
4. 只有端点真正监听成功后才能显示“开”；保存设置或启动失败进入 `ERROR` 并给出可操作原因。
5. `goodbye` 至少发送一次；丢包时仍由 12 秒 TTL 兜底。
6. 关闭后 `tools/call` 必须拒绝新请求，不能只隐藏 UI。
7. 在途调用最多等待配置的排空时间，然后返回结构化取消结果。
8. 接口服务崩溃时开关显示异常/关闭，不得继续广播在线。

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
    "path": "/mcp",
    "instanceKeyFingerprint": "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    "protocolVersions": ["2025-06-18"],
    "catalogRevision": 2137,
    "capabilityDigest": "sha256:abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
  },
  "callEndpoint": {
    "transport": "https-streamable-http",
    "port": 9443,
    "path": "/mcp",
    "instanceKeyFingerprint": "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    "protocolVersions": ["2025-06-18"],
    "catalogRevision": 2137,
    "capabilityDigest": "sha256:abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
    "serviceRole": "tool-provider"
  },
  "mcp": {
    "protocolVersions": ["2025-06-18"],
    "catalogRevision": 2137,
    "capabilityDigest": "sha256:abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
    "changeNotifications": false
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
9. 显式设置 IP multicast TTL/hops 为 1；不能把发现公告转发到公网或其他路由域。

Dart 实现参数：

```dart
final socket = await RawDatagramSocket.bind(
  InternetAddress.anyIPv4,
  47831,
  reuseAddress: true,
  reusePort: !Platform.isWindows,
);
socket.multicastLoopback = true;
socket.multicastHops = 1;
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

### 4.3 接收端严格校验

接收端对每个 datagram 独立执行以下检查；任一失败只丢弃该包，不能退出监听：

1. 长度 `1..1200` bytes，严格 UTF-8，顶层必须是 JSON object。
2. UDP 源地址必须是 RFC1918 IPv4：`10/8`、`172.16/12` 或 `192.168/16`；连接 URL 只使用这个源地址。
3. `protocol="lmcp-discovery"`、`protocolVersion="2.0"`、`messageType="announce"|"goodbye"` 精确匹配；未知主版本拒绝。
4. `instanceId=<app.id>:<hardwareCode>`；同硬件多安装槽可追加 `:<slot>`；`hardwareCode` 恰为 10 位大写十六进制；不能等于本实例 ID。
5. `sentAt` 为 UTC `Z` 时间；announce 的 `ttlSeconds` 恰为 12。
6. 两个 endpoint 的 transport、port、path、fingerprint、protocolVersions、catalogRevision、capabilityDigest 必须逐项一致；路径恰为 `/mcp`，禁止 query、`..` 和重定向。
7. 指纹和摘要均匹配 `sha256:` 加 64 位小写十六进制；三个位置的 revision/摘要必须一致；协议列表包含 `2025-06-18`。
8. `callEndpoint.serviceRole` 只能是 `tool-provider` 或 `harness-controller`；`mcp.changeNotifications` 必须是 boolean。
9. 同一实例的端点、指纹、revision 或 digest 变化时废弃旧目录并重新 initialize/list，不能继续使用旧缓存。
10. goodbye 只要求协议、版本、类型、实例 ID 和 `sentAt`；收到后立即移除。没有 goodbye 时按最后有效 announce 的 12 秒 TTL 清理。

发送端必须在序列化后按 UTF-8 bytes 再检查 1200 上限。VibeKits 会在主机名过长时缩短公告中的 host/app 显示段，同时保留 `APP@host-hardwareCode` 结构；不得像旧实现一样超过 1200 后静默不发。这个边界是“同网段另一台 VibeKits 收不到本机”的已知直接原因之一。

### 4.4 防火墙、VPN 与多网卡

- macOS 首次运行应允许签名后的 VibeKits/KEMI 接收入站连接；系统防火墙中不得只放行 UDP 而漏掉公告中的实际 TCP 端口。
- Windows 安装器/管理员部署必须为签名程序本身创建仅 Private profile 的入站规则：UDP 47831 与其 TCP 监听；不要开放 Public profile，不要给任意程序放行。只允许固定端口的部署应把 VibeKits 与 KEMI 放在不同机器并使用 9443。
- 出站需允许 UDP `239.255.42.99:47831` 和公告指定的对端 RFC1918 TCP 端口。企业 EDR、访客 Wi-Fi/AP isolation 会阻断同网段设备，必须由网络管理员明确放行。
- VPN、虚拟机、Docker、USB 网卡和 Wi-Fi 可同时存在。实现要在每张拥有 RFC1918 IPv4 的 multicast 网卡分别 join 和 send，不能只使用默认路由；重复包按 `instanceId` 合并。
- 接口上下线后应重建 membership；当前进程至少在下次启动重新枚举。没有合格私网网卡时保持 OFF/ERROR，不能广播公网地址。

macOS 参考检查：

下列 `9443` 是首选值；若公告使用动态端口，命令必须替换成公告中的实际值。

```bash
lsof -nP -iUDP:47831
lsof -nP -iTCP:9443 -sTCP:LISTEN
sudo tcpdump -ni en0 'udp dst 239.255.42.99 and port 47831'
sudo tcpdump -ni en0 'tcp port 9443'
```

Windows 参考检查（管理员 PowerShell）：

```powershell
Get-NetUDPEndpoint -LocalPort 47831
Get-NetTCPConnection -State Listen -LocalPort 9443
Get-NetFirewallRule -PolicyStore ActiveStore | Where-Object DisplayName -Match 'VibeKits|KEMI'
pktmon filter add LMCP-UDP -p 47831
pktmon start --etw -m real-time
```

抓包时先确认发送端每 4 秒出现一包且 `length <= 1200`，再看接收端。如果发送端没有包，检查开关、公告 TCP 端口监听和序列化长度；发送端有包而接收端没有，检查 membership/网卡/防火墙/AP isolation；UDP 已收到但 UI 没设备，逐项核对严格字段；目录失败再检查 HTTPS 指纹和 digest。不要用关闭 TLS 校验、改成 HTTP 或扩大公网防火墙来“修复”。

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

`description` 必须让智能体不看源码也能知道什么时候调用、前置条件、结果、重要副作用和失败情形。`inputSchema` 必须完整声明类型、必填、默认值、枚举、范围和每个字段含义。工具还应使用 MCP `annotations` 声明 `readOnlyHint`、`destructiveHint`、`idempotentHint` 和 `openWorldHint`；服务端必须再次验证参数，不能相信调用方。禁止只广播“常用工具”，所有真正允许远端使用的工具都必须出现在 `tools/list`。

### 5.1 文件发送是完整工具，不是设备列表的隐含动作

提供文件传输能力的 APP 必须显式提供工具，不能只提供 `devices.list` 后要求智能体猜内部接口。KEMI传书的正式工具为 `kemi.files.send`，最低契约如下：

| 参数 | 规则 |
|---|---|
| `sourcePath` | 必填，本机绝对文件路径；必须是普通文件，调用时重新检查存在性、权限、大小和符号链接边界 |
| `targetDeviceId` | 必填，来自最新 `kemi.devices.list`，发送前复核仍在线且身份未变化 |
| `targetName` | 可选接收文件名，不得包含目录穿越或绝对路径 |
| `conflictPolicy` | 必填枚举：`receiver-default`、`ask`、`rename`、`overwrite`、`reject`；`receiver-default` 把同名处理交给接收端安全策略，默认不得静默覆盖 |
| `idempotencyKey` | 推荐；重复请求必须返回原任务或明确冲突，不能重复发送 |

返回至少包含 `transferId/status/sourceSize/sha256/targetDeviceId/targetName/bytesTransferred`；长传输应另有 `kemi.files.status` 和 `kemi.files.cancel`。文件内容和路径不得进入 UDP 公告、日志摘要或证书。调用前必须显示源文件、大小、目标设备和覆盖策略并请求批准；接收端仍保留接受/拒绝权。

KEMI传书当前生产目录必须完整列出下列四个工具；VibeKits 不得只显示名称，必须同时展示运行时 `description/inputSchema/risk/验收状态`：

| 工具 | 输入 | 功能与结果 | 风险和当前边界 |
|---|---|---|---|
| `kemi.device.status` | `{}` | 返回 KEMI 实例、版本/构建号、系统、运行时长、内存、本机 IP、文件服务、附近设备数和 MCP 发送状态 | 只读；已真实调用成功 |
| `kemi.devices.list` | `{}` | 返回在线接收目标的 `targetDeviceId`、别名、IP、端口、HTTPS、系统和设备类型 | 只读但暴露局域网设备元数据；已真实调用成功 |
| `kemi.files.last_status` | `{}` | 返回活动态或最近一条脱敏发送终态；活动态 `final=false`，终态 `final=true`，终态保留 7 天 | 只读；不得返回源路径、文件内容、Token、远程会话 ID 或接收端保存路径；已真实调用成功 |
| `kemi.files.send` | 见下表 | 从本机读取一个明确的普通文件，经 KEMI 正式 TLS 固定链路发送到 `devices.list` 的在线目标 | 高风险文件外发；接收端仍须允许；真实 handler 和路由已验证，但尚未取得 Windows 接收端落盘路径/大小/SHA-256，不能标为“落盘成功” |

`kemi.files.send` 当前可调用参数合同：

| 参数 | 必填 | 约束 |
|---|---:|---|
| `sourcePath` | 是 | 本机绝对路径；普通文件、非符号链接、调用时存在且可读；当前 KEMI 上限 16 MiB |
| `targetDeviceId` | 是 | 1–256 字符，必须来自紧邻调用前的 `kemi.devices.list`，并再次核对在线和证书身份 |
| `targetName` | 是 | 1–255 字符，只能是文件名，不得包含绝对路径、目录穿越或路径分隔符 |
| `conflictPolicy` | 是 | 当前生产值 `receiver-default`；同名处理由接收端安全策略决定，不得静默覆盖 |

VibeKits 调用时先刷新目录和设备列表，再通过 `vibekits.mcp.tool_call` 原样传递 `instanceId/toolName/arguments`。服务端必须在 110 秒内返回完成、拒绝或 `TARGET_RESPONSE_TIMEOUT`，取消准备/上传任务、关闭会话并释放发送锁。要宣称发送成功，必须另外取得接收端实际保存路径、文件大小和 SHA-256，并与发送端一致；目录可调用、进入发送链路或 `last_status` 有记录都不能替代落盘证据。

### 5.2 端点参数必须写到可直接连接

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

实例首次准备 MCP 时生成 EC P-256（`prime256v1`）私钥和十年自签名 X.509 证书。证书与私钥必须跨重启稳定；VibeKits 将两者分别保存在 Windows Credential Manager、macOS Keychain 或 Android Keystore，不写入工作区、普通配置、日志或 UDP。系统凭据单项写入由 OS 原子完成；创建顺序为 key→cert，cert 失败立即删除 key，只有一边存在时下次重建完整 pair。指纹是证书 DER 的 SHA-256，不是 PEM 文本或公钥字符串的哈希。

客户端允许自签名证书仅用于取得 peer certificate，随后必须常量时间比较公告中的完整 SHA-256 指纹；不匹配立即断开且不发送 HTTP 内容。禁用证书校验但不固定指纹、HTTP、302 跳转、系统代理和把 Token 放在 URL 都不合规。实例证书变化按新身份安全事件处理：清目录并要求用户确认，不能静默信任。

所有 LMCP JSON 请求都已序列化且受 1 MiB 上限约束，客户端必须发送准确 `Content-Length`，不得依赖 `Transfer-Encoding: chunked`。这是 Windows、小型原生 HTTP Server 与 Dart/Flutter 客户端共同互通的硬门槛；服务端可以支持 chunked 作为扩展，但不能要求客户端只能使用 chunked。

`capabilityDigest` 的输入是完成所有分页后的规范对象 `{"tools":[...],"nextCursor":null}`：Map key 递归按 Unicode 字符串排序，数组保序，UTF-8 编码后 SHA-256。tools 中必须包含 name/title/description/inputSchema/annotations 以及实现公开的 risk 扩展。客户端必须基于服务端返回的**原始完整工具对象**计算摘要，不能先映射成自己的 UI 模型再计算，否则未知扩展或结构化 `risk` 会被删除/改形。公告三个位置的 digest 完全相同；任何差异拒绝目录。`catalogRevision` 是独立的单调变更键，不能用四位摘要截断代替。

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

### 5.3 `tools/list` 必须完整且可分页

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

### 5.4 `tools/call` 参数和结果

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

身份扩展字段允许位于 `tools/call.result` 顶层，或位于 MCP 标准的 `tools/call.result.structuredContent`；同一次响应不得给出两套冲突值。VibeKits 从两处合并读取后仍严格比较公告的 `instanceId`、实际工具名和 `catalogRevision`，缺失或不一致都拒绝结果。

### 5.5 异步任务必须提供完整参数和可回收结果（KEMI-BM 生产样例）

“发现了工具”不算完成。提供者必须在 `tools/list` 中完整给出每个参数的类型、必填项、枚举、长度和语义，并保证调用方在 APP 重启或原调用断开后仍能取回终态。以 2026-08-31 真机 `KEMI-BM@hua-41B8C7FDF4`（`192.168.3.62:9443/mcp`、APP 2.1.5、catalogRevision 3）为已验收样例，其五个工具合同如下：

| 工具 | 风险 | 精确输入 | 必须返回 |
| --- | --- | --- | --- |
| `kemi.benchmark.device_status` | `readOnly` | 空对象，`additionalProperties=false` | 实例/版本、MCP 状态、任务状态、附近 LMCP/2 数量；不得返回私钥、原始硬件配置 |
| `kemi.benchmark.last_result` | `readOnly` | 空对象，`additionalProperties=false` | `ok`、`available`；有结果时返回完整 `result` 和 `reportSha256`，无结果返回稳定 `NO_RESULT`；不得返回本地绝对路径 |
| `kemi.benchmark.run` | `controlsDevice` | 必填 `mode`：`quick` 或 `stability`；必填 `idempotencyKey`：字符串 8–128 字符；拒绝额外参数 | 审批通过后返回非空 `taskId`、状态工具名、建议轮询秒数；同一幂等键重试必须指向同一任务 |
| `kemi.benchmark.status` | `readOnly` | 必填 `taskId`：字符串 1–128 字符；拒绝额外参数 | 活动态返回审批/阶段/轮次进度和 `final=false`；完成态必须在同一响应返回 `final=true`、完整 `result`、`reportSha256`；未知/过期任务返回稳定 `TASK_NOT_FOUND` |
| `kemi.benchmark.cancel` | `controlsDevice` | 必填 `taskId`：1–128 字符；必填 `idempotencyKey`：8–128 字符；拒绝额外参数 | 返回当前任务终态；重复取消必须幂等；运行中的设备控制仍需被调用端审批 |

标准调用流程固定为：

1. 先从已固定证书且摘要验证通过的当前目录取得 Schema，禁止调用方硬编码旧 revision 或猜参数。
2. 调用 `run({"mode":"quick","idempotencyKey":"<8-128 字符唯一键>"})`。被调用端必须弹出本机权限确认；拒绝或审批超时返回 `isError=true`、稳定错误码（生产样例为 `DENIED`），调用方立即停止且不得伪造 taskId。
3. 审批通过后保存 `taskId`，按返回的建议间隔（缺失时 5 秒，客户端夹在 2–15 秒）调用 `status({"taskId":"..."})`，直到 `final=true`。查询本身必须只读且可跨调用方重启恢复。
4. 若网络/调用方在运行中断开，恢复后调用 `last_result({})`；提供者至少保留最近一条完整终态，使调用方仍能取得结果证据。
5. 调用方只有同时验证 `isError=false`、`ok=true`、实例/工具/revision 身份、`result` 为对象、`reportSha256=sha256:<64 位小写十六进制>` 后，才能宣布任务完成。

本次真实回收验证通过：VibeKits 调用 `kemi.benchmark.last_result` 得到 `isError=false`、`available=true`、完整三轮 `result`；taskId=`b07e6779-8815-45e2-b94e-dea3a7ff2311`，mode=`quick`，elapsedMs=`73744`，finalScore=`99.15625`，grade=`S`，capacity/frame/input/stability 均为 `100`，reportSha256=`sha256:db6d5ff14dd3a060469a5c5d21804a0c6f196b3e967a4a6c0760384f34cfc363`。另一次 `run` 在未获本机批准时正确返回 `DENIED`，证明权限门禁没有被远程调用绕过。

VibeKits 服务端仅接受私网/loopback 来源的 `POST /mcp`，其他 path/method 返回 404，排空时返回 503，并发超过 8 返回 429，请求超过 1 MiB 返回 413。JSON-RPC parse/invalid request/invalid params/method not found/internal error 分别使用标准 `-32700/-32600/-32602/-32601/-32603`；通知成功可返回 HTTP 202 空响应。

所有远端 `tools/call` 必须进入与本机 Harness 相同的 `VibekitsHarnessToolBridge.invoke`：先按当前 inputSchema 再验证参数，再按 `readOnly/writesData/controlsDevice/destructive` 执行当前权限策略；需要审批时在本机显示工具、目标和有界参数，拒绝即不执行。成功、失败和拒绝都写入 `HarnessToolActivityStore`，不得因为来源是 KEMI 或另一台 VibeKits 而绕过审批/审计。MCP 总开关默认关闭；只有显示证书指纹和完整目录的风险确认通过后才监听首选 9443 或公告中的真实回退端口并广播。

VibeKits 的发现接收与“向外暴露 MCP”开关相互独立：即使总开关关闭，APP 仍监听局域网公告并显示其他设备；关闭只停止本 APP 的 HTTPS Server 和对外公告。运行态路径不得从 `Directory.current`/工作区推导。开关同意状态保存在平台 Application Support 的 `Vibekits/mcp/exposure.json`；本机进程注册目录保存在平台 Application Cache 的 `Vibekits/mcp/registrations`。任一本地注册目录不可写都只能令 local 层为空，不能阻断 LAN 订阅。初始化失败必须回滚 started/subscription/timer 状态，允许下一次重试。

以下情况 VibeKits 会拒绝调用：工具不在当前目录、Schema 无效、目录摘要不匹配、实例指纹改变、设备已 `goodbye`/TTL 离线、端点跳出私网、响应超出限制。

VibeKits 对目录握手使用 8 秒短超时，对 `tools/call` 使用 120 秒调用超时。需要等待接收端授权的服务必须在 110 秒内返回完成、拒绝或 `TARGET_RESPONSE_TIMEOUT`，预留结构化响应传输时间；不得让服务端任务在客户端退出后无限持锁。超过此时长的工作必须返回 `taskId`，并提供 status/cancel 工具。

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

### 6.1 每个工具必须说清“能做什么”

`tools/list` 和 APP 接入文档对每个工具都必须给出：

- 稳定 `name`、人类可读 `title` 和不含糊的 `description`；
- 完整 `inputSchema`：字段、必填、类型、范围、枚举、默认值、`additionalProperties`；
- `readOnly/writesData/controlsDevice/destructive`、外发数据范围和审批点；
- 前置条件、成功 `structuredContent` 字段、稳定错误码、超时/取消/幂等语义；
- 当前验收状态：只完成 `tools/list` 不得写成“功能已成功”。

文件发送必须是显式 `send` 工具，并提供可查的进度/终态；异步长任务必须另有 `status` 和 `cancel`。“设备列表里有目标”不等于“能发文件”，发送端成功也不等于接收端已落盘；最终验收需比对接收路径、大小和 SHA-256。

### 6.2 Harness 的长期评分和固定路由

每次 Harness 选择 MCP 时必须先刷新完整目录，固定按层选择：

```text
app（VibeKits 自身 MCP） → local（本机其他进程 MCP） → lan（局域网 MCP）
```

评分不能让低层候选越级抢占高层；只在同一层的同类候选间按 `reputation.score DESC` 排序。未评分工具初始 60 分且界面保持普通样式；一旦有自动结果或人工评分，MCP 列表必须显示分数/等级标识。低分和 `garbage` 工具降权但仍可见，不能伪装成不存在。

评分是跨项目、跨会话、跨重启的长期记忆，主键是规范化后的 `toolName`，不是设备实例。因此多台设备提供同名工具（例如多台 KEMI 的 `kemi.files.send`）共享同一个全局分数；每台设备的在线状态、证书和端点仍须逐台实时验证。记录字段至少包含总调用、成功、失败、连续失败、平均延迟、自动完成质量、可选人工 0–5 分和更新时间。

当前计算规则为：自动完成质量映射到 0–100；有人工评分时使用 `35% 自动质量 + 65% 人工评分`；每次连续失败再扣 7 分，结果限制到 0–100。等级为 `excellent >=85`、`good >=70`、`neutral >=50`、`poor >=30`、`garbage <30`。人工 0 分表示垃圾并强力降权；成功会清零连续失败。调用完成后必须按真实完成质量记录，不能只因 HTTP/MCP 返回成功就给满分。

Harness 通过 `vibekits.mcp.reputation_list` 查看全局记忆，通过 `vibekits.mcp.reputation_rate` 写入 0–5 分。任何评分都不能绕过 TLS 指纹、目录摘要、inputSchema、在线检查或写入/设备控制审批。

## 7. 第三方 APP 交付检查表

- [ ] 显示名称包含 APP 名、主机名和 10 位硬件识别码。
- [ ] `app.id`、`hardwareCode`、`instanceId` 重启后稳定。
- [ ] 有用户可见、可持久化的 MCP 开关。
- [ ] 从关闭到打开会先显示完整工具清单、证书身份、风险和撤销方法；拒绝时保持关闭。
- [ ] OFF/STARTING/ON/DRAINING/ERROR 的状态有明显区别。
- [ ] 打开发送 `announce`，关闭发送 `goodbye` 并停止服务。
- [ ] 实现标准 `initialize/tools/list/tools/call`。
- [ ] 每个工具具有完整描述和 JSON Schema。
- [ ] 文件传输能力提供显式 send 和可查终态；异步长任务另有 status/cancel，不能只列设备。
- [ ] 每个工具已写明用途、全部参数、风险、成功结果、错误码和实际验收状态。
- [ ] 接口变化更新目录版本并发出通知。
- [ ] 广播不包含秘密或业务数据。
- [ ] 两台真实设备验证上线、调用、关闭立即消失、断电 TTL 消失。
- [ ] 通过 VibeKits 的第三方 LMCP 合规测试后才标记完成。

## 8. VibeKits 当前实现对应关系

- 身份生成：`lib/features/dev_tools/domain/mcp_device_identity.dart`
- 开关和持久化：`McpExposurePreferences`
- `announce/goodbye`：`LanPeerDiscoveryService`
- P-256 实例证书、HTTPS `/mcp`、MCP 服务端：`VibekitsLmcpExposureServer`
- 证书固定和远端 MCP 客户端：`LmcpRemoteClient`
- 实时三层目录：`McpCapabilityDirectory`
- 界面：Harness 右侧工具轨的 MCP 明确开/关状态、首次/重新打开授权菜单、本 APP MCP 完整列表、本机 MCP 和局域网 MCP 列表
- Harness 远端路由：`vibekits.mcp.catalog_list` 和 `vibekits.mcp.tool_call`

VibeKits 不再把扩展控件横向铺在 Harness 顶栏，也不把 Flutter 浮层叠在 Windows 原生 WebView 上。Harness Web 内容和一条 60px 的右侧工具轨采用物理分栏；不再保留“工具”总按钮。MCP 图标直接表示“打开本机 MCP”，与本机 MCP、局域网 MCP、飞书、日志、远程操作和设置使用同尺寸小图标纵向排列，悬浮后展示完整设备名、接口范围和当前状态。点击已关闭的 MCP 图标或设置面板开关时，必须先弹出权限和风险说明，仅“确认开启”后才启动服务、持久化并广播；关闭可立即执行。这是对外暴露边界的一次确认，不是普通 MCP 工具的逐次审批；远程 Harness 任务控制仍独立审批。本机/局域网设备数量使用右上角小徽标。设置图标打开统一面板，可查看设备身份、切换 MCP、读取三层设备数和刷新目录。工具轨不得随主机名长度变化，不得遮挡 WebView，不得把控件挤向左侧。

### 8.1 VibeKits 1.9 当前正式传输

VibeKits 当前实现就是本文的 LMCP/2 `https-streamable-http`，不再对外公告无证书 `http-jsonrpc`。用户确认后启动 HTTPS `/mcp`，固定端口被同机 KEMI 占用时可回退动态端口，但公告中的两个 endpoint 必须精确携带真实端口、`/mcp`、证书指纹、协议版本、目录版本和摘要。客户端每次从实时公告取得端点，固定 TLS 证书后依次执行 `initialize → notifications/initialized → tools/list → tools/call`。

本文是第三方 APP 的唯一实现入口。

## 9. 双向真实验收（交付门禁）

自动化先执行：

```bash
flutter analyze --no-pub lib test
flutter test --no-pub test/lmcp_exposure_server_test.dart \
  test/lan_peer_discovery_service_test.dart \
  test/mcp_capability_directory_test.dart \
  test/mcp_exposure_consent_dialog_test.dart \
  test/mcp_device_identity_test.dart
```

其中必须覆盖：持久 P-256 证书重载指纹不变；严格公告 `<=1200` bytes；两个进程/实例共享一个 UDP 端口并收到 LMCP/2；RFC1918 多网卡地址全部入选且公网/回环排除；真实 TLS 指纹固定；initialize→分页 tools/list→tools/call；错误 schema 不执行；写入类工具进入审批；关闭清公告和 endpoint。

### 9.1 VibeKits ↔ VibeKits

优先使用两台不同机器 A/B；同机验证时第一个服务使用 9443，第二个服务必须广播其真实动态端口：

1. 两边 MCP 初始为关；确认 UDP 47831 在监听但 TCP 9443 未监听、无 LMCP/2 announce。
2. A 打开，确认授权框列出证书指纹和全部工具；抓包看到 A 每 4 秒 announce，B 在 12 秒内出现 A。
3. B 对 A 依次发送 initialize、notifications/initialized、完整分页 tools/list；重算摘要必须等于公告。
4. B 调用 `vibekits.calculator.programmer`，参数 `{"expression":"1+1"}`；结果 `isError=false`，并精确回显 A 的 instanceId、工具名、revision 和 traceId。
5. 选择一个 writesData/controlsDevice 工具，只验证 A 出现本机审批；点拒绝，确认未产生副作用且审计状态为 denied。禁止拿真实用户文件做破坏测试。
6. 交换 A/B 重复 2–5，证明双向而非单向。
7. A 关闭：先抓到 goodbye，B 立即移除；模拟断电不发 goodbye，B 在最后有效公告 12 秒后移除；A 公告的 TCP 端口不再接受连接。

### 9.2 VibeKits ↔ KEMI传书

已完成的生产证据是：Mac VibeKits 能固定 KEMI build102 证书、读取四工具目录并真实调用三个只读工具。这只证明了本机接收与调用。2026-08-31 的 10 秒实时监听只收到 Mac KEMI LMCP/2，没有收到 Windows VibeKits 任何公告；Windows 端也尚未给出“收到 KEMI announce”的抓包。因此当前跨机双向发现为**未验收**，必须按以下步骤补齐，不能用同机单元测试冒充：

1. KEMI 的 MCP 面板出现 VibeKits LMCP/2（不是兼容 LMCP/1），显示与抓包一致的 `instanceId/192.168.x.x:<实际端口>/mcp/fingerprint/revision/digest`。
2. KEMI 初始化 VibeKits 并读取完整目录，调用同一个只读计算器用例成功；VibeKits 审计记录来源工具、结果和耗时。
3. KEMI 发起高风险工具时 VibeKits 本机审批可拒绝；KEMI 收到结构化 `isError`，不得自动改走 shell。
4. 分别关闭 KEMI 和 VibeKits，另一端验证 goodbye 立即消失、断电 TTL 消失、证书篡改拒绝、digest/revision 改变重新加载。
5. Windows 必须运行包含 LMCP/2 接收器的新构建，不能只核对 `1.9.0-dev.137+2137` 文本版本；验收记录必须同时保存 Git/source revision 或产物 SHA-256。
6. Windows 签名安装程序必须为实际 VibeKits 可执行文件创建 Private profile 入站 UDP 47831 和公告 TCP 端口规则；先用 `pktmon`/抓包证明收到 KEMI 报文，再调查 UI 解析。

验收记录至少保存：两端版本/SHA-256、两端私网 IP、10 秒 UDP 抓包、公告 TCP 端口建连、initialize 与每页 tools/list 的脱敏 JSON、摘要重算、一次只读调用、一次拒绝审计、goodbye/TTL 时间。不得保存私钥、Token、完整用户路径或文件内容。

## 10. 最短排障决策树

```text
对端列表为空
  ├─发送端没有 4 秒 announce → MCP 是否确认开启？公告 TCP 端口是否真实监听？包是否 >1200？
  ├─发送端有、接收端抓不到 → 是否每张私网网卡 join+send？防火墙/VPN/AP isolation？
  └─接收端抓到但 UI 丢弃 → 按 4.3 逐字段检查，尤其 endpoint 三处一致性

列表存在但目录为空
  ├─公告 TCP 端口不通 → 防火墙、端口占用、服务是否只绑定 loopback
  ├─TLS 失败 → 抓到的证书 DER SHA-256 是否等于公告
  └─tools/list 后拒绝 → 分页是否完整、canonical JSON/digest 是否一致

目录存在但调用失败
  ├─revision/instance/tool 不一致 → 清旧缓存并重新 initialize/list
  ├─invalid params → 严格按 inputSchema 传参，不猜字段
  └─denied/isError → 查看被调用端本机审批和脱敏审计，不绕过权限
```

如果 `lsof`/`Get-NetTCPConnection` 显示 9443 已被同机另一个 LMCP APP 占用，VibeKits 允许绑定 OS 分配的动态端口，但必须在 announce 的两个 endpoint 精确广播这个端口并通过同样的 TLS/摘要校验；KEMI 的严格解析器接受 `1..65535` 的真实端口。任何端口都不得“偷偷”使用而不更新公告。自动化测试必须通过依赖注入使用隔离的 TCP/UDP 端口。
