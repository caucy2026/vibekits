# KEMI远程办公 × Vibekits 智能体状态集成需求

日期：2026-08-29
状态：交付 KEMI/RustDesk 团队进行技术设计
需求方：Vibekits
关联文档：

- `38_HARNESS_RUSTDESK_P2P_STATUS_ARCHITECTURE.md`
- `39_RUSTDESK_VIBEKITS_OPTIONAL_INTEGRATION_CONTRACT.md`

## 1. 目标

在已经通过认证的 KEMI远程办公会话中，为远端用户提供一个独立、只读的“Vibekits 智能体状态”页面，实时查看本机 Harness 的公开执行状态，包括任务数量、执行阶段、工具、脱敏目标、进度、结果和最后更新时间。

本功能只共享状态，不共享任务内容。KEMI远程办公与 Vibekits 必须始终能够独立安装、启动、升级、运行和卸载；任一方缺失、异常、版本不兼容或连接中断时，不得影响另一方原有功能。

## 2. 必须遵守的连接方向

本机连接采用以下固定角色：

```text
Vibekits
  └─ 启动只读本机 IPC 服务（服务端）
           ↑
           └─ 本机 KEMI/RustDesk Host 主动探测、连接和订阅（客户端）
                         ↓
                 已认证 RustDesk P2P 会话
                         ↓
                 远端 Desktop/Web 状态页面
```

约束：

1. Vibekits 不主动连接远端 KEMI/RustDesk，不登录 hbbs/hbbr，不实现打洞、中继和远端身份认证。
2. KEMI/RustDesk Host 只连接同机、同用户的 Vibekits IPC，不从 hbbs/hbbr 查询 IPC 地址。
3. 远端用户完成会话认证并显式打开“Vibekits”页面后，Host 才能订阅连续状态。
4. 未订阅时只允许低频能力探测，不允许持续读取、转发或排队状态。

## 3. 双方责任

### 3.1 Vibekits 负责

1. 从官方 Harness 生命周期和工具桥生成多工作区、多会话、多任务状态。
2. 对所有输出执行脱敏、限长、编号、合并和速率控制。
3. 保存本机最新快照，并提供只读本机 IPC 服务。
4. 接受能力探测、握手、获取快照、订阅、重同步和取消订阅。
5. 校验 IPC 对端的同用户身份，并在 Windows 上支持进一步校验 KEMI/RustDesk 可执行文件身份。
6. RustDesk 不存在或异常时保持 Harness、OCR、ADB、串口、SSH、清理和其他工具正常。

### 3.2 KEMI/RustDesk 本机 Host 负责

1. 新增独立后台组件 `VibekitsStatusAdapter`。
2. 异步发现 Vibekits IPC，完成版本、nonce、身份和帧上限校验。
3. 只在远端会话已认证、具有独立权限且远端显式订阅后读取状态。
4. 把状态装入专用 P2P protobuf 消息，通过现有端到端加密会话发送。
5. 保证状态消息优先级低于视频、输入、音频、剪贴板、文件和终端。
6. 慢客户端采用 latest-wins，丢弃旧状态，不得反压 Vibekits 或远控主链。
7. Vibekits 缺失、卡死、升级、损坏或频繁重启时，保持 KEMI/RustDesk 原有行为。

### 3.3 KEMI/RustDesk 远端负责

1. Desktop/Web 增加独立“Vibekits”入口和状态页面。
2. 只有 Host 宣告能力后才允许发起订阅。
3. 显示连接状态、任务分组、执行阶段、工具、进度、结果和最后更新时间。
4. 页面关闭或远程会话结束时立即取消订阅。
5. 不通过状态协议执行工具、发送提示词、修改配置或批准操作。

### 3.4 hbbs/hbbr 责任边界

1. 继续承担原有注册、打洞和加密会话中继。
2. 不解析、不索引、不长期保存 Vibekits 状态。
3. 不增加 Vibekits 专用数据库或业务 API。
4. 不需要知道设备是否安装 Vibekits。

## 4. 本机 IPC 要求

### 4.1 端点

- Windows：`\\.\pipe\vibekits-harness-status-v1-<user-sid-hash>`。
- macOS/Linux：当前用户运行目录中的 `vibekits-harness-status-v1.sock`，权限 `0600`。
- 禁止使用 `0.0.0.0`、局域网地址、固定 TCP 端口或可被其他用户连接的端点。

