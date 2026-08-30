# VibeKits 三层实时 MCP 能力网络架构

版本：2.0 架构评审稿  
状态：取代此前“人工配对后才能读取 MCP 列表”的设计  
核心目标：VibeKits 启动后无感、自动、实时地维护本 APP、本机进程和本局域网三个 MCP 工具列表，再由 Harness 根据实时能力完成任务。

第三方 APP 必须遵循的设备命名、硬件识别码、MCP 开关、上线/离线和远程等价调用要求，以 [LMCP/2 APP 设备身份、MCP 开关与远程等价调用标准](50_LMCP_APP_DEVICE_IDENTITY_AND_SWITCH_STANDARD.md) 为唯一实施入口。

## 1. 用户期望

用户打开 VibeKits 后不需要输入 IP、导入公钥、手工配对、添加 MCP 配置或点击刷新。系统自动完成：

```text
发现节点 → 安全握手 → 读取 tools/list → 建立实时能力索引 → 持续监听变化
```

界面始终展示三个相互独立的 MCP 列表：

1. **本 APP MCP**：VibeKits 自己实现并可直接执行的工具。
2. **本机 MCP**：同一台电脑上其他进程、插件、Sidecar 和 APP 提供的工具。
3. **局域网 MCP**：同一局域网中其他电脑、设备和 APP 提供的工具。

三个列表不能混成一个数字。Harness 可以在统一能力图中检索，但每个工具必须保留来源层、APP、实例、机器、连接和实时状态。

## 2. 总体架构

```text
                    ┌──────────────────────────┐
                    │       用户任务/Harness    │
                    └─────────────┬────────────┘
                                  ▼
                    ┌──────────────────────────┐
                    │   实时 MCP 能力图/路由器   │
                    │ Schema·状态·风险·负载·来源 │
                    └──────┬────────┬──────────┘
                           │        │
          ┌────────────────┘        └─────────────────┐
          ▼                         ▼                 ▼
┌──────────────────┐    ┌──────────────────┐  ┌──────────────────┐
│ A. 本APP MCP列表  │    │ B. 本机 MCP列表  │  │ C. 局域网MCP列表 │
│ 内存注册表        │    │ 本机发现代理     │  │ LAN发现与会话层  │
│ 事件直接更新      │    │ socket/stdio     │  │ 加密连接/心跳    │
└──────────────────┘    └──────────────────┘  └──────────────────┘
```

能力路由器只消费三个目录的标准化快照和增量事件，不直接扫描端口、不猜命令、不根据 APP 名称写死功能。

## 3. 三个 MCP 列表

### 3.1 本 APP MCP 列表

来源：VibeKits `HarnessToolDefinition` 和已接执行器。

特点：

- APP 启动时立即生成首个快照。
- 工具注册、平台门禁、运行时依赖变化时发布增量事件。
- 每项包含工具 Schema、风险、可执行状态和不可用原因。
- 不经过网络，不需要发现或连接授权。

### 3.2 本机 MCP 列表

来源只允许显式、可验证的本机机制：

- 操作系统用户级 MCP 注册目录。
- VibeKits 管理的本机 Sidecar 注册文件。
- 受控 Unix Domain Socket / Windows Named Pipe 公告。
- 已启动进程主动发布的本机 LMCP 公告。
- 用户现有 MCP 客户端配置的只读导入。

禁止扫描所有 TCP 端口、枚举无关进程命令行或读取其他用户凭据。

本机节点连接优先级：

```text
Named Pipe/Unix Socket → stdio启动器 → 127.0.0.1受保护HTTP
```

VibeKits 自动建立只读目录会话并执行 `initialize/tools/list`。进程启动、退出、注册文件变化或能力摘要变化时实时更新列表。

### 3.3 局域网 MCP 列表

其他 APP 按 LMCP 实时公告自己的存在、实例身份、安全 MCP 入口和能力摘要。VibeKits 收到公告后自动：

1. 校验私网来源、协议版本、字段和速率。
2. 建立仅限目录读取的加密发现会话。
3. 自动执行 `initialize/tools/list`。
4. 把普通工具提供者标为 `callable`，加入局域网列表。
5. 维持心跳并订阅能力变化。

这一过程不弹窗、不要求输入 IP、不要求手工配对。连接到普通 MCP 工具提供者后，本机 Harness 可以直接按 Schema 调用其工具，不再弹出二次审批。

## 4. 无感自动配对模型

“自动配对”定义为自动建立一个加密、可验证的 MCP 会话。本机 Harness 是受信任务控制器，可以通过该会话读取目录并调用普通 MCP 工具。

每个 APP 第一次安装时生成不可导出的实例身份密钥。广播包含实例公钥指纹和短时握手材料；两端使用挑战应答证明持有对应私钥，并协商短时加密会话。VibeKits 自动保存：

