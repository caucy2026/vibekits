# RustDesk × Vibekits 可选集成合同

日期：2026-08-28  
状态：交给 RustDesk 与 Vibekits 两端共同实现  
关联架构：`38_HARNESS_RUSTDESK_P2P_STATUS_ARCHITECTURE.md`

## 1. 一句话原则

RustDesk 和 Vibekits 都必须能独立安装、启动、升级、运行和卸载。集成是可选增强功能，不是任何一方的启动依赖、网络依赖或权限依赖。

```text
没有 Vibekits：RustDesk 原有远控/文件/终端功能全部正常；“Vibekits”显示未连接。
没有兼容 RustDesk：Vibekits 的 Harness/工具/本地日志全部正常；“远程状态”显示不可用。
连接中断：双方原有任务继续，仅状态面板进入离线/过期状态。
```

## 2. 责任边界

### Vibekits 负责

- 从官方 Harness 生命周期和 Vibekits 工具桥生成多工作区、会话、任务状态；
- 对状态脱敏、限长、编号并保存本机最新快照；
- 提供只读本机 IPC 服务；
- 接受 RustDesk 的能力探测、订阅、取消订阅和重新同步请求；
- 不连接远端 RustDesk，不实现 P2P、打洞、中继、远端身份认证或远控权限。

### 本机 RustDesk 负责

- 可选探测 Vibekits 本机 IPC；
- 校验本机 IPC 服务身份和协议版本；
- 在已有远端会话认证成功且远端显式订阅后，读取并转发脱敏状态；
- 保持视频、输入、文件、终端、剪贴板和音频优先；状态拥塞时丢弃旧状态，不得反压远控；
- Vibekits 不存在、不兼容或异常时完全保持原有行为。

### 远端 RustDesk 负责

- 在 UI 中提供独立“Vibekits”入口；
- 只有本机 Host 宣告能力后才允许订阅；
- 展示连接状态、任务列表、最后更新时间和过期提示；
- 不通过状态通道执行工具、自动批准、读取提示词或获取模型正文。

### hbbs/hbbr 负责

- 继续执行 RustDesk 原有注册、打洞和中继；
- 不解析、不保存、不索引 Vibekits 状态；
- 不需要知道本机是否安装 Vibekits。

## 3. 工作流程

### 3.1 本机 RustDesk 启动

```text
RustDesk 启动
  ├─ 原有远控服务立即启动（永远不等待 Vibekits）
  └─ 后台探测 Vibekits IPC，首次超时 300 ms
       ├─ 不存在/拒绝/超时 → capability=false，记录一次有界诊断
       ├─ 版本不兼容       → capability=false，reason=incompatible
       └─ 握手成功         → capability=true，缓存 30 秒，不主动订阅状态
```

探测失败不能弹阻塞窗口、不能退出 RustDesk、不能重启服务、不能改变设备 ID、密码、网络配置或在线状态。

### 3.2 Vibekits 启动

```text
Vibekits 启动
  ├─ Harness/UI/工具立即可用（永远不等待 RustDesk）
  ├─ 启动本机只读状态 IPC
  └─ 后台检测 RustDesk 兼容性
       ├─ 未安装/未运行 → 远程状态=未连接
       ├─ 已运行但不支持协议 → 远程状态=版本不兼容
       └─ 已连接 → 远程状态=等待远端订阅
```

RustDesk 探测或连接失败只影响“远程状态”图标，不影响 Harness 启动时间、模型请求、工具调用和本地状态日志。

### 3.3 远端连接与订阅

```text
远端 RustDesk 会话认证成功
  ↓
Host 发送 capability: vibekits_harness_status_v1 = true/false
  ↓
远端用户点击“Vibekits”
  ├─ capability=false → 显示“未连接”，提供原因，不重试风暴
  └─ capability=true  → 发送 HarnessStatusSubscribe
                          ↓
                    Host 订阅本机 IPC
                          ↓
                    返回完整状态快照
                          ↓
             状态改变立即发送；忙碌 2s/空闲 15s 心跳
```

远端关闭面板或远程会话结束时必须取消订阅；本机 IPC 可继续存在，但不能继续向不存在的 peer 排队。

## 4. 远端 UI 状态

远端“Vibekits”入口始终可见，但不得误导：