### 4.2 连接与重试

1. KEMI/RustDesk 首次探测必须在 300 ms 内结束。
2. 失败后按 1/2/5/15 秒退避，稳定后最多每 15 秒探测一次。
3. 同一时刻最多一个探测连接和一个活跃订阅。
4. 不允许阻塞启动、弹出错误窗口、忙等或形成重连风暴。
5. Vibekits 晚启动时，KEMI/RustDesk 无需重启即可在 15 秒内发现。
6. KEMI/RustDesk 晚启动时，应在 3 秒内完成首次握手。

### 4.3 帧协议

1. 使用长度前缀 JSON 或 CBOR，不使用换行分隔流。
2. 单帧默认上限 32 KiB，双方握手协商后取较小值。
3. 单任务状态建议不超过 4 KiB；完整设备快照不得超过协商上限。
4. 帧超限、格式无效、版本无交集或 nonce 不一致时立即关闭本次连接。
5. 错误响应只包含固定错误码和脱敏说明，不发送异常堆栈。

## 5. 握手合同

KEMI/RustDesk 请求：

```json
{
  "type": "hello",
  "protocol": "vibekits.harness.status",
  "versions": [1],
  "client": "kemi-rustdesk",
  "peerId": "non-empty-ephemeral-peer-id",
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
  "publisherVersion": "<current-version>",
  "instanceId": "ephemeral-uuid",
  "capabilities": ["snapshot", "subscribe", "heartbeat", "resync"],
  "nonce": "same-random-base64",
  "maxFrameBytes": 32768
}
```

必须校验：

1. `type`、`protocol`、`versions`、`client`、`peerId`、`nonce` 和帧上限。
2. `peerId` 必须非空、有长度上限并满足约定字符集。
3. nonce 必须随机且原样回传；nonce 只防串线和旧响应，不单独作为身份认证。
4. Windows 校验 Named Pipe 对端用户 SID；macOS/Linux 校验 peer UID。
5. 身份校验失败不得降级到无鉴权 TCP。
6. 握手成功只表示协议建立；收到同一 `peerId` 和版本的第一条有效心跳后，UI 才能显示绿色“已连接”。

## 6. 本机 IPC 消息

| 消息 | 方向 | 说明 |
| --- | --- | --- |
| `hello/helloAck` | 双向 | 身份、版本和能力协商 |
| `getSnapshot` | KEMI → Vibekits | 请求完整最新快照 |
| `subscribe` | KEMI → Vibekits | 从指定全局序号开始订阅 |
| `snapshot` | Vibekits → KEMI | 完整或增量状态 |
| `heartbeat` | Vibekits → KEMI | 存活、全局序号和当前节奏 |
| `resync` | KEMI → Vibekits | 序号断档后重新获取完整快照 |
| `unsubscribe` | KEMI → Vibekits | 释放订阅 |
| `error` | 双向 | 固定、有界、脱敏错误 |

KEMI/RustDesk 无权通过本机 IPC 写提示词、执行工具、修改设置、批准操作或读取 Harness 日志正文。

## 7. 状态模型和顺序

### 7.1 标识

- `deviceRef`：安装内生成的不可逆设备引用。
- `workspaceRef`：不可逆工作区引用，不发送真实路径。
- `sessionRef`：不可逆会话引用。
- `taskId`：每次请求生成的新 UUID。
- `streamSequence`：设备状态流的全局单调序号，用于 ACK、断档和重同步。
- `taskRevision`：单个任务的单调修订号，用于拒绝旧任务状态覆盖新状态。

不得让多个任务分别使用相同的 P2P `sequence`。P2P ACK 和重同步必须以 `streamSequence` 为准。

### 7.2 阶段

```text
starting → ready → queued → planning → reasoning
                                  ├→ waitingApproval
                                  ├→ invokingTool → toolRunning
                                  └→ synthesizing
                                         ├→ completed
                                         ├→ failed
                                         ├→ canceled
                                         └→ stopped
```

终态不能返回运行态。APP 重启后，旧的非终态任务必须变为 `interrupted`，不能继续显示为运行中。

### 7.3 建议快照

