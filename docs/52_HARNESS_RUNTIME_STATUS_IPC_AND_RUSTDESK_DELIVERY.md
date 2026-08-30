# Harness 实时状态 IPC 与 RustDesk 远端交付要求

状态：实施中
协议：`vibekits.harness.status` version 1
调用方向：本机 RustDesk 订阅本机 Vibekits；RustDesk 再转发给控制本机的远端会话
安全属性：只读、可选、可丢弃、失败隔离

## 1. 交付目标

本机 Vibekits 工作时，正在通过 RustDesk 控制本机的远端用户可以实时看到 Harness 的公开工作状态：

```text
Vibekits Harness lifecycle / tool bridge
  -> 多任务状态 registry（脱敏、限长、latest-wins）
  -> 本机只读 IPC publisher
  -> 本机 RustDesk Host status adapter
  -> 已认证 RustDesk P2P/direct 或 hbbr relay 会话
  -> 远端 RustDesk “Harness 状态”只读面板
```

状态链路异常不得影响 Harness、ADB、RustDesk 视频、输入、音频、文件、终端或剪贴板。

## 2. 与 ADB 隧道的关系

两套能力必须使用独立模块、IPC 消息和权限：

| 能力 | 方向 | 数据性质 | 权限 |
| --- | --- | --- | --- |
| ADB service tunnel | 本机 Vibekits 控制远端电脑的 ADB server | 双向原始 TCP，高权限 | `enable-tunnel` / 后续专用 remote ADB 权限 |
| Harness status | 本机 Vibekits 把公开状态发给控制本机的远端 | 单向只读、低优先级状态 | `view_harness_status` |

Harness 状态协议没有工具调用、审批、提示词、命令执行或配置修改接口，不能复用 ADB lease，也不能通过状态消息承载任意字节。

## 3. Vibekits 状态源

状态 registry 支持多个 workspace、session 和并行 task。主键：

```text
workspaceRef + sessionRef + taskId
```

要求：

1. `workspaceRef/sessionRef/deviceRef` 是安装内生成的不可逆公开引用，不发送真实路径。
2. 每次 registry 改变递增全局 `streamSequence`；每个任务单独递增 `taskRevision`。
3. 终态不能返回运行态；应用重启后旧非终态任务标记为 `interrupted`。
4. 保持现有 `HarnessWorkStatusHub.latest/changes/publish` API 兼容，同时提供完整 registry snapshot。
5. 至少支持 10 个并行任务；完整快照超限时保留聚合计数和最新任务，不形成无界历史。

公开 phase：

```text
idle, starting, ready, queued, planning, reasoning,
waitingApproval, invokingTool, toolRunning, synthesizing,
completed, failed, canceled, stopped, interrupted
```

快照示例：

```json
{
  "schema": "vibekits.harness.status/v1",
  "streamSequence": 42,
  "generatedAt": "2026-08-30T03:00:00Z",
  "aggregate": {
    "taskCount": 3,
    "busyCount": 1,
    "waitingApprovalCount": 0,
    "failedCount": 1
  },
  "tasks": [
    {
      "deviceRef": "opaque-device-ref",
      "workspaceRef": "opaque-workspace-ref",
      "workspaceLabel": "工作区",
      "sessionRef": "opaque-session-ref",
      "taskId": "uuid",
      "taskRevision": 5,
      "phase": "toolRunning",
      "message": "正在读取远端文件",
      "toolId": "vibekits.git.read_remote_file",
      "toolName": "读取远端文件",
      "target": "远端仓库文件",
      "startedAt": "2026-08-30T02:59:50Z",
      "updatedAt": "2026-08-30T02:59:58Z"
    }
  ]
}
```

## 4. 本机 IPC 角色与端点

Vibekits 是只读 publisher/server；RustDesk Host 是 subscriber/client。

- macOS/Linux：`${Directory.systemTemp.path}/vkh/v1.sock`；父目录 `vkh` 为 `0700`、socket 为 `0600`。短后缀是强制契约，用于满足 macOS `sockaddr_un.sun_path` 的约 104 字节上限。
- Windows：`\\.\pipe\vibekits-harness-status-v1-<user-sid-hash>`，DACL 只允许当前用户 SID。
- 禁止使用 TCP、局域网地址、`0.0.0.0` 或公开固定端口作为降级方案。
- 平台无法提供安全 transport 时返回 unavailable；Harness 继续工作。