| 状态 | 文案 | 操作 |
| --- | --- | --- |
| `notInstalled` | 未连接：本机未发现 Vibekits | 可关闭；不显示“安装失败” |
| `notRunning` | 未连接：Vibekits 未运行 | 允许低频刷新 |
| `unsupported` | 未连接：本机 Vibekits 不支持状态共享 | 建议更新 Vibekits |
| `rustdeskUnsupported` | 当前 RustDesk 版本不支持 Vibekits 状态 | 建议更新 RustDesk |
| `permissionDenied` | 未授权查看智能体状态 | 不反复申请权限 |
| `connecting` | 正在连接 Vibekits… | 3 秒内必须结束 |
| `connectedIdle` | 已连接，Harness 当前空闲 | 显示最后心跳 |
| `connectedBusy` | 已连接，N 个任务运行中 | 显示项目/会话/阶段 |
| `stale` | 状态可能已过期 | 保留最后快照并标灰 |
| `disconnected` | Vibekits 连接已断开 | 原有远控继续工作 |

远端点击入口不得触发本机启动 Vibekits、下载软件、修改服务、提升权限或自动批准 Harness 操作。

## 5. 本机发现与 IPC 合同

### 5.1 端点

- Windows：`\\.\pipe\vibekits-harness-status-v1-<user-sid-hash>`；
- macOS/Linux：当前用户运行目录中的 `vibekits-harness-status-v1.sock`，权限 `0600`；
- 禁止监听 `0.0.0.0`、局域网 IP 或固定 TCP 端口；
- RustDesk 只在本机连接，不从 hbbs/hbbr 查询 IPC 地址。

### 5.2 握手

RustDesk 请求：

```json
{
  "type": "hello",
  "protocol": "vibekits.harness.status",
  "versions": [1],
  "client": "rustdesk",
  "nonce": "random-base64",
  "maxFrameBytes": 32768
}
```

Vibekits 响应：

```json
{
  "type": "helloAck",
  "selectedVersion": 1,
  "publisher": "vibekits",
  "publisherVersion": "<current-vibekits-version>",
  "instanceId": "ephemeral-uuid",
  "capabilities": ["snapshot", "subscribe", "heartbeat", "resync"],
  "nonce": "same-random-base64",
  "maxFrameBytes": 32768
}
```

规则：

- nonce 不一致、版本无交集、帧超限或 JSON/CBOR 无效时立即关闭本次连接；
- 连接失败使用 1/2/5/15 秒退避，稳定后最高每 15 秒探测一次；
- 同一时刻最多一个探测和一个活跃订阅，不允许并发重连风暴；
- IPC 身份校验失败只产生脱敏诊断，不能降级为无鉴权 TCP。

### 5.3 本机 IPC 消息

| 消息 | 方向 | 说明 |
| --- | --- | --- |
| `hello/helloAck` | 双向 | 能力与版本协商 |
| `getSnapshot` | RustDesk → Vibekits | 请求当前全部任务快照 |
| `subscribe` | RustDesk → Vibekits | 从指定 sequence 开始订阅 |
| `snapshot` | Vibekits → RustDesk | 完整或增量状态 |
| `heartbeat` | Vibekits → RustDesk | 轻量存活与最新 sequence |
| `resync` | RustDesk → Vibekits | sequence 断档时重取完整快照 |
| `unsubscribe` | RustDesk → Vibekits | 释放订阅 |
| `error` | 双向 | 有界错误码，不含异常堆栈和秘密 |

RustDesk 无权通过该 IPC 写提示词、调用工具、修改配置、批准操作或读取 Harness 日志正文。

## 6. P2P 能力协商

RustDesk Host 在远端认证完成后提供：

```json
{
  "vibekits_harness_status": {
    "available": true,
    "protocolVersion": 1,
    "reason": ""
  }
}
```

`available=false` 是正常状态，不是远程连接错误。旧 Host 没有该字段时，远端按 `rustdeskUnsupported` 处理，不能不断发送未知消息。

状态数据使用专用 protobuf 消息 `HarnessStatusSubscribe/Snapshot/Ack`，不得复用聊天消息、剪贴板、文件传输、RawMessage 或屏幕 OCR。

## 7. 双向失败隔离

### RustDesk 必须保证