- `instanceId`
- `app.id/name/version`
- 实例公钥指纹
- 首次发现和最近在线时间
- 当前网络地址
- MCP 入口
- 能力摘要
- 会话状态

自动会话至少允许：

```text
initialize + ping + tools/list + capability changes + health + tools/call
```

普通工具提供者不做逐工具人工审批。实例指纹突然变化时按“新实例”处理并重新自动握手；旧实例标记离线。

唯一需要本机用户审批的场景是：**其他局域网智能体或 Harness 要把任务提交给本机 Harness，远程控制本机 Harness 工作**。该审批位于 Harness 远程任务入口，不位于 MCP 工具出口。

## 5. 实时更新机制

三个列表使用“完整快照 + 单调版本 + 增量事件”模型。

统一目录事件：

```json
{
  "catalogVersion": 128,
  "event": "tool_added | tool_updated | tool_removed | peer_online | peer_offline",
  "sourceTier": "app | local | lan",
  "instanceId": "...",
  "toolName": "...",
  "toolRevision": "sha256:...",
  "occurredAt": "2026-08-30T06:00:00Z"
}
```

更新来源：

- 本 APP：注册表内存事件，立即更新。
- 本机：文件监听、Named Pipe/Socket 断连和进程生命周期事件。
- 局域网：LMCP 在线公告、能力摘要变化、加密会话断开和 TTL。

列表更新目标：

- 本 APP 工具变化：一个事件循环内可见。
- 本机进程变化：目标 1 秒内，最迟 3 秒。
- 局域网变化：目标 4 秒内，离线最迟 12 秒。

每个节点维护状态：

```text
discovering → catalogConnecting → catalogReady → callable
                                      │             │
                                      └→ stale ←────┘
                                           │
                                        offline
```

`catalogReady` 表示目录可用；普通 MCP 节点完成握手后自动进入 `callable`。如果目标是另一个 Harness，则只有其远程任务入口取得会话授权后才接受任务。

## 6. 工具统一数据模型

每个工具索引必须包含：

| 字段 | 含义 |
|---|---|
| `sourceTier` | `app/local/lan` |
| `instanceId` | 具体应用安装实例 |
| `appId/appName/appVersion` | 应用身份 |
| `hostId/hostName/address` | 执行机器 |
| `toolName` | MCP真实工具名 |
| `description/inputSchema` | 标准MCP定义 |
| `risk` | 只读、写入、控制、破坏性 |
| `catalogVersion/toolRevision` | 实时版本 |
| `online/catalogReady` | 连接状态 |
| `authorizationState` | 普通工具自动可调，或远程Harness入口待批/已批/拒绝 |
| `latency/load` | 路由参考，不作为成功证据 |
| `lastSeen` | 最近在线时间 |

同名工具不能覆盖。统一工具键为：

```text
sourceTier / hostId / instanceId / toolName
```

## 7. Harness 接收任务后的行为

### 7.1 每个新任务读取实时目录

Harness 不在启动时缓存一份永久工具列表。每个新任务先判断是否需要工具；需要时调用后台目录的 `snapshotForTask()` 取得带 `catalogVersion` 的不可变快照，并依次查看：

```text
本 APP MCP → 本机其他进程 MCP → 本局域网 MCP
```

这个顺序表示先查看，不表示无条件选择第一个工具。Harness 比较工具描述、JSON Schema、在线状态、数据位置和任务风险后选择最匹配接口。执行前若版本已经改变则重新取快照；长任务每个新阶段也检查版本。后台负责发现和更新，智能体只读取最新快照，不维护另一份目录缓存。

### 7.2 对方怎样描述 MCP 接口

每个提供者必须返回标准 MCP `tools/list` 条目，至少包含：

```json
{
  "name": "serial.session_open",
  "title": "打开串口长会话",
  "description": "打开持续串口会话。先调用 serial.list_ports；成功后返回 sessionId。",
  "inputSchema": {
    "type": "object",
    "properties": {
      "port": {"type": "string", "description": "串口名，例如 COM3"},
      "baudRate": {"type": "integer", "default": 115200, "minimum": 300}
    },
    "required": ["port"],
    "additionalProperties": false
  }
}
```

- `name` 是稳定、唯一、可调用的机器标识。
- `title` 是用户可读短名称。
- `description` 必须说明用途、前置调用、返回结果、重要副作用和失败条件。
- `inputSchema` 是参数唯一权威来源，必须明确类型、必填项、默认值、枚举、范围和字段说明。
- 广播和 Schema 不得包含 Token、密码或私钥。
- 接口变化后更新 `catalogRevision`，VibeKits 随即重新读取 `tools/list`。

本机其他进程也可向 `.runtime-cache/mcp/registrations/<instanceId>.json` 原子发布注册文件：

