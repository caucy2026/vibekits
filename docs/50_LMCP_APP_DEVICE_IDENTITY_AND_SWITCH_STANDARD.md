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

VibeKits 将这些扩展控件按右上角两行分组：第一行是任务、日志和远程操作，第二行是设备名称/MCP 开关、本机 MCP、局域网 MCP。设备名称使用固定宽度和省略显示，完整名称由悬浮提示展示，不能因主机名过长把按钮挤入主界面左侧。

本文是第三方 APP 的实现入口；总体能力图、权限和任务路由见 [VibeKits 三层实时 MCP 能力网络架构](49_REALTIME_THREE_TIER_MCP_FABRIC_ARCHITECTURE.md)。
