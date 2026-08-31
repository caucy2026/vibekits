# VibeKits × KEMI传书 LMCP/2 联调记录

日期：2026-08-30
状态：LMCP/2 双向代码与 Release 已交付；VibeKits → KEMI 只读调用已闭环；单次文件落盘与 KEMI → VibeKits 真机调用等待两端 UI 解锁后完成

## 1. 现场根因

同一局域网生产组播 `239.255.42.99:47831` 的 10 秒抓包同时收到：

- VibeKits `192.168.3.58`：567 字节，`protocolVersion=1.0`，`endpoint.transport=ssh-stdio`。
- KEMI传书 `192.168.3.65`：1189 字节，`protocolVersion=2.0`，使用 `catalogEndpoint/callEndpoint`、`https-streamable-http` 和 `9443/mcp`。

因此失败不是组播、网卡、端口或 macOS 权限问题。旧 VibeKits 只读取 LMCP/1 `endpoint` 并强制 `ssh-stdio`；KEMI传书只接收 LMCP/2，双方在解析阶段主动丢弃对方。旧 VibeKits 还错误地依赖公告中的 `mcp.tools`，而 LMCP/2 公告只携带摘要，真实目录必须在 HTTPS 会话中读取。

## 2. VibeKits 本次修复

- 发现接收器同时解析 LMCP/1 与 LMCP/2，未知主版本继续拒绝。
- LMCP/2 端点要求源 IP 为 RFC1918 私网地址，`catalogEndpoint/callEndpoint` 的端口、路径、证书指纹、目录版本和能力摘要必须一致。
- HTTPS 客户端在发送 HTTP 数据前固定实际服务端证书 DER 的 SHA-256，不使用无条件跳过证书校验的生产路径。
- 完整执行 `initialize → notifications/initialized → tools/list`，支持分页、重复游标防护、响应大小上限和规范化目录摘要校验。
- 只有通过认证并进入当前目录的工具才能执行 `tools/call`；结果再次核对 `instanceId`、工具名和 `catalogRevision`。
- LMCP/2 工具目录自动进入三层能力目录；公告摘要、端点或证书变化会重新读取，离线会清理缓存。
- 组播监听和发送改为枚举全部 RFC1918 IPv4 网卡并逐接口加入/发送，同时保留同机 loopback 和共享端口。

## 3. 真实调用证据

VibeKits 新客户端连接运行中的 KEMI传书 2.0.5/构建 96：

1. 证书指纹与公告 `sha256:1a8d...c7c3` 一致。
2. `initialize` 协商为 MCP `2025-06-18`。
3. `tools/list` 返回 `kemi.device.status` 和 `kemi.devices.list`，完整目录 SHA-256 与公告一致。
4. `tools/call(kemi.device.status,{})` 成功，返回 `instanceId=org.kemi.send:E16497473C`、`catalogRevision=2`、`isError=false`。
5. KEMI传书状态先返回 `lmcpPeerCount=1`，证明其兼容接收器已经看到远端 VibeKits 旧公告。

## 4. 本机 Release 双向发现证据

启动本次编译的 `build/macos/Build/Products/Release/Vibekits.app` 后，VibeKits 与 KEMI传书同时成功共享 `UDP *:47831`。生产组播 10 秒实抓到三个唯一实例：

| 源地址 | 实例 | 协议 | 字节 | 传输 |
|---|---|---:|---:|---|
| `192.168.3.65` | `com.vibekits.desktop:F27FFED178` | LMCP/1.0 | 575 | `ssh-stdio` |
| `192.168.3.65` | `org.kemi.send:E16497473C` | LMCP/2.0 | 1189 | `https-streamable-http` |
| `192.168.3.58` | `com.vibekits.desktop:824F9994A8` | LMCP/1.0 | 567 | `ssh-stdio` |

KEMI传书随后通过真实 `kemi.device.status` 返回 `lmcpPeerCount=2`，说明它同时保留了本机 Mac 与远端 Windows 两台 VibeKits。VibeKits Release 界面的局域网 MCP 角标同样为 `2`；独立生产组播测试确认其中 KEMI 节点已自动完成证书固定、目录加载和只读工具调用。因此“双方在局域网互相发现”已通过，不再是仅靠模拟报文的结论。

## 5. 迁移边界

