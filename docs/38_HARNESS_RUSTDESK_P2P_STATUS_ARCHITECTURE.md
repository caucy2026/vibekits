# Harness × RustDesk P2P 实时状态架构

日期：2026-08-28  
RustDesk 源码基线：`caucy2026/rust-desk` `main@08a5ed713a305b8438e88c8a709edfdfaa48ab16`

## 1. 目标

远端控制设备在已认证的 RustDesk 会话中，实时看到本机所有 Harness 工作区/会话/任务的公开执行状态：启动、排队、规划、推理、等待批准、工具执行、生成答复、成功、失败、取消与停止。状态只描述进度，不发送提示词、逐字思维链、模型正文、文件内容、凭据或完整路径。

RustDesk 未运行、远端未连接或网络断开时，Harness 必须照常工作；状态通道永远不能成为任务、UI 或 RustDesk 远控的前置依赖。

## 2. 已确认的现状

- Vibekits 已有 `HarnessWorkStatusHub`，但它只有进程级“最后一条状态”，不能表达多个工作区、会话和并行任务。
- RustDesk 仓库已有 HBBC `presence/heartbeat`：60 秒在线续租、150 秒失效；它统计设备在线数，不承载业务任务状态。
- RustDesk `rendezvous.proto` 的注册/打洞心跳服务于 hbbs 信令；`hbbr` 是加密会话中继，不是任意 JSON 状态服务器。
- RustDesk 客户端已有本机 IPC、Flutter 全局事件流、P2P `message.proto` 和会话消息分发，可扩展独立的 Harness 状态消息，不能复用聊天文本伪装协议。

## 3. 总体数据流

```text
官方 DSH 生命周期/公开步骤       Vibekits 工具桥
            │                       │
            └──────┬────────────────┘
                   ▼
       HarnessTaskStateRegistry（多任务状态机）
                   │ 立即事件 + 忙碌 2s/空闲 15s 心跳
                   ▼
     本机安全 IPC（Windows Named Pipe / Unix Domain Socket）
                   │ 同用户 ACL、版本握手、订阅、长度上限
                   ▼
        RustDesk Host 状态适配器（仅本机读取）
                   │ 已认证会话内 HarnessStatusSnapshot
                   ▼
       RustDesk P2P 加密通道（直连或 hbbr 原样中继）
                   ▼
      远端 RustDesk Desktop/Web “智能体状态”面板
```

HBBC 在线心跳继续独立运行，仅表示设备在线。Harness 状态不写入 HBBC，不要求修改 hbbs/hbbr 数据库。

## 4. 多项目状态机

状态主键为 `workspaceRef + sessionRef + taskId`。`workspaceRef/sessionRef` 是安装内生成的不可逆公开引用，默认不传真实路径；显示名称经过长度限制和凭据脱敏。

```text
dormant → starting → ready → queued → planning → reasoning
                                            ├→ waitingApproval
                                            ├→ invokingTool → toolRunning ┐
                                            └─────────────────────────────┤
                                                                          ▼
                                                            synthesizing → completed
                                                                          ├→ failed
                                                                          ├→ canceled
                                                                          └→ stopped
网络状态是旁路：connected ↔ stale ↔ disconnected，不改变任务阶段。
```

规则：

1. 每次合法转换递增单调 `sequence`；终态不能回到运行态，同一会话的新请求创建新 `taskId`。
2. 工具阶段必须含公开 `toolId/toolName`、脱敏目标、开始时间和成功/失败状态；不含完整参数和结果正文。
3. “推理中”只表示官方 DSH 公开生命周期，不传输私有逐字思维链。
4. Registry 同时维护逐任务状态与设备聚合：运行任务数、等待批准数、失败数、最近更新时间。
5. APP 重启后先发布 `starting`；旧的非终态任务恢复为 `interrupted`，不能伪装仍在运行。

建议快照字段：

```json
{
  "schema": "vibekits.harness.status/v1",
  "deviceRef": "opaque-device-ref",
  "workspaceRef": "opaque-workspace-ref",
  "workspaceLabel": "vibekits",
  "sessionRef": "opaque-session-ref",
  "taskId": "uuid",
  "sequence": 42,
  "phase": "toolRunning",
  "message": "正在读取 Git 远端文件",
  "toolId": "vibekits.git.read_remote_file",
  "target": "HiV730/manifest.git",
  "progress": {"current": 1, "total": 1, "unit": "tool"},
  "startedAt": "2026-08-28T08:00:00Z",
  "updatedAt": "2026-08-28T08:00:05Z"
}
```