RustDesk 先启动时以 1/2/5/15 秒有界退避发现 IPC；Vibekits 先启动时 RustDesk 3 秒内完成第一次握手。首次探测超时 300 ms，同一时刻最多一个探测和一个活跃订阅。

## 5. 帧格式

传输使用：

```text
4-byte unsigned big-endian payload length
UTF-8 JSON payload
```

- 默认/最大帧 32768 bytes，握手后取双方较小值。
- 长度为 0、超过上限、UTF-8/JSON 无效、对象类型错误时返回有界错误并关闭。
- 不使用换行分隔 JSON；不反序列化任意 Dart/Rust 对象。

## 6. 握手

RustDesk 请求：

```json
{
  "type": "hello",
  "protocol": "vibekits.harness.status",
  "versions": [1],
  "client": "kemi-rustdesk",
  "peerId": "local-host-session-ref",
  "nonce": "random-base64",
  "maxFrameBytes": 32768
}
```

Vibekits 响应：

```json
{
  "type": "helloAck",
  "protocol": "vibekits.harness.status",
  "selectedVersion": 1,
  "publisher": "vibekits",
  "publisherVersion": "1.9.0-dev.137",
  "instanceId": "ephemeral-uuid",
  "capabilities": ["snapshot", "subscribe", "heartbeat", "resync"],
  "nonce": "same-random-base64",
  "maxFrameBytes": 32768
}
```

校验失败立即关闭。nonce 防响应串线，不代替 OS IPC 身份校验。握手成功不等于远端 P2P 已订阅；Vibekits 本地 UI 只有在收到 RustDesk 的有效 heartbeat/订阅确认后才显示 connected。

## 7. IPC 消息

### 获取完整快照

```json
{"type":"getSnapshot","afterStreamSequence":0}
```

响应：

```json
{"type":"snapshot","full":true,"streamSequence":42,"payload":{}}
```

### 订阅

```json
{"type":"subscribe","afterStreamSequence":42}
```

Vibekits 首先发送完整快照，随后状态变化立即发送。每个 subscriber 只保留一个待发送最新快照；慢读时覆盖旧包。

### 心跳

忙碌状态无变化时每 2 秒，空闲状态无变化时每 15 秒：

```json
{
  "type":"heartbeat",
  "protocolVersion":1,
  "peerId":"local-host-session-ref",
  "streamSequence":42,
  "suggestedIntervalMs":15000,
  "busy":false
}
```

过期阈值：`max(6000 ms, 3 × suggestedIntervalMs)`，不能固定为 6 秒。

### 重同步与取消

```json
{"type":"resync","afterStreamSequence":35}
{"type":"unsubscribe"}
```

### 错误

```json
{"type":"error","code":"invalid_frame","message":"Invalid status frame"}
```

允许错误码：`invalid_frame`、`frame_too_large`、`invalid_handshake`、`unsupported_version`、`unauthorized_peer`、`not_subscribed`、`internal_error`。不得发送堆栈、路径或凭据。

## 8. RustDesk P2P 消息

RustDesk 在共享 `message.proto` 的可扩展 oneof 中增加专用消息，使用未占用字段编号：

双方在 2026-08-30 联调时确认 `Misc` 顶层 oneof 字段号固定预留为：
`33 HarnessStatusCapability`、`34 HarnessStatusSubscribe`、
`35 HarnessStatusSnapshot`、`36 HarnessStatusAck`。后续不得复用或改号。

```proto
message HarnessStatusCapability {
  uint32 protocol_version = 1;
  bool available = 2;
  string reason = 3;
}

message HarnessStatusSubscribe {
  uint32 protocol_version = 1;
  uint64 after_stream_sequence = 2;
}

message HarnessStatusSnapshot {
  uint32 protocol_version = 1;
  uint64 stream_sequence = 2;
  bytes payload = 3;
  bool heartbeat = 4;
  uint32 suggested_interval_ms = 5;
}

message HarnessStatusAck {
  uint64 stream_sequence = 1;
}
```

不得复用 `ChatMessage`、剪贴板、文件、`RawMessage`、HBBC presence 或 ADB tunnel。旧版本忽略未知消息，不影响桌面控制。

## 9. RustDesk 必须实现