```json
{
  "schema": "vibekits.harness.status/v1",
  "deviceRef": "opaque-device-ref",
  "workspaceRef": "opaque-workspace-ref",
  "workspaceLabel": "工作区",
  "sessionRef": "opaque-session-ref",
  "taskId": "uuid",
  "streamSequence": 42,
  "taskRevision": 5,
  "phase": "toolRunning",
  "message": "正在读取远端文件",
  "toolId": "vibekits.git.read_remote_file",
  "toolName": "读取远端文件",
  "target": "远端仓库文件",
  "progress": {"current": 1, "total": 1, "unit": "tool"},
  "startedAt": "2026-08-29T01:00:00Z",
  "updatedAt": "2026-08-29T01:00:05Z"
}
```

## 8. 允许和禁止传输的数据

### 8.1 默认允许

- 匿名设备、工作区和会话引用；
- 经过脱敏的显示标签；
- 任务 ID、全局序号和任务修订号；
- 公开阶段、工具 ID/名称；
- 泛化后的目标类型；
- 进度、时间、成功/失败/取消/停止状态；
- 不含业务数据的轻量心跳。

### 8.2 默认禁止

- 用户提示词和模型回复正文；
- 私有逐字思维链；
- 文件内容和完整文件路径；
- 完整命令及其参数；
- 原始 URL、查询参数、片段和用户信息；
- 项目、客户、产品或仓库的敏感真实名称；
- API Key、Token、密码、Cookie、Authorization、私钥；
- 系统环境变量、异常堆栈和 Harness 日志正文。

目标摘要默认只发送类型，例如“远端仓库文件”“Android 设备”“本地文档”。即使只保留 basename，也不能自动认定安全。任何更具体的显示名必须由 Vibekits 脱敏策略明确允许。

## 9. P2P 协议要求

KEMI/RustDesk 应在共用 `message.proto` 的可扩展 `oneof` 中增加独立消息，字段编号必须使用尚未占用的新编号：

```proto
message HarnessStatusSubscribe {
  uint32 protocol_version = 1;
  uint64 after_stream_sequence = 2;
}

message HarnessStatusSnapshot {
  uint32 protocol_version = 1;
  uint64 stream_sequence = 2;
  bytes payload = 3;
  bool heartbeat = 4;
}

message HarnessStatusAck {
  uint64 stream_sequence = 1;
}
```

禁止复用 `ChatMessage`、剪贴板、文件传输、`RawMessage`、屏幕 OCR 或 HBBC 在线心跳。

要求：

1. 状态改变立即发送。
2. 运行中无变化时每 2 秒发送心跳；空闲时每 15 秒发送心跳。
3. 心跳明确携带本次建议间隔，接收端过期阈值不得固定为 6 秒。
4. 建议过期阈值为 `max(6 秒, 3 × 当前心跳间隔)`。
5. 每个远端 peer 最多保留一个在途快照，慢客户端直接合并为最新状态。
6. 序号断档时请求完整快照；状态流不是审计日志，不要求重放全部历史。
7. 旧客户端必须忽略未知消息和未知字段，不得影响原有远控。

## 10. 能力与权限

Host 在远端会话认证完成后发布：

```json
{
  "vibekits_harness_status": {
    "available": true,
    "protocolVersion": 1,
    "reason": ""
  }
}
```

要求：

1. 增加独立只读权限 `view_harness_status`。
2. 不得沿用文件、剪贴板、终端或远控权限代替该权限。
3. `available=false` 是正常能力状态，不是远程会话故障。
4. UI 只相信握手和 capability，不根据版本字符串猜测能力。
5. “等待批准”只显示提示；状态协议不存在批准接口。

## 11. 远端 UI

远端页面至少支持：

- 未安装、未运行、不兼容、未授权、连接中；
- 已连接空闲、已连接运行中；
- 状态过期、状态通道断开；
- 按工作区和会话分组任务；
- 当前阶段、工具、进度、耗时和最后更新时间；
- 明确说明页面只读。

连接中状态必须在 3 秒内结束。远端点击入口不得触发本机安装、启动 Vibekits、提升权限或自动批准操作。

## 12. 失败隔离和性能