VibeKits 当前仍只对外广播真实存在的 LMCP/1 `ssh-stdio` 能力。它尚无可对局域网安全暴露的持久实例证书和 HTTPS MCP Server，因此本次没有伪造 LMCP/2 `callEndpoint`。KEMI传书在滚动升级期兼容显示 LMCP/1 节点，但不能把旧 `ssh-stdio` 节点当作 HTTPS 工具调用。

后续要实现双向 LMCP/2 工具调用，VibeKits 还必须交付：持久实例密钥、HTTPS `/mcp` 服务、服务端 `initialize/tools/list/tools/call`、开关排空状态机、证书轮换和跨平台安全存储。完成这些之前，只能宣称“VibeKits 可安全调用 KEMI传书”，不能宣称“KEMI传书可调用 VibeKits”。

## 2026-08-30 第二轮：从“能看到”改为“像本机工具一样调用”

首轮只证明 VibeKits 底层客户端能够调用 KEMI，尚未把远端路由注册进 Harness。因此模型可以在界面看到 `kemi.device.status`，却没有正式工具把任务送入 `McpCapabilityDirectory.invokeLanTool`。本轮新增：

- `vibekits.mcp.catalog_list`：返回本 APP、本机、局域网三层完整实时目录，包含实例、可调用状态、真实工具名、用途和完整 `inputSchema`。
- `vibekits.mcp.tool_call`：按 `instanceId + toolName + arguments` 调用当前认证目录中的局域网工具；离线、旧 LMCP/1、目录缺失、指纹或摘要不一致均拒绝。
- `mcp.tool_call` 进入 Harness 统一审批和审计，审批菜单展示目标实例、工具和参数；不能静默回退成本机 shell。
- 右侧工具轨新增“本 APP MCP”入口，完整列出 VibeKits 自己公开的工具；设备列表明确区分“可调用”和“仅发现”。
- MCP 从关闭切到打开时先弹出权限申请，列出全部本 APP 工具以及局域网发现、读取、写入、文件外发和设备控制风险；取消时保持关闭。

