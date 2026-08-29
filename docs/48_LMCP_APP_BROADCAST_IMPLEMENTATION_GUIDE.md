# LMCP/1 应用广播与协同接入实施指南

版本：1.0  
状态：已被 [三层实时 MCP 能力网络架构](49_REALTIME_THREE_TIER_MCP_FABRIC_ARCHITECTURE.md) 取代；本文仅保留 LMCP/1 历史实现参考
适用对象：所有需要被 VibeKits Harness 或其他智能体在局域网发现、授权和调用的 APP、服务、设备控制程序与 Sidecar。

## 1. 最终目标

每个程序都是一个独立“能力节点”。程序启动后主动在局域网上报自己的存在和安全 MCP 入口；Harness 发现节点后，在用户批准配对的前提下读取其真实 `tools/list`，形成统一能力池，再依据任务、工具 Schema、平台、在线状态、风险和授权范围选择实际执行节点。

```text
APP A ──LMCP广播──┐
APP B ──LMCP广播──┼→ Harness发现候选节点
APP C ──LMCP广播──┘          │
                              ▼
                     LMCP/1 手工配对（旧）
                              │
                              ▼
                   安全MCP initialize/tools/list
                              │
                              ▼
                   本机+局域网统一能力池
                              │
                       用户提交自然语言任务
                              │
                              ▼
                 拆分、路由、执行、等待、汇总
```

发现、配对和控制是三个独立阶段：发现不能调用；配对只允许建立 MCP；真正的写入和控制仍由执行端按工具、目标和参数审批。

## 2. APP 必须实现的四个部分

### 2.1 标准 MCP Server

APP 必须提供标准 MCP JSON-RPC，至少正确实现：

- `initialize`
- `notifications/initialized`
- `tools/list`
- `tools/call`
- `ping`

每个工具必须有稳定名称、清晰说明和完整 JSON Schema。说明要写明用途、副作用、目标范围、前置条件、是否长时间运行以及失败含义，不能依赖智能体猜参数。

### 2.2 LMCP/1 发现广播

APP 每 4 秒向 `239.255.42.99:47831` 发送一个最大 1024 字节的 UTF-8 JSON 数据报。局域网发现 TTL 推荐 12 秒，连续超过 TTL 没有广播即视为离线。

最小合规报文：

```json
{
  "protocol": "lmcp-discovery",
  "protocolVersion": "1.0",
  "messageType": "announce",
  "instanceId": "camera-service-line-01",
  "app": {
    "id": "com.example.camera-service",
    "name": "Camera Service",
    "version": "1.4.2"
  },
  "endpoint": {
    "transport": "ssh-stdio",
    "port": 22
  },
  "mcp": {
    "protocolVersions": ["2025-06-18"],
    "capabilityDigest": "sha256:0123456789abcdef..."
  },
  "security": {
    "pairingRequired": true,
    "authMethods": ["ssh-ed25519"],
    "controlApproval": "per-tool"
  },
  "ttlSeconds": 12,
  "sentAt": "2026-08-30T05:00:00Z"
}
```

字段定义以 [发现报文 JSON Schema](schemas/lmcp-discovery-1.0.schema.json) 为机器权威来源。

### 2.3 安全 MCP 传输

首个强制支持的传输是 `ssh-stdio`：MCP JSON-RPC 通过 SSH 进程 stdin/stdout 传输，每行一个完整 JSON 对象。

要求：

- 服务器 host key 必须固定并由用户核对。
- 每个调用设备使用独立 Ed25519 密钥，不共享私钥。
- 服务端必须先由本机用户批准客户端公钥。
- `authorized_keys` 使用 `restrict` 和强制 MCP 命令，不提供通用 Shell。
- 撤销一个设备不得影响其他设备。

支持 `https-streamable-http` 的程序必须使用 TLS 1.2+、证书指纹固定或受信 CA，以及独立客户端身份；广播必须包含 `path` 和 `certificateSha256`。禁止明文 HTTP。