1. IPC、P2P 状态流和 HBBC 在线链路分别熔断。
2. 任一状态组件异常不得影响 Harness、视频、键盘、鼠标、音频、文件、终端和剪贴板。
3. 状态生产和发送使用有界内存，latest-wins，不允许无界队列。
4. 状态变化到远端 P95 小于 2 秒。
5. IPC 持续不响应时，单次探测 300 ms 内结束。
6. 支持至少 10 个并行 Harness 任务且不串状态。
7. 远端状态页面卡死时，主远控会话仍正常。

## 13. KEMI/RustDesk 团队设计交付物

请对方方案设计至少包含：

1. `VibekitsStatusAdapter` 所在模块、线程/异步模型和生命周期。
2. Windows Named Pipe 与 Unix Domain Socket 的实现和身份校验方法。
3. 握手、帧编解码、限长、超时、退避和取消机制。
4. `message.proto` 精确字段编号及新旧端兼容策略。
5. Host capability 和 `view_harness_status` 权限接入点。
6. Desktop/Web 状态页面的数据流和状态机。
7. P2P 直连与 hbbr 中继下的数据路径，证明服务端不解析状态。
8. latest-wins、ACK、断档重同步和内存上限设计。
9. 威胁模型：异用户进程、伪造服务、重放、超长帧、恶意字段、慢读端和日志泄密。
10. 自动测试、两机直连测试、hbbr 中继测试、升级和回滚计划。

方案中需要明确列出需要 Vibekits 配合确认的接口或字段，不得默认为 Vibekits 会主动连接远端。

## 14. 联合验收

| 编号 | 场景 | 必须结果 |
| --- | --- | --- |
| OR-01 | 只安装 KEMI/RustDesk | 原有功能正常，Vibekits 能力为不可用 |
| OR-02 | 只安装 Vibekits | Harness/工具正常，远程状态为未连接 |
| OR-03 | KEMI 先启动，随后启动 Vibekits | 不重启 KEMI，15 秒内发现能力 |
| OR-04 | Vibekits 先启动，随后启动 KEMI | 不重启 Vibekits，3 秒内完成握手 |
| OR-05 | 握手后尚未收到心跳 | 不得显示绿色已连接 |
| OR-06 | 空 `peerId`、错误 nonce 或版本不兼容 | 拒绝连接且双方原功能正常 |
| OR-07 | 工作中关闭 Vibekits | 远端状态断开，远控不断线 |
| OR-08 | 远控中关闭 KEMI/RustDesk | Harness 继续，本机状态和日志不丢 |
| OR-09 | IPC 持续不响应 | 300 ms 探测超时，无 UI 卡顿和重试风暴 |
| OR-10 | P2P 直连 | 状态变化 P95 小于 2 秒 |
| OR-11 | hbbr 中继 | 状态可达，hbbr 不解析和保存状态 |
| OR-12 | 远端未打开状态页 | Host 不订阅和转发连续状态 |
| OR-13 | 10 个并行 Harness 任务 | 不串任务、序号和 ACK |
| OR-14 | 模拟提示词、Key、密码、路径和 URL | 远端、抓包和服务端日志无敏感原文 |
| OR-15 | 远端状态页卡死或慢读 | 视频、输入、文件等主功能正常 |
| OR-16 | 忙碌 2 秒与空闲 15 秒心跳 | 均不误报过期，断线后按动态阈值过期 |
| OR-17 | sequence 断档 | 请求完整快照，不重放无界历史 |
| OR-18 | 双方分别升级和回滚 | 最坏仅状态能力不可用，原功能不回归 |

只有自动测试通过，并完成 Windows 两机 P2P 直连和 hbbr 中继真测，才能宣称集成完成。

## 15. 当前 Vibekits 实现边界

截至本文日期，Vibekits 已有：

- KEMI/RustDesk 客户端发现、启动、`--get-id` 和网页地址推导；
- 远程分享入口和连接状态颜色；
- 协议名、版本、peer 和心跳状态机的单元测试骨架。

尚未完成：

- 多任务状态 Registry；
- Windows Named Pipe/Unix Domain Socket 服务；
- 完整握手和对端身份校验；
- 订阅、完整快照、增量快照、ACK 和重同步；
- 与 KEMI/RustDesk Host 的真实接线；
- 两机 P2P 与 hbbr 中继联合验收。

因此，双方应先评审本需求和对方技术设计，再分别实现，不能把当前状态图标视为已经完成通信。