- Vibekits 未安装、未运行、损坏、升级中、IPC 卡死、协议错误或频繁重启时，RustDesk 首帧、在线注册、远控、文件传输和退出均不等待它；
- IPC 读取在独立异步任务中，取消订阅可立即结束；
- 状态消息优先级低于视频、输入、音频、剪贴板和文件传输；
- RustDesk 升级/卸载不删除 Vibekits 数据。

### Vibekits 必须保证

- RustDesk 未安装、未运行、版本过旧、配置损坏、IPC 拒绝或远端断线时，Harness、OCR、ADB、串口、SSH、清理和其他工具全部正常；
- 状态发布使用有界队列和 latest-wins，RustDesk 慢或不读时不能阻塞状态生产者；
- RustDesk 升级/卸载不删除 Harness 会话和本地日志；
- 关闭远程分享只停止 IPC 订阅，不停止 Harness 任务。

## 8. 隐私与权限

- 默认发送：公开阶段、脱敏项目/会话标签、工具 ID/名称、脱敏目标、进度、时间和结果状态；
- 禁止发送：提示词、逐字思维链、模型回复正文、文件内容、完整路径、命令完整参数、API Key、Token、密码、Cookie、Authorization 和私钥；
- RustDesk 会话增加独立只读权限 `view_harness_status`，不得沿用文件传输或剪贴板权限；
- “等待批准”只能提示远端用户回到真实 Vibekits 界面，状态协议本身没有批准接口。

## 9. 兼容和升级

- 协议使用整数版本，双方选择交集中的最高版本；无交集则 `unsupported`；
- 新字段必须可忽略，旧客户端收到未知字段仍能显示基本阶段；
- 新消息类型不得改变旧 RustDesk P2P 消息编号；旧端忽略未知 oneof；
- Vibekits 与 RustDesk 可单独回滚，回滚只使状态入口不可用，不影响两边原功能；
- RustDesk UI 不根据 Vibekits 版本字符串猜能力，只相信握手和 capability。

## 10. RustDesk 实现清单

1. 新增后台 `VibekitsStatusAdapter`，异步发现/握手/订阅本机 IPC；
2. 在 `message.proto` 增加专用状态订阅、快照和 ACK；
3. Host 认证完成后发布 capability，不存在 Vibekits 时发布 `available=false`；
4. Desktop/Web 增加“Vibekits”入口和第 4 节状态页面；
5. 慢客户端采用 latest-wins，状态通道独立限流；
6. 会话断开时取消本机订阅并释放任务；
7. 不修改 hbbs/hbbr 业务模型，不把状态上传 HBBC；
8. 增加下列自动测试和两机真测。

## 11. 联合验收矩阵

| 编号 | 场景 | 必须结果 |
| --- | --- | --- |
| OR-01 | 只安装 RustDesk | 原有功能正常；Vibekits 显示“未连接” |
| OR-02 | 只安装 Vibekits | Harness/工具正常；远程状态显示“未连接” |
| OR-03 | RustDesk 运行后启动 Vibekits | 不重启 RustDesk，15 秒内能力变为可用 |
| OR-04 | Vibekits 运行后启动 RustDesk | 不重启 Vibekits，3 秒内握手完成 |
| OR-05 | 工作中关闭 Vibekits | 远端状态转断开；远控不断线 |
| OR-06 | 远控中关闭 RustDesk | Harness 继续；本地状态和日志不丢 |
| OR-07 | 两端协议不兼容 | 显示版本不兼容；双方原功能正常 |
| OR-08 | IPC 持续不响应 | 300 ms 探测超时；无 UI 卡顿和重试风暴 |
| OR-09 | P2P 直连 | 状态变化 P95 小于 2 秒 |
| OR-10 | hbbr 中继 | 状态可达；hbbr 不解析状态内容 |
| OR-11 | 远端不订阅 | Host 不读取/转发连续状态流 |
| OR-12 | 10 个并行 Harness 任务 | 分项目显示；无状态串线和无界队列 |
| OR-13 | 状态中包含模拟 Key/密码/路径 | 远端与抓包均无敏感原文 |
| OR-14 | 远端状态面板卡死 | 视频、输入、文件传输和本机 Harness 正常 |
| OR-15 | 双方分别升级与回滚 | 最坏仅状态不可用，原功能不回归 |

只有 OR-01～OR-15 自动测试通过，并完成 Windows 两机直连和 hbbr 中继真测，才能标记集成完成。