KEMI 首轮生产目录仅有 `kemi.device.status` 和 `kemi.devices.list`，所以“能列设备”不等于“能发文件”。文件发送必须作为显式 `kemi.files.send`（以及长任务的 status/cancel）进入真实 `tools/list`，参数和风险遵循 [LMCP/2 标准第 5.4 节](50_LMCP_APP_DEVICE_IDENTITY_AND_SWITCH_STANDARD.md#54-文件发送是完整工具不是设备列表的隐含动作)。在 KEMI 返回该目录并完成真机接收闭环前，不宣称 MCP 已能发送文件。

KEMI build97 随后已把 `kemi.files.send` 加入 catalogRevision 3；VibeKits 生产客户端真实读取到三个工具并向 Windows KEMI-E668 发起 164 字节测试文件调用。该次调用进入真实发送链路，但接收端在客户端等待边界内未返回许可或拒绝，build97 又没有持久化最后一次结构化传输审计，故不能证明文件落盘，也不能给出接收路径或接收端哈希。此结果按失败门槛记录，不能写成“发送成功”。暴露出的修复要求是：VibeKits 将目录/调用超时拆为 8 秒/120 秒；KEMI 服务端必须在 110 秒内返回结构化终态、清理发送锁，并公开脱敏 status 接口。完成修复后才重新执行一次、且只执行一次真机发送。

### build98 超时与审计修复验收

KEMI 2.0.5+98 已升级为 catalogRevision 4，真实 VibeKits 客户端完成 TLS 指纹固定、目录摘要校验并读取以下完整目录：

| 工具 | 风险与用途 |
|---|---|
| `kemi.device.status` | 只读设备/运行状态 |
| `kemi.devices.list` | 只读在线接收目标和稳定 targetDeviceId |
| `kemi.files.last_status` | 只读最近一次脱敏传输状态；活动态 `final=false`、终态 `final=true`，终态只保留一条/7天 |
| `kemi.files.send` | 高风险文件外发；绝对普通文件、目标在线、16 MiB 上限、接收端仍可拒绝 |

VibeKits 对 `kemi.files.last_status` 的真实 `tools/call` 返回 `isError=false`、`catalogRevision=4`、`retentionSeconds=604800`、`available=false`，并明确列出永不返回 `sourcePath/fileContent/transferToken/remoteSessionId/receiverSavePath`。`available=false` 是正确结果：build97 的历史调用不可恢复且本轮按要求没有重发，不能伪造完成记录。

build98 的 `kemi.files.send` 在 110 秒内必须完成、拒绝或返回 `TARGET_RESPONSE_TIMEOUT`；超时会取消准备/上传任务、关闭会话、释放发送锁并保存脱敏终态。KEMI 完整测试 88/88、analyze 0、Universal Release 和深度签名通过；VibeKits 端目录/授权/路由定向测试与 Release 构建通过。文件真实落盘成功仍需要接收端在 110 秒窗口内明确接受后再做一次新的单次验收；build97 那次不能计入成功。

## 2026-08-30 第三轮：VibeKits 成为可被远端调用的 LMCP/2 服务

VibeKits 已补齐此前第 5 节列出的服务端缺口。开启 MCP 前必须由用户在界面确认证书身份、完整工具清单和风险；新安装与无法解析的偏好都保持关闭。确认后启动生产 HTTPS `/mcp`，支持 MCP `2025-06-18` 的 `initialize`、分页 `tools/list` 和 `tools/call`。远端调用复用 `VibekitsHarnessToolBridge.invoke`，因此参数 schema、风险审批和 `HarnessToolActivityStore` 审计与本机 Harness 相同。关闭时先发 `goodbye`，停止接受新调用，最多排空 5 秒并关闭 HTTPS。

实例身份使用持久 EC P-256 自签名证书，公告的是证书 DER SHA-256；私钥和证书只写系统 Credential Manager/Keychain/Keystore。有效身份重载后指纹保持不变；半写入、空值、损坏或不匹配的凭据不会让 MCP 永久损坏，而是在保持暴露关闭的前提下重建一组完整身份。

生产服务优先绑定 TCP 9443。由于本机 KEMI 已使用 9443，VibeKits 仅在明确检测到端口占用时回退到 OS 动态端口，并在 `catalogEndpoint` 与 `callEndpoint` 中广播同一个真实端口；路径仍固定 `/mcp`，证书指纹、协议版本、catalogRevision 和 capabilityDigest 三处严格一致。KEMI 的严格解析器接受 `1..65535` 的公告端口，不要求第三方服务固定 9443。

跨机器收不到 VibeKits 公告的一个生产根因已经复现并修复：最坏 LMCP/2 announce 曾达到 1207 字节，被 1200 字节发送门禁静默丢弃。现在 catalogRevision 使用短的单调构建号，并按最终 UTF-8 报文长度安全缩短 display host，同时保留 `APP@host-hardwareCode`，所有正式公告强制 `<=1200` 字节。发现端逐张 RFC1918 IPv4 网卡加入 `239.255.42.99:47831`，发送端也逐接口设置 multicast interface，IP hops 固定 1；同机多个 APP 通过端口复用共同监听。

自动化证据：LMCP 五文件套件 19/19，通过共享 47831 的跨 VibeKits 实例发现、真实 TLS 指纹固定、完整分页目录、只读调用、写入审批、端口占用回退、goodbye 和多网卡筛选；`flutter analyze --no-pub lib test` 为 0 问题，`git diff --check` 通过。最终 macOS Universal Release 为 `build/macos/Build/Products/Release/Vibekits.app`，深度 ad-hoc 签名验证通过；可执行文件 SHA-256 `ad559e91d063e199bb882d4173d0016f6b82428edc948b525341199d1ff70129`，App.framework SHA-256 `fc5e5d19d25eb221a936d3c66ab6f1df81f9eaedf0ef16e57de35c92a8e127cf`。

尚未伪造为成功的两项真机门禁：

1. Mac 当前锁屏，尚未在最终 Release 的真实风险菜单中点击允许，因此运行态仅验证 VibeKits 共享监听 UDP 47831、默认未开放 TCP MCP；解锁后必须确认动态 HTTPS 端口、KEMI 反向 tools/list 和一次 `vibekits.calculator.programmer` 调用。
2. build98 新文件样本已创建但保持 HOLD。只有 Windows KEMI-E668 接收窗口置前并明确 READY 后，VibeKits 才通过最新目录调用一次 `kemi.files.send`；必须取得 structuredContent/isError、transfer/trace 标识、接收保存路径、大小和两端一致 SHA-256 后才能标记成功，禁止自动重试。