### 2.4 执行端授权与审计

APP 自己负责最终控制权。至少区分：

- `readOnly`：只读查询。
- `writesData`：写数据或改变持久状态。
- `controlsDevice`：控制设备、进程、网络或外部系统。
- `destructive`：删除、覆盖、卸载、格式化或不可逆操作。

高风险工具必须在实际执行端展示工具、目标、关键参数和风险，由该端用户批准。审计至少记录来源节点、工具、目标、批准结果、执行结果和时间，但不能记录密码、Token、私钥或 Secret。

## 3. APP 启动时序

```text
1. 启动业务服务
2. 启动本机 MCP Server
3. 确认 MCP Server 已可 initialize
4. 计算规范化 tools/list 的 capabilityDigest
5. 启动 LMCP 广播
6. 等待配对或 MCP 调用
7. 工具目录变化 → 更新 digest → 下一次广播生效
8. MCP 不可用 → 停止广播
9. APP 退出 → 停止广播并释放端口
```

禁止 MCP 尚未可用就广播“在线”，也禁止程序退出后保留 Sidecar 继续广播假节点。

## 4. Harness 发现和调用时序

```text
收到广播
  → 校验私网来源/大小/协议主版本/字段范围
  → 创建 authorized=false 候选节点
  → 用户选择配对
  → 核对 host key + 批准客户端公钥
  → MCP initialize
  → MCP tools/list
  → 对比 capabilityDigest
  → 建立已授权能力索引
  → 等待任务
```

接到用户任务后：

```text
理解任务
  → 从本机和已授权远端能力池检索候选工具
  → 校验Schema、平台、在线状态、风险、授权和负载
  → 生成任务分解与执行节点计划
  → 必要的主机端审批
  → 本地/远端执行
  → 长任务轮询同一taskId
  → 汇总带来源证据的结果
```

节点名称、APP 名称和广播中的能力摘要都不能作为工具存在的证据；连接后的 `tools/list` 才是事实来源。

## 5. 工具设计规范

一个可自动调用的工具必须具备：

- 唯一稳定名称，推荐 `<domain>.<resource>.<action>`。
- `description` 说明何时调用、何时不能调用和副作用。
- 参数逐项标明类型、必填、默认值、枚举、格式和范围。
- 返回结构区分业务失败、授权拒绝、超时和传输失败。
- 写操作提供预览、幂等键或版本摘要。
- 分页明确终止条件。
- 所有输出有上限，大结果返回受控 artifact 引用。
- Secret 只通过应用自己的安全凭据系统引用，不放 MCP 参数。

示例：

```json
{
  "name": "camera.capture.snapshot",
  "description": "从指定已登记摄像头拍摄一张图片；只读取设备，不改变摄像头配置。",
  "inputSchema": {
    "type": "object",
    "additionalProperties": false,
    "required": ["cameraId"],
    "properties": {
      "cameraId": {
        "type": "string",
        "description": "camera.list 返回的稳定摄像头ID"
      },
      "quality": {
        "type": "integer",
        "minimum": 30,
        "maximum": 100,
        "default": 85
      }
    }
  }
}
```

## 6. 长任务统一约定

预计超过普通 MCP 超时的任务必须实现：

| 工具 | 必要输入 | 必要输出 |
|---|---|---|
| `collaboration.task_start` | `requestId, objective, allowedToolIds, deadline, evidenceLevel` | `taskId, phase, acceptedScope, startedAt` |
| `collaboration.task_status` | `taskId, waitSeconds=0..45` | `phase, progress, message, result?, evidence[], updatedAt` |
| `collaboration.task_cancel` | `taskId, reason` | `phase, cleanupState, updatedAt` |

规则：

- `requestId` 是幂等键；相同请求不得创建两个任务。
- 调用端保存 `taskId`，只轮询同一个任务。
- 任务只能调用 `allowedToolIds`。
- `deadline` 到期必须停止继续扩张工作。
- 用户取消后释放进程、文件句柄、端口和设备会话。
- 结果必须包含执行节点 `instanceId/app.id` 和证据来源。