```json
{
  "instanceId": "vendor-app-01",
  "name": "Vendor App",
  "appId": "com.vendor.app",
  "appVersion": "2.1.0",
  "transport": "stdio",
  "endpoint": "D:\\\\apps\\\\vendor-mcp.exe",
  "catalogRevision": "sha256:...",
  "updatedAt": "2026-08-30T08:00:00Z",
  "tools": []
}
```

写入方先写临时文件再原子改名，退出时删除自己的注册文件。当前实现每秒复核本机注册目录；局域网目录随 LMCP 心跳、上下线和能力摘要变化更新。

### 7.3 Harness 界面

Harness 顶部提供 `本机 MCP`、`局域网 MCP` 两个独立按钮和实时设备数。点击按钮显示设备列表；点击设备弹出接口详情，展示实例、应用版本、传输、端点、目录版本，以及每个工具的 `name`、标题、用途说明和格式化 `inputSchema`。设备已发现但尚未取得 `tools/list` 时必须明确显示“尚未返回接口目录”，不能把设备在线误报为接口可用。

Harness 不先选择机器，而是先把任务拆成所需能力：

```text
自然语言任务
  → 子目标
  → 所需输入/输出/副作用
  → 查询三层实时能力图
  → 过滤离线、Schema不符、平台不符节点
  → 计算候选执行计划
  → 本机Harness直接调用所选MCP工具
  → 执行并持续核对节点状态
```

选择评分至少考虑：

1. Schema 是否精确满足任务。
2. 数据、文件或设备实际位于哪台机器。
3. 节点当前是否在线、目录是否最新。
4. 工具风险和任务本身允许的副作用。
5. 平台、硬件和依赖。
6. 负载、延迟和任务预计时长。
7. 是否能避免跨机器传输敏感或大体积数据。

本机不是固定优先，局域网也不是固定优先；实际能力和数据位置决定执行节点。

## 8. 权限边界：只审批远程进入 Harness

权限由“谁在调用谁”决定，不由工具位于本机还是局域网决定：

| 调用方向 | 动作 | 是否审批 | 审批位置 |
|---|---|---:|---|
| 本机 Harness → 本 APP MCP | `tools/list`、`tools/call` | 否 | 无 |
| 本机 Harness → 本机其他进程 MCP | `tools/list`、`tools/call` | 否 | 无 |
| 本机 Harness → 局域网普通 MCP 工具提供者 | 自动握手、`tools/list`、`tools/call` | 否 | 无 |
| 局域网远程 Harness → 本机 Harness | 提交、接管或改变任务 | 是 | 本机，即被调用 Harness 端 |
| 本机 Harness → 局域网远程 Harness | 提交远程任务 | 是 | 对方机器，即被调用 Harness 端 |
| 已批准远程 Harness 会话 → 被调用 Harness | 批准范围内继续执行和调用工具 | 否 | 沿用会话授权 |
| 远程 Harness 扩大任务范围、权限或有效期 | 变更授权 | 是 | 被调用 Harness 端重新审批 |

因此，普通 MCP 工具提供者不实现用户审批 UI；只有声明 `serviceRole=harness-controller`、能够接受远程任务的 Harness 才实现远程入口审批。

以下动作用户无感、无需审批：

- 发现本机或局域网节点。
- 自动目录握手。
- `initialize/ping/tools/list`。
- 能力摘要和健康状态更新。
- 节点上线、离线和工具增删。
- 本机 Harness 调用本 APP、本机其他进程或局域网普通 MCP 工具。
- Harness 按任务计划连续调用多个工具。

只有以下动作需要本机用户审批：

- 其他机器上的智能体/Harness 主动向本机 Harness 提交远程任务。
- 其他机器要求接管、暂停、取消或改变本机 Harness 当前任务。
- 远程来源申请扩大已经批准的任务范围或有效期。

远程入口审批展示来源 Harness 身份、机器、任务目标、允许范围和有效期。用户可以批准本次任务、批准限时会话或拒绝，并能随时撤销。批准后本机 Harness 在批准范围内自动调用自己的三层 MCP 能力池，不再逐工具弹窗。

本机用户直接给本机 Harness 下达的任务已经构成任务授权。Harness 仍需遵守工具 Schema、目标边界、幂等和禁止事项，但不增加重复确认窗口。

## 9. 多节点协同任务

主 Harness 保存任务图：

```text
parentTaskId
  ├─ subtask-A → 本APP工具
  ├─ subtask-B → 本机APP-2
  └─ subtask-C → 局域网设备-3
```

每个子任务记录目标节点、工具版本、输入摘要、远程入口授权来源（如有）、taskId、进度、结果和证据。可独立的任务并行；具有依赖、共享设备或写冲突的任务串行。

远端长任务使用：

