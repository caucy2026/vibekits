# LMCP/1：局域网 MCP 发现、授权与协同协议

> **历史文档：禁止用于新 APP。** 第三方开发、联调和双机验收只使用 [LMCP/2 唯一互通标准](50_LMCP_APP_DEVICE_IDENTITY_AND_SWITCH_STANDARD.md)。LMCP/1 仅供 VibeKits 把旧节点显示为“仅发现、不可调用”。

> **历史文档：禁止用于新 APP。** 第三方开发、联调和双机验收只使用 [LMCP/2 唯一互通标准](50_LMCP_APP_DEVICE_IDENTITY_AND_SWITCH_STANDARD.md)。LMCP/1 仅供 VibeKits 把旧节点显示为“仅发现、不可调用”。

状态：VibeKits 开放应用协议 v1.0，作为兼容基础保留；自动目录配对和三层实时列表由 [LMCP 2.0 架构](49_REALTIME_THREE_TIER_MCP_FABRIC_ARCHITECTURE.md) 取代。它不是 MCP 官方标准；MCP 本身仍使用标准 JSON-RPC、`initialize`、`tools/list` 和 `tools/call`。

## 1. 设计目标

任何现有或未来应用只要：

1. 按 LMCP/1 广播自己的 MCP 服务声明；
2. 提供声明的安全 MCP 传输；
3. 在服务端取得用户授权；
4. 返回标准 MCP 工具目录；

就能被 VibeKits Harness 或其他 LMCP 客户端发现并调用。发现不等于配对，配对不等于控制授权。

## 2. 网络发现

- IPv4 组播：`239.255.42.99:47831`。
- 发送间隔：推荐 4 秒；允许 3～10 秒。
- 数据报：UTF-8 JSON，最大 1024 字节，不分片。
- TTL：声明字段 `ttlSeconds`，范围 8～60；缺省 12。超过 TTL 未刷新即离线。
- 接收端只接受 RFC1918 私网来源；公网、回环、链路本地和非法地址丢弃。
- 未知字段必须忽略；未知主版本必须显示为不兼容且不得连接。

规范声明：

```json
{
  "protocol": "lmcp-discovery",
  "protocolVersion": "1.0",
  "messageType": "announce",
  "instanceId": "稳定且不含用户秘密的实例ID",
  "app": {
    "id": "com.example.future-app",
    "name": "Future App",
    "version": "2.3.0"
  },
  "endpoint": {
    "transport": "ssh-stdio",
    "port": 22
  },
  "mcp": {
    "protocolVersions": ["2025-06-18"],
    "capabilityDigest": "sha256:..."
  },
  "security": {
    "pairingRequired": true,
    "authMethods": ["ssh-ed25519"],
    "controlApproval": "per-tool"
  },
  "ttlSeconds": 12,
  "sentAt": "2026-08-30T04:00:00Z"
}
```

`instanceId` 在同一安装实例内稳定，长度 1～80；重装可以变化。不得使用 API Key、Token、邮箱、手机号或完整用户名生成。`capabilityDigest` 是规范化 `tools/list` 的 SHA-256 摘要，用于提示目录变化，不能替代连接后的真实 `tools/list`。

## 3. 传输与互操作

LMCP/1 必须支持 `ssh-stdio`：客户端以 SSH 进程的 stdin/stdout 承载 MCP JSON-RPC，每行一个完整 JSON 消息。SSH 必须固定 host key、使用每设备独立 Ed25519 身份并采用强制命令；禁止授权通用 Shell。

未来次版本可以增加 `https-streamable-http`，但只有受信 CA 或人工固定证书指纹、TLS 1.2+、独立客户端身份和服务端授权都满足时才能声明。发现包内 Token 和查询参数 Secret 始终禁止。

VibeKits 1.9 的过渡实现另接受 `http-jsonrpc`：它只允许回环和 RFC1918 私网源地址，只有用户在提供端确认风险并打开 MCP 开关时才监听，关闭时立即发送 `goodbye` 并停止端口。端点固定为 `POST /mcp`，实现标准 JSON-RPC 2.0 的 `initialize`、`ping`、`tools/list`、`tools/call`，正文上限 1 MiB。该模式用于可信、隔离的局域网自动协作，不具备 TLS 的窃听/篡改防护，不能跨路由器暴露，也不能标记为 LMCP/2 安全合规；生产跨网部署仍必须使用 HTTPS 或 SSH。

连接成功后必须重新执行标准 MCP：

```text
initialize → notifications/initialized → tools/list → tools/call
```

广播的能力摘要和工具名称仅用于界面提示，不能跳过 `tools/list`。

## 4. 三层授权

| 层次 | 服务端必须验证 | 撤销效果 |
|---|---|---|
| 发现 | 私网来源、包大小、版本和字段边界 | 节点从候选列表消失 |
| 配对 | 本机用户批准客户端公钥并固定服务端 host key | 该设备立即无法建立 MCP |
| 控制 | 每次工具调用按工具风险、目标和参数审批 | 只拒绝本次调用或当前会话 |

服务端必须把 `readOnly/writesData/controlsDevice/destructive` 等风险映射到自己的审批策略。远端主智能体不能替执行端用户批准控制操作，也不能因“最高权限”绕过配对和目标确认。

## 5. 协同任务约定

普通工具直接使用各应用自己的 MCP Schema。需要长时间、可等待、可取消的协同任务时，应用应额外实现以下三个工具：

- `collaboration.task_start`
  - 输入：`requestId`（幂等键）、`objective`、`allowedToolIds[]`、`deadline`、`evidenceLevel`。
  - 输出：`taskId`、`phase=queued|running`、`acceptedScope`、`startedAt`。
- `collaboration.task_status`
  - 输入：`taskId`、`waitSeconds`（0～45）。
  - 输出：`phase`、`progress`、`message`、`result?`、`evidence[]`、`updatedAt`。
- `collaboration.task_cancel`
  - 输入：`taskId`、`reason`。
  - 输出：最终 `phase` 和资源回收状态。

主智能体必须保存 `taskId` 并长轮询同一任务，禁止因超时重复 `task_start`。任务只能调用 `allowedToolIds`，目标端仍逐项执行自己的权限和审批策略。结果必须标明来自哪个 `instanceId/app.id`，不能把多个节点输出混成无来源结论。

## 6. 安全和隐私

发现包严禁包含：Bearer Token、MCP连接文件、模型 Key、App Secret、用户任务、工具参数、文件路径、聊天内容、设备公钥正文或任何凭据。节点名称和 IP 未经认证，可以被伪造；UI 必须显示“未授权”，直到 SSH host key 与客户端公钥双向核验完成。

实现必须限制：数据报大小、字段长度、JSON深度、节点数量、刷新频率和错误日志长度。不得响应发现包执行命令，不得通过广播自动接受配对，不得因为同一网段自动批准控制。

## 7. 兼容性

- 主版本相同：忽略未知字段，按已知能力降级。
- 主版本不同：只展示不兼容节点，不连接。
- `app.id` 不得用于权限判断；权限绑定 `instanceId + SSH host key + 客户端公钥`。
- VibeKits 在过渡期继续接收旧 `vibekits.mcp.peer` 声明，但新应用必须发送 `lmcp-discovery/1.0`。

## 8. 第三方最小验收

第三方应用交付前至少证明：合规广播、VibeKits可发现、未配对不能连接、错误host key被拒绝、批准后`initialize/tools/list`成功、控制工具触发目标端审批、长任务可等待和取消、撤销公钥后立即失效、离线后按TTL移除、广播与日志均不含秘密。