单个快照上限 4 KiB，设备聚合包上限 32 KiB；超限只保留最新状态和计数。

## 5. 本机 IPC

- Windows：`\\.\pipe\vibekits-harness-status-v1-<user-sid-hash>`；macOS/Linux：用户运行目录下权限 `0600` 的 Unix Domain Socket。
- Vibekits 是服务端，RustDesk Host 是只读订阅端。RustDesk 不允许通过此通道执行工具、批准操作或读取日志正文。
- 握手包含协议版本、进程随机 nonce、能力位和最大帧长；帧采用长度前缀 JSON/CBOR，禁止换行流和无限帧。
- Windows 校验连接进程 SID 与签名/可执行路径；Unix 校验 peer UID。不得开放 TCP 监听端口。
- RustDesk 晚启动时主动连接；Vibekits 晚启动时 RustDesk 以 1/2/5/15 秒退避重连，最高保持 15 秒，不忙等。

## 6. RustDesk P2P 协议

在客户端和服务端共用的 `message.proto` `Misc` oneof 中增加独立消息，不占用 `ChatMessage`、`RawMessage` 或 hbbs 注册心跳：

```proto
message HarnessStatusSubscribe {
  uint32 protocol_version = 1;
  uint64 after_sequence = 2;
}
message HarnessStatusSnapshot {
  uint32 protocol_version = 1;
  uint64 sequence = 2;
  bytes payload = 3;
  bool heartbeat = 4;
}
message HarnessStatusAck {
  uint64 sequence = 1;
}
```

- 远端在认证和权限确认后显式订阅；未订阅不发送。
- 状态变化立即发送；运行中无变化每 2 秒发送轻量心跳，空闲每 15 秒一次。
- 每个 peer 只保留一个在途包；慢客户端合并为最新快照，禁止排队拖慢视频、键盘和文件传输。
- sequence 断档时远端请求完整快照；状态不是可靠审计日志，审计仍保存在本机 Harness 日志中。
- 直连失败时可由 hbbr 原样中继端到端加密消息；hbbr 不解析、不索引、不长期保存状态。

## 7. 远端界面

RustDesk Desktop/Web 增加独立“智能体状态”抽屉：

- 顶部显示设备连接状态和最后心跳时间；
- 按工作区分组，列出会话、当前阶段、工具和耗时；
- 等待批准只提示“本机等待批准”，远端批准必须继续走现有 RustDesk 控制画面与 Vibekits 权限界面；
- 断线超过 3 个心跳周期显示“状态可能过期”，不得继续转圈；
- 默认不展示路径、提示词和输出，用户在本机设置中可完全关闭状态分享。

## 8. 失败隔离与隐私

1. IPC、P2P、HBBC 三条链路分别熔断；任一失败不影响 Harness 和远控。
2. 状态发布采用有界广播和 latest-wins，绝不反压 DSH 或工具线程。
3. API Key、Token、密码、Authorization、URL 查询、文件正文和完整命令禁止进入状态包。
4. 本机日志记录状态序号、阶段、发送结果和耗时，不记录 P2P 密钥或远端凭据。
5. 远端订阅需要当前 RustDesk 会话已认证，并增加独立只读权限 `view_harness_status`。

## 9. 实施顺序与验收

### P0：Vibekits 状态源

- 将单值 `HarnessWorkStatusHub` 升级为多任务 Registry；兼容现有 UI 的 `latest` 投影。
- 接入 DSH 启动/就绪/公开规划和推理阶段、审批、工具、生成答复及终态。
- 单元测试非法转换、并行任务、重启中断、脱敏、上限和节流。

### P1：RustDesk 本机桥

- 两仓共享 `vibekits.harness.status/v1` 协议夹具。
- 真机验证 RustDesk 先启动、Vibekits 先启动、双方重启、IPC 拒绝异用户进程。

### P2：P2P 与远端面板

- proto、Host 转发、Desktop/Web 订阅与渲染同时发布，旧客户端忽略未知字段。
- 验证直连、hbbr 中继、断网恢复、慢客户端、10 个并行任务和 24 小时运行。

### 通过标准

- 状态变化到远端 P95 小于 2 秒；空闲心跳不超过 15 秒。
- 断开状态通道后 Harness、视频、键盘、文件传输无可感知变化。
- 抓包和服务端日志中不存在提示词、模型正文、凭据、完整路径；hbbs/hbbr 无需理解 Harness 消息。

RustDesk 端可直接执行的可选依赖、发现握手、UI 状态和联合验收合同见 `39_RUSTDESK_VIBEKITS_OPTIONAL_INTEGRATION_CONTRACT.md`。