- `collaboration.task_start`
- `collaboration.task_status`
- `collaboration.task_cancel`

节点离线时不得盲目重复启动；恢复后先查询原 `taskId`。只有确认原任务未发生且工具幂等时才能重新路由。

## 10. UI 信息架构

Harness 增加“能力网络”入口，默认显示三个实时列表和独立计数：

```text
能力网络  [本APP 154] [本机 23] [局域网 61]
```

每个列表支持按 APP、机器、领域、状态和风险筛选。节点行展示：

- APP 和机器名称
- 在线/离线/目录连接中
- 工具数量和最近更新时间
- 延迟、负载和协议版本
- 当前是否允许调用

默认不展示公钥、Token、内部连接文件或完整网络握手信息。工具发生增删时列表自动变化，不提供必须由用户点击的“刷新”按钮；可以有只读的“重新探测”诊断动作。

## 11. 对其他 APP 的新广播要求

其他 APP 广播必须增加自动目录握手字段：

```json
{
  "protocol": "lmcp-discovery",
  "protocolVersion": "2.0",
  "messageType": "announce",
  "instanceId": "future-app-01",
  "app": {
    "id": "com.example.future-app",
    "name": "Future App",
    "version": "1.0.0"
  },
  "catalogEndpoint": {
    "transport": "https-streamable-http",
    "port": 9443,
    "path": "/mcp/catalog",
    "instanceKeyFingerprint": "sha256:..."
  },
  "callEndpoint": {
    "transport": "https-streamable-http",
    "port": 9443,
    "path": "/mcp",
    "serviceRole": "tool-provider"
  },
  "mcp": {
    "protocolVersions": ["2025-06-18"],
    "catalogVersion": 128,
    "capabilityDigest": "sha256:...",
    "changeNotifications": true
  },
  "ttlSeconds": 12,
  "sentAt": "2026-08-30T06:00:00Z"
}
```

`serviceRole=tool-provider` 表示供 Harness 自动调用，不做逐工具审批。若一个 APP 对外暴露的是 Harness 远程任务入口，必须声明 `serviceRole=harness-controller`，并在接受远程任务前完成本机用户的任务/会话授权。两种角色不能混淆。

## 12. 安全边界

- 自动连接允许本机 Harness 调用普通 MCP 工具，但不允许远程智能体无审批控制本机 Harness。
- 广播不能携带 Token、Secret、任务内容或业务数据。
- 目录握手使用短时加密会话和挑战应答，防止被动窃听和简单冒充。
- 首次出现的任何节点只进入目录能力池。
- 实例密钥变化、协议降级或能力摘要异常时自动降为 `stale`。
- 不扫描端口，不调用未广播服务，不读取无关进程。
- 目录响应有大小、数量、Schema深度和速率限制。
- 同名 APP、同名工具和相同 IP 都不能合并身份。

## 13. 分阶段实施

### 阶段 A：三列表和实时目录

- 本 APP 目录快照与事件。
- 本机 MCP 注册/进程监听。
- LMCP 2.0 局域网公告。
- 自动目录握手和 `tools/list`。
- 三列表 UI 和统一能力图。

### 阶段 B：远程 Harness 入口授权和自动路由

- 工具风险归一化。
- 本机 Harness 自动调用工具。
- 远程 Harness 任务/会话入口审批。
- Harness 候选评分和执行计划。
- 本机/远端标准 `tools/call`。

### 阶段 C：多节点长任务协同

- start/status/cancel。
- 子任务图、并行和依赖。
- 节点离线恢复、证据汇总和审计。

## 14. 新完成定义

只有以下项目全部通过，才能称为“VibeKits 启动后自动使用本机和局域网 MCP”：

1. 启动后自动出现本 APP、本机、局域网三个独立列表。
2. 不输入 IP、不手工配对、不点刷新也能发现和读取目录。
3. 本机程序和局域网设备上线/离线会自动增删。
4. 工具变化按 catalogVersion 实时更新。
5. 发现、目录和本机 Harness 工具调用不会弹授权窗口。
6. 远程 Harness 提交任务时在被调用端审批，拒绝后不启动任务。
7. Harness 能按实际能力将任务路由到正确节点。
8. 多节点结果保留来源，失败不冒充成功。
9. 长任务可等待、取消和恢复查询，不重复启动。
10. 两台真实电脑加一个本机外部 MCP 进程完成联合验收。

## 15. 与旧文档的关系

本文取代旧设计中“用户先手工配对才能读取列表”和“每个工具由执行端逐项审批”的部分。保留标准 MCP 工具 Schema、广播不含秘密、远程 Harness 入口审批、长任务协议和结果来源审计。

下一步应先实现三层实时目录和自动目录握手，再实现工具调用路由；不能继续用静态发现列表冒充统一能力网络。