1. Host 侧 `VibekitsStatusAdapter`，独立异步任务发现、握手和订阅 IPC。
2. 只有存在至少一个已认证 Remote 控制会话、远端有 `view_harness_status` 权限且远端显式订阅时，才持续读取/转发状态。
3. Host 认证后发送 capability；Vibekits 不存在时 `available=false` 是正常状态。
4. P2P 状态消息低于视频、输入、音频、文件等优先级，latest-wins；慢端不能反压主链。
5. 每个远端 peer 独立订阅/ACK/过期状态；会话断开或面板关闭时取消订阅。
6. Desktop/Web 增加只读 Harness 面板，显示 unavailable/connecting/idle/busy/stale/disconnected、聚合计数、任务、阶段、工具和最后更新时间。
7. 远端 UI 明确标注只读；waitingApproval 只提示回到本机 Vibekits，不提供批准按钮。
8. hbbs/hbbr 不解析、不保存、不索引状态，不增加业务数据库。

## 10. 隐私

允许：公开 phase、匿名引用、泛化标签、工具 ID/名称、泛化目标、进度、时间、结果状态。

禁止：提示词、逐字思维链、模型回复正文、文件内容、完整路径、完整命令参数、原始 URL、API Key、Token、密码、Cookie、Authorization、私钥、环境变量、异常堆栈和运行日志正文。

Vibekits 在进入 registry 前脱敏，IPC server 在编码前再次限长；RustDesk 不应尝试恢复或补全被移除的信息。

## 10.1 Vibekits 已交付的本机 Publisher API

Vibekits 生产启动代码按以下方式接入 registry；IPC 启动失败仅返回
`available=false`，不得阻止应用启动：

```dart
final publisher = HarnessStatusIpcPublisher(
  snapshotProvider: () => HarnessWorkStatusHub.registryLatest.toJson(),
  snapshotStream: () => HarnessWorkStatusHub.registryChanges.map(
    (snapshot) => snapshot.toJson(),
  ),
  publisherVersion: '1.9.0-dev.137',
  observer: onHarnessStatusIpcEvent,
);
final result = await publisher.start();
```

`observer` 提供 `handshakeSucceeded/subscriptionStarted/heartbeatSent/
unsubscribed/disconnected`。握手成功只代表本机 IPC 协商完成，不能单独把
远端状态标为绿色；订阅建立和后续心跳才可更新实时连接状态。应用退出时调用
`publisher.stop()`。

当前 macOS/Linux transport 已实现真实 UDS、同 UID 校验、`0700/0600`
权限和固定路径。Windows 安全 Named Pipe transport 尚未交付，默认明确返回
unavailable，并保留可注入原生 transport 接口；禁止临时降级为 TCP。

## 11. 自动验收

### Vibekits

- 多任务/并行任务、全局 sequence、task revision、非法转换、interrupted 恢复。
- 凭据、URL、路径和命令脱敏；快照/帧大小上限。
- hello nonce/version/max frame；getSnapshot/subscribe/resync/unsubscribe。
- 忙 2 秒/空闲 15 秒心跳及动态 stale TTL。
- 慢 subscriber latest-wins，断开不阻塞 Harness。
- Unix socket 权限与重启；Windows named pipe adapter unavailable 时 fail-closed。

### RustDesk

- IPC 缺失/超时/无效帧/错误 nonce/错误 UID/SID/版本不兼容。
- capability 与独立 `view_harness_status` 权限。
- 未认证、未订阅、无权限时不转发。
- P2P 直连和 hbbr 中继、慢客户端、sequence 断档/resync。
- 远端面板 freshness、动态 TTL、断线清理。
- 状态链路故障时视频、输入和文件传输无回归。

## 12. 本机与两机验收顺序

1. Vibekits registry、协议 codec、IPC server 单元测试。
2. Vibekits 本机运行并验证 socket/pipe 生命周期；没有 RustDesk 时 Harness 正常。
3. RustDesk 本机 adapter 与真实 IPC 握手，读取完整快照和心跳。
4. 建立远端 RustDesk 控制会话，打开 Harness 面板后才订阅。
5. 执行 Harness 工具，远端 2 秒内看到 phase/tool/泛化目标变化。
6. 关闭面板、断开远控、关闭 Vibekits、制造慢读和 sequence 断档。
7. Windows 两机 P2P 直连与 hbbr 中继通过后，才能宣称完整集成。