## 7. 任务协同与节点选择

Harness 的选择顺序不是固定“本机优先”或“远端优先”，而是按约束评分：

1. 工具和 Schema 是否准确匹配任务。
2. 节点是否在线且已经配对。
3. 平台、硬件、文件和设备是否位于该节点。
4. 所需授权是否满足。
5. 风险是否最小。
6. 当前负载、预计耗时和网络延迟。
7. 数据是否可以不跨机器移动。

可以拆分的任务允许并行分派；具有先后依赖或会竞争同一设备的任务必须串行。主 Harness 必须保留子任务与节点映射，不能把多个节点结果混成无来源答案。

## 8. 错误与状态

推荐统一错误类型：

- `not_paired`
- `approval_required`
- `approval_denied`
- `capability_changed`
- `tool_unavailable`
- `invalid_arguments`
- `busy`
- `deadline_exceeded`
- `cancelled`
- `peer_offline`
- `transport_error`
- `partial_failure`

错误必须包含稳定类型、可读消息和可执行的下一步；不能只返回“失败”。发现节点在 TTL 到期后标为离线，正在执行的任务不能自动换节点重做，除非工具明确幂等且用户允许故障转移。

## 9. 广播中禁止出现的内容

- Bearer Token、OAuth Token、API Key、App Secret。
- SSH 私钥、公钥正文或密码。
- MCP connection file 内容。
- 用户任务、聊天、文件路径、设备序列号。
- 完整工具参数或业务数据。
- 可直接调用控制接口的一次性链接。

广播只是服务名片，不是授权凭证，也不是远程调用请求。

## 10. 新 APP 最小接入步骤

1. 复制[应用清单 Schema](schemas/lmcp-app-manifest-1.0.schema.json)。
2. 参考[示例清单](../examples/lmcp/future-app.manifest.json)填写 APP 信息。
3. 实现并本机测试标准 MCP Server。
4. 选择 `ssh-stdio` 或合规 HTTPS 传输。
5. 实现目标端配对、审批、撤销和审计。
6. 原生实现广播，或运行[参考 Sidecar](../tool/lmcp_reference_peer.mjs)。
7. 使用 `--validate-only` 检查最终广播和字节数。
8. 两台真实机器完成发现、拒绝、批准、调用、取消、撤销和离线测试。

旧程序使用 Sidecar：

```text
node tool/lmcp_reference_peer.mjs app.manifest.json --validate-only
node tool/lmcp_reference_peer.mjs app.manifest.json
```

Sidecar 只广播，不代理凭据；原程序仍须提供声明的 MCP 服务。

## 11. 完成定义

一个 APP 只有满足以下条件才能标记“可参与局域网协同”：

- 广播符合 LMCP/1 Schema 且小于等于 1024 字节。
- Harness 能发现并在 TTL 后正确移除。
- 未配对连接失败。
- 错误 host key 或已撤销设备连接失败。
- 配对后 `initialize/tools/list/tools/call` 通过。
- 工具 Schema 足以自动生成正确参数。
- 控制调用由执行端审批，拒绝后没有副作用。
- 长任务可等待、取消且不会重复启动。
- 结果带节点和证据来源。
- 广播、日志、错误和 Git 均无秘密。
- 至少完成一次真实跨设备验收；同机模拟不替代真实网络。

## 12. 相关机器文件

- [LMCP/1 完整协议](46_LAN_MCP_DISCOVERY_PROTOCOL_V1.md)
- [发现报文 Schema](schemas/lmcp-discovery-1.0.schema.json)
- [应用清单 Schema](schemas/lmcp-app-manifest-1.0.schema.json)
- [第三方接入包](47_LMCP_THIRD_PARTY_INTEGRATION_KIT.md)
- [示例应用清单](../examples/lmcp/future-app.manifest.json)
- [参考广播 Sidecar](../tool/lmcp_reference_peer.mjs)
