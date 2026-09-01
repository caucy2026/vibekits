# LMCP/2 APP 设备身份、MCP 开关与远程等价调用标准

版本：2.4
状态：VibeKits、KEMI传书和第三方 APP 唯一可执行互通规范
目标：另一台机器只需完整实现本文，即可让 VibeKits 与对端双向发现、固定实例证书、读取目录，并像调用本机工具一样互相调用。

本文中的 MUST/“必须”是上线门禁。LMCP/1 只保留接收兼容：显示为“仅发现、不可调用”；新版本不得把 `ssh-stdio` 伪装成 LMCP/2，也不得再正式发送 LMCP/1 公告。

### 一文交付规则

把第三方 APP 交给另一个开发团队时，**只交付本文，也只以本文验收**。本文是自包含合同，不要求接入方再组合阅读仓库中的能力目录、历史协议或联调记录。对方必须同时完成以下四层，不得只做“发现”或只复制一段 UDP JSON：

1. 身份与开关：稳定 `instanceId`、持久证书、风险确认和可撤销状态机；
2. 跨机发现：按本文固定参数在每张私网网卡上发送/接收 LMCP/2，并完成 Windows Private 防火墙规则；
3. 真实调用：HTTPS `/mcp`、TLS 指纹固定、`initialize → tools/list → tools/call`、目录摘要和错误语义；
4. 可理解工具：每个工具提供用途、完整 Schema、风险、成功结果、错误码和真实双机验收状态；
5. 工程闭环：Harness 能按当前目录自行选工具、组合调用、跟踪长任务、验证物理结果、恢复中断并输出可审计证据，而不是只把一次 HTTP 成功当作任务完成。

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

VibeKits 当前实现的 `catalogRevision` 是单调构建号 `2138`，APP 版本为 `1.9.0`。后续任何工具名称、描述、风险、annotations 或 JSON Schema 变化都必须提升构建号并重新计算摘要。

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

打开 MCP 是一次明确的“向局域网发布能力并按所选范围接受自动调用”授权。确认页必须让用户选择允许的调用方范围、工具/风险上限、文件或设备作用域以及撤销方法；未在授权范围内的工具不得出现在可调用目录。授权一旦确认并持久化，范围内的只读、写入、文件外发、设备控制和 Harness 自动化调用都必须直接执行并返回结果，禁止每次 `tools/call` 再弹“允许/拒绝”。首次确认承担风险告知，后续由审计、撤销和范围变更保护用户，而不是用重复弹窗破坏无人值守自动化。

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
6. 每次发送 announce 前必须确认 HTTPS listener 仍在运行；listener 异常退出时立即停止 announce、尝试发送 goodbye 并进入 `ERROR`。禁止 TCP 端点已经关闭却持续广播“在线”。
6. 关闭后 `tools/call` 必须拒绝新请求，不能只隐藏 UI。
7. 在途调用最多等待配置的排空时间，然后返回结构化取消结果。
8. 接口服务崩溃时开关显示异常/关闭，不得继续广播在线。

### 3.1 持久自动调用授权（禁止逐次重复审批）

用户在 MCP 确认页选择“允许远程调用”后，APP 必须持久化一个自动调用授权，至少包含：提供者 `instanceId` 和证书指纹、允许的调用方（指定 instanceId 列表或明确的“当前私网内所有已认证 LMCP/2 调用方”）、工具名/工具组、最高风险等级、文件根目录或目标设备等作用域、创建时间和用户可见的撤销入口。默认有效期是“直到用户关闭 MCP 或主动撤销”，不能在每次任务、APP 重启、调用方重连或新 Harness 会话时失效。

对落在该授权范围内的调用，服务端必须：立即校验 Schema 和幂等键 → 自动执行 → 返回结构化结果或 taskId → 允许调用方自动轮询/取消/恢复；不得出现第二次权限弹窗、不得等待人工点击、不得因无人值守而返回 `DENIED`/审批超时。`readOnly`、`writesData`、`controlsDevice` 和 `serviceRole=harness-controller` 都遵守这一原则；风险级别决定首次授权页展示内容和可选范围，不决定是否每次再问。

只有以下事件允许把调用变回“需要用户重新授权”：提供者实例证书指纹变化；调用方超出原授权身份范围；新工具或现有工具的风险/数据/设备作用域扩大；用户关闭 MCP、撤销授权或降低风险上限；操作系统自身权限已撤销。单纯 APP 重启、网络重连、catalogRevision 递增但能力未扩权、相同幂等任务重试、status/last_result 恢复都不得重新询问。发生扩权时只暂停新增范围，原授权范围仍可自动运行。

### 3.2 运行中调用提示（不是第二次审批）

所有远程 `tools/call` 必须采用与远程桌面连接状态相同的“首次建立信任、
后续持续可见、随时可以终止”交互：

1. 首次连接或首次申请某个工具/风险/资源作用域时显示正式授权页。授权页必须
   显示调用方 APP、设备显示名、`instanceId`、证书指纹、工具、参数作用域、
   风险、有效期、审计和撤销方法。用户确认后持久化授权；取消则返回
   `AUTH_SCOPE_REQUIRED`，不得执行副作用。
2. 命中持久授权的后续调用立即自动执行，不再等待“允许/拒绝”。调用开始时
   必须在被调用 APP 内显示非模态运行提示，默认至少可见 3 秒；短任务完成后可
   自动收起，长任务必须持续显示到完成、失败或取消。提示不得阻塞 MCP 响应或
   Harness 自动化。
3. 提示至少显示“调用方设备/APP、工具名称、开始时间、当前状态”，并提供两个
   可访问按钮：`调用信息` 展开脱敏参数摘要、作用域、traceId/taskId、进度和
   审计入口；`强制关闭` 立即停止接受该调用的后续工作、触发协作取消、关闭其
   网络/文件/设备会话并返回 `USER_TERMINATED`。按钮不能只是关闭提示窗口。
4. 强制关闭菜单必须允许用户进一步选择“仅终止本次”“撤销该工具授权”或
   “撤销/拉黑该调用方”。撤销后下一次调用立即返回 `AUTH_SCOPE_REQUIRED`；
   黑名单命中返回 `CALLER_BLOCKED`。终止、撤销和失败均写入脱敏审计。
5. 工具实现必须接受取消信号，并在安全边界检查取消；文件发送还必须取消准备、
   上传和接收会话、释放文件锁且保留可查询终态。无法安全中断的原子动作要在
   `tools/list` 明确说明 `cancelBehavior`，但仍须阻止后续步骤。
6. 同一调用方的并发提示可合并成一个状态卡，但每条调用必须有独立 traceId、
   详情和终止动作。应用切到后台时仍应提供系统通知或托盘状态；不得静默执行。

调用提示是透明告知而非审批。实现若在每次调用时再次弹出需要人工点击的确认框，
即使工具最终成功，也按自动化不合格处理。

### 3.3 调用方身份与授权绑定

服务端不能仅凭“来源 IP 位于 RFC1918”授予持久权限。每个 MCP 会话必须携带可由
TLS/签名材料验证的调用方 `instanceId`、APP 身份和实例证书指纹；授权主键至少为
`callerInstanceId + callerFingerprint + providerInstanceId + tool/scope`。来源 IP
只用于局域网边界检查，不是身份。身份缺失或验签失败返回 `CALLER_IDENTITY_REQUIRED`
或 `CALLER_IDENTITY_INVALID`，不能降级为匿名高风险调用。证书轮换必须重新授权。

具体传输可以使用双向 TLS，或在已固定服务端 TLS 的 HTTPS 请求上使用标准化的
调用方证书/签名头；无论采用哪种方式，调用方私钥不得进入 UDP、参数、日志或
业务响应。`initialize` 成功后服务端应返回当前识别的调用方身份摘要，调用方必须
核对，防止授权串用。

本标准当前固定使用“服务端 TLS + 每请求 ECDSA 调用方签名”，禁止各 APP 自定义
不兼容头。所有 POST `/mcp` 请求必须携带：

| HTTP Header | 值 |
|---|---|
| `LMCP-Caller-Instance-Id` | 调用方稳定 `instanceId` |
| `LMCP-Caller-App-Id` | 调用方 `app.id`，必须是 instanceId 前缀 |
| `LMCP-Caller-Certificate` | 调用方 P-256 实例证书 DER 的 base64，不含换行 |
| `LMCP-Caller-Fingerprint` | 上述 DER 的 `sha256:` 小写十六进制 |
| `LMCP-Caller-Timestamp` | UTC Unix 毫秒整数 |
| `LMCP-Caller-Nonce` | 16–32 随机字节的无填充 base64url；5 分钟内不得重复 |
| `LMCP-Caller-Signature` | 对下列 canonical bytes 做 ECDSA-SHA256，DER 签名 base64 |

签名输入精确为 UTF-8，字段间只用 `\n`，末尾没有换行：

```text
LMCP/2
POST
/mcp
<callerInstanceId>
<timestamp>
<nonce>
sha256:<HTTP body 原始字节的小写 SHA-256>
```

服务端必须在解析 JSON 和执行工具前完成：请求体哈希、证书 DER 指纹、P-256
ECDSA 签名、instanceId/appId 关系、时间偏差不超过 120 秒、nonce 防重放。失败
使用 HTTP 401 和结构化 `CALLER_IDENTITY_INVALID`；缺头使用
`CALLER_IDENTITY_REQUIRED`；重放使用 `CALLER_REPLAYED`。目录读取也必须签名，
但可在正式授权前完成，以便授权页显示完整工具；`tools/call` 必须命中持久授权。
调用方证书与服务端证书可来自同一个安全的实例证书存储，但各 APP 私钥永不共享。

### 3.4 MCP 调用方连接与权限面板（参考远程桌面）

被调用 APP 必须提供一个常驻、可随时打开的“MCP 调用方”面板。视觉层级参考远程
桌面的连接权限窗口：先告诉用户“谁连进来了”，再展示“允许它做什么”，最后提供
真实调用记录和立即断开的操作。不能先放一堆工具图标，却把调用方身份藏到二级页。

固定布局顺序如下：

```text
┌──────────────────────────────────────────────┐
│ ① 调用方身份卡                              │
│ [APP图标] VibeKits@设备名-硬件码             │
│           instanceId / 证书指纹摘要          │
│           已连接 00:01:43 · 正在调用/空闲    │
│           来源私网地址 · 当前连接 ID         │
├──────────────────────────────────────────────┤
│ ② 权限                                      │
│ [状态查询:开] [文件发送:部分] [设备控制:开]  │
│ [剪贴板:关] [屏幕/输入:关] [Harness自动化:开]│
├──────────────────────────────────────────────┤
│ ③ 当前调用（有活动任务时显示）              │
│ kemi.files.send · running · 63% · taskId摘要 │
├──────────────────────────────────────────────┤
│ [调用记录]                    [断开连接]      │
└──────────────────────────────────────────────┘
```

#### 3.4.1 第一项必须是“谁在调用”

调用方身份卡至少显示：

- 调用方 APP 图标、APP 名、设备显示名和完整 `instanceId`；
- 调用方实例证书 SHA-256 指纹（默认可缩写，点击可看完整值）；
- `已连接/正在调用/空闲/正在断开/已断开/身份异常`，文字和颜色同时区分；
- 当前连接持续时间、首次连接时间、最后一次调用时间；
- 来源 RFC1918 地址、MCP `Mcp-Session-Id` 或等价本地 `connectionId`；
- 当前活动调用数，以及是否命中持久授权、临时暂停或黑名单。

显示名和 IP 只是帮助用户识别；授权判断仍使用
`callerInstanceId + callerFingerprint + providerInstanceId + scope`。多调用方同时在线
时一方一张卡，正在调用的排最前，其余按最后活动时间排序；断开只能作用于当前选中
调用方，不能误伤其他已认证调用方。

首次授权页使用同一身份卡样式，但状态写成“请求连接”，并在用户确认前禁止执行
副作用。身份指纹改变必须显示“身份已变化，需要重新授权”，不能沿用旧头像和旧名称
让用户误认为同一设备。

#### 3.4.2 “权限”描述 MCP 真正能调用的功能

权限区域不是系统权限的装饰图标，而是当前调用方持久授权的实时投影。权限由
`tools/list`、工程 `_meta`、风险类别和资源作用域动态生成；APP 没有的能力不显示。
推荐的标准分组为：

| 权限分组 | 对应能力示例 | 必须显示的作用域 |
|---|---|---|
| 状态与查询 | device.status、devices.list、status、last_result | 可查询的设备/任务范围 |
| 文件读取 | 读取、选取、哈希文件 | 允许的源目录、类型和大小上限 |
| 文件发送/接收 | files.send、upload、download | 目标设备、接收目录、覆盖策略和大小上限 |
| 数据写入 | 配置、数据库、项目文件修改 | 资源根、数据集/项目和写入边界 |
| 剪贴板 | 读取/写入系统剪贴板 | 文本/文件/图片类型、方向和敏感数据限制 |
| 屏幕与输入 | 截图、键盘、鼠标、触控 | 目标屏幕/设备、只观察或可控制 |
| 设备控制 | 安装、启动、ADB、串口、基准压测 | 目标设备 ID、命令/动作白名单 |
| 网络与进程 | 网络探测、端口、服务/进程控制 | 主机、端口、进程和允许动作 |
| Harness 自动化 | 由智能体自主组合以上工具 | 允许的工具组、最高风险和资源边界 |

每个权限块必须同时有图标、短名称和 `开/部分/关/已撤销` 文本，不能只靠蓝色或灰色
表达。悬浮或点击后展示：包含的完整工具名、用途、风险、授权时间、资源范围、最近
使用时间和调用次数。“部分”表示工具或资源只授权了一部分，必须列明缺失范围。

点击权限块只能查看、缩小或撤销现有范围；扩大权限必须重新进入正式扩权确认页，
展示新增工具、资源和风险，不能用一个无说明的 ON 按钮静默提权。运行期间撤销某项
权限时，立即拒绝该范围的新调用；相关在途调用按工具 cancel 合同安全终止并返回
`AUTH_SCOPE_REVOKED` 或 `USER_TERMINATED`。

#### 3.4.3 “调用记录”是被调用审计，不是普通调试日志

底部按钮固定命名为 `调用记录`；如果 APP 另有开发调试日志，必须放在其他入口，
不能混用。调用记录中的每一行对应一次真实 MCP 工具调用，至少包含：

- 调用方显示名、instanceId/指纹摘要和连接 ID；
- provider instanceId、toolName、catalogRevision；
- 开始/结束时间、duration、traceId、taskId；
- 脱敏参数摘要、命中的权限/资源作用域；
- `accepted/running/succeeded/failed/cancelled/verified` 状态、进度和稳定错误码；
- 结果摘要、物理证据摘要、是否由用户终止、是否发生重试/恢复；
- 对工具信誉的本次影响。

默认按时间倒序，支持按调用方、工具、结果和时间筛选，并能从活动调用跳到对应记录。
记录至少保留 7 天或最近 1000 条（先到更大覆盖范围者），存储达到上限时有界轮转。
不得记录私钥、Token、密码、完整文件内容、完整敏感路径或未脱敏剪贴板内容。

#### 3.4.4 “断开连接”必须真正停止当前调用方

`断开连接` 是随时可用的主动作，语义等同远程桌面的“断开当前会话”，不是关闭面板：

1. 用户点击后立即把选中调用方设为 `disconnecting`，停止接受它的新
   `tools/call`；新请求返回 `CALLER_DISCONNECTED`。
2. 向该连接的全部在途调用传播取消信号；文件、网络、ADB、串口、设备控制和
   Harness 组合任务必须停止后续步骤、关闭会话并释放锁。已不可逆完成的原子副作用
   不伪装回滚，记录为 `executed/partial`。
3. 每个被取消调用返回 `isError=true`、`ok=false/final=true/state=cancelled` 和
   `error.code=USER_TERMINATED`，同时写入调用记录。
4. 关闭或失效当前 `Mcp-Session-Id/connectionId`、SSE 流及该调用方的临时传输状态；
   其他调用方和全局 MCP listener 继续运行。
5. 调用端收到 `CALLER_DISCONNECTED` 或 `USER_TERMINATED` 后禁止自动无限重连；只有
   新的用户/智能体任务明确发起，或被调用端点击“允许重新连接”，才能创建新会话。
6. 断开完成后身份卡保留为 `已断开`，用户可进入调用记录查看终态。

必须严格区分四个层级：

| 操作 | 影响范围 | 持久授权 | 全局 MCP |
|---|---|---|---|
| `强制关闭本次调用` | 一个 traceId/taskId | 保留 | 保持 ON |
| `断开连接` | 当前调用方连接及其全部在途调用 | 默认保留 | 保持 ON |
| `撤销权限/拉黑调用方` | 当前调用方后续工具或全部连接 | 删除/禁止 | 保持 ON |
| `关闭 MCP` | 所有调用方、在途调用、HTTPS 和 announce | 按用户选择保留或清除 | 进入 OFF |

仅关闭窗口、隐藏状态卡、断开 SSE 但继续执行后台任务，或断开后由 SDK 无限制自动
重连，都判定为不合格。

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
    "catalogRevision": 2138,
    "capabilityDigest": "sha256:abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
  },
  "callEndpoint": {
    "transport": "https-streamable-http",
    "port": 9443,
    "path": "/mcp",
    "instanceKeyFingerprint": "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    "protocolVersions": ["2025-06-18"],
    "catalogRevision": 2138,
    "capabilityDigest": "sha256:abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
    "serviceRole": "tool-provider"
  },
  "mcp": {
    "protocolVersions": ["2025-06-18"],
    "catalogRevision": 2138,
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

### 4.4 启动顺序、周期发现与恢复（先启动的 APP 也必须被发现）

发现不得依赖一次性启动报文。提供方在 MCP 为 ON 且 HTTPS listener 健康期间必须
立即发送一次 announce，并每 4 秒在每张合格私网 IPv4 网卡重发；调用方无论何时
启动，都必须先完成 `bind + joinMulticast + listen`，然后持续接收，不能只在自己
启动瞬间扫描一次。调用方启动后应在一个公告周期内开始看到已运行提供方，最迟
8 秒进入 `verifying`，在 TLS/目录验证完成后进入 `verified`；12 秒 TTL 只用于移除，
不能被当作首次扫描等待时间。

网卡新增、地址变化、睡眠唤醒、VPN 切换和监听 socket 异常后，双方必须重新枚举
接口、重新 join 并立即 announce；接收端必须保持已知节点的退避验证状态，下一条
有效公告到达时恢复。APP A 先开、B 后开与 B 先开、A 后开都属于强制测试矩阵。
测试至少覆盖：提供方提前运行 10 秒后再启动调用方，调用方在 8 秒内发现；调用方
先运行后提供方打开，结果相同；调用方重启后无需提供方重启即可重新发现；丢失
goodbye 时 12 秒移除，提供方恢复后 8 秒内重新出现。
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

返回至少包含 `transferId/status/sourceSize/sha256/targetDeviceId/targetName/bytesTransferred`；长传输应另有 `kemi.files.status` 和 `kemi.files.cancel`。文件内容和路径不得进入 UDP 公告、日志摘要或证书。首次授权必须显示允许的源文件根目录、目标设备范围、大小上限和覆盖策略；之后范围内调用自动执行，不得逐文件重复询问。接收端若要求自己的许可，必须提供同样可持久化的自动接收授权；没有接收授权的目标不得宣称支持无人值守自动化落盘。

KEMI传书当前生产目录必须完整列出下列四个工具；VibeKits 不得只显示名称，必须同时展示运行时 `description/inputSchema/risk/验收状态`：

| 工具 | 输入 | 功能与结果 | 风险和当前边界 |
|---|---|---|---|
| `kemi.device.status` | `{}` | 返回 KEMI 实例、版本/构建号、系统、运行时长、内存、本机 IP、文件服务、附近设备数和 MCP 发送状态 | 只读；已真实调用成功 |
| `kemi.devices.list` | `{}` | 返回在线接收目标的 `targetDeviceId`、别名、IP、端口、HTTPS、系统和设备类型 | 只读但暴露局域网设备元数据；已真实调用成功 |
| `kemi.files.last_status` | `{}` | 返回活动态或最近一条脱敏发送终态；活动态 `final=false`，终态 `final=true`，终态保留 7 天 | 只读；不得返回源路径、文件内容、Token、远程会话 ID 或接收端保存路径；已真实调用成功 |
| `kemi.files.send` | 见下表 | 从本机读取一个明确的普通文件，经 KEMI 正式 TLS 固定链路发送到 `devices.list` 的在线目标 | 高风险文件外发；发送端和接收端均须先配置持久自动授权，范围内不得逐次询问；真实 handler 和路由已验证，但尚未取得 Windows 接收端落盘路径/大小/SHA-256，不能标为“落盘成功” |

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

`capabilityDigest` 的输入是完成所有分页后的规范对象 `{"tools":[...],"nextCursor":null}`：Map key 递归按 Unicode 字符串排序，数组保序，UTF-8 编码后 SHA-256。tools 中必须包含 name/title/description/inputSchema/outputSchema/annotations/_meta 以及实现公开的 risk 扩展。客户端必须基于服务端返回的**原始完整工具对象**计算摘要，不能先映射成自己的 UI 模型再计算，否则未知扩展、工程 `_meta` 或结构化 `risk` 会被删除/改形。公告三个位置的 digest 完全相同；任何差异拒绝目录。`catalogRevision` 是独立的单调变更键，不能用四位摘要截断代替。

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
| `kemi.benchmark.run` | `controlsDevice` | 必填 `mode`：`quick` 或 `stability`；必填 `idempotencyKey`：字符串 8–128 字符；拒绝额外参数 | 首次 MCP 授权已包含该工具时立即自动启动并返回非空 `taskId`、状态工具名、建议轮询秒数；不得再次弹窗；同一幂等键重试必须指向同一任务 |
| `kemi.benchmark.status` | `readOnly` | 必填 `taskId`：字符串 1–128 字符；拒绝额外参数 | 活动态返回阶段/轮次进度和 `final=false`；完成态必须在同一响应返回 `final=true`、完整 `result`、`reportSha256`；未知/过期任务返回稳定 `TASK_NOT_FOUND` |
| `kemi.benchmark.cancel` | `controlsDevice` | 必填 `taskId`：1–128 字符；必填 `idempotencyKey`：8–128 字符；拒绝额外参数 | 已授权范围内自动取消并返回当前终态，不得再次弹窗；重复取消必须幂等 |

标准调用流程固定为：

1. 先从已固定证书且摘要验证通过的当前目录取得 Schema，禁止调用方硬编码旧 revision 或猜参数。
2. 调用 `run({"mode":"quick","idempotencyKey":"<8-128 字符唯一键>"})`。若首次持久授权已包含该调用方、`kemi.benchmark.run` 和 `controlsDevice`，被调用端必须立即自动执行并返回 taskId，禁止再次弹出本机权限确认。只有不在授权范围内时才返回稳定 `AUTH_SCOPE_REQUIRED`；不能用等待 110 秒后的 `DENIED` 代替明确的扩权结果。
3. 保存 `taskId`，按返回的建议间隔（缺失时 5 秒，客户端夹在 2–15 秒）调用 `status({"taskId":"..."})`，直到 `final=true`。查询本身必须只读、无需再次允许且可跨调用方重启恢复。
4. 若网络/调用方在运行中断开，恢复后调用 `last_result({})`；提供者至少保留最近一条完整终态，使调用方仍能取得结果证据。
5. 调用方只有同时验证 `isError=false`、`ok=true`、实例/工具/revision 身份、`result` 为对象、`reportSha256=sha256:<64 位小写十六进制>` 后，才能宣布任务完成。

本次真实回收验证通过：Harness 经 `vibekits.mcp.catalog_list → vibekits.mcp.tool_call → LAN kemi.benchmark.last_result` 得到 `isError=false`、`available=true`、完整三轮 `result`；taskId=`b07e6779-8815-45e2-b94e-dea3a7ff2311`，mode=`quick`，elapsedMs=`73744`，finalScore=`99.15625`，grade=`S`，capacity/frame/input/stability 均为 `100`，reportSha256=`sha256:db6d5ff14dd3a060469a5c5d21804a0c6f196b3e967a4a6c0760384f34cfc363`。旧服务对 `run` 仍逐次弹窗并在无人点击时返回 `DENIED`，按本节新标准判定为**自动化不合格**，必须改成首次持久授权后自动执行。

VibeKits 服务端仅接受私网/loopback 来源的 `POST /mcp`，其他 path/method 返回 404，排空时返回 503，并发超过 8 返回 429，请求超过 1 MiB 返回 413。JSON-RPC parse/invalid request/invalid params/method not found/internal error 分别使用标准 `-32700/-32600/-32602/-32601/-32603`；通知成功可返回 HTTP 202 空响应。

所有远端 `tools/call` 必须进入与本机 Harness 相同的 `VibekitsHarnessToolBridge.invoke`：先按当前 inputSchema 验证参数，再匹配持久自动调用授权的调用方、工具、风险和作用域。命中授权即自动执行；不命中则返回 `AUTH_SCOPE_REQUIRED` 并引导用户在设置中扩权，禁止在单次 HTTP 调用里长时间等待弹窗。成功、失败和拒绝都写入 `HarnessToolActivityStore`。MCP 总开关默认关闭；只有首次风险确认通过后才监听端点并广播，之后无需逐次审批。

VibeKits 的发现接收与“向外暴露 MCP”开关相互独立：即使总开关关闭，APP 仍监听局域网公告并显示其他设备；关闭只停止本 APP 的 HTTPS Server 和对外公告。运行态路径不得从 `Directory.current`/工作区推导。开关同意状态保存在平台 Application Support 的 `Vibekits/mcp/exposure.json`；本机进程注册目录保存在平台 Application Cache 的 `Vibekits/mcp/registrations`。任一本地注册目录不可写都只能令 local 层为空，不能阻断 LAN 订阅。初始化失败必须回滚 started/subscription/timer 状态，允许下一次重试。

以下情况 VibeKits 会拒绝调用：工具不在当前目录、Schema 无效、目录摘要不匹配、实例指纹改变、设备已 `goodbye`/TTL 离线、端点跳出私网、响应超出限制。

VibeKits 对目录握手使用 8 秒短超时，对 `tools/call` 使用 120 秒调用超时。目录认证失败时实例仍保留在实时列表，但必须标记 `callable=false` 并返回有界 `catalogError` 与稳定 `catalogErrorCode`。机器目录必须分别表达 `discoveryAlive`（TTL 内收到公告）、`endpointReachable`（TCP/TLS/HTTP 端点是否可达）和 `catalogState=verifying|unreachable|rejected|verified`；UI 和 Harness 禁止把 `discoveryAlive=true` 简写成“可用”。同一端点、指纹、revision 和 digest 未变化时，失败重试至少退避 5 秒，禁止每个重复 UDP 公告都立即重做 TLS/目录认证。任一身份或目录键变化则立即清除退避并重新验证。授权检查必须本地同步完成，命中持久授权立即执行，不得把 110 秒预算用于等待人工批准；未授权立即返回 `AUTH_SCOPE_REQUIRED`。文件接收等外部目标响应可使用不超过 110 秒的业务超时。超过客户端调用时长的工作必须尽快返回 `taskId`，并提供无需再次授权的 status/cancel 工具。

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

网络断开、目录版本变化和远端错误必须保留来源信息；不得悄悄改成本机 shell 执行。写入/设备控制是否允许由持久自动调用授权的风险上限和作用域控制，不做普通 MCP 的逐次审批。

### 6.1 每个工具必须说清“能做什么”

`tools/list` 和 APP 接入文档对每个工具都必须给出：

- 稳定 `name`、人类可读 `title` 和不含糊的 `description`；
- 完整 `inputSchema`：字段、必填、类型、范围、枚举、默认值、`additionalProperties`；
- `readOnly/writesData/controlsDevice/destructive`、外发数据范围和首次授权作用域；
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

Harness 通过 `vibekits.mcp.reputation_list` 查看全局记忆，通过 `vibekits.mcp.reputation_rate` 写入 0–5 分。任何评分都不能绕过 TLS 指纹、目录摘要、inputSchema、在线检查或持久授权作用域。

### 6.3 Harness 工程执行闭环（核心目标）

LMCP 的最终目标不是“设备出现在列表里”，而是让 Harness 在没有阅读对方源码、
没有人工逐步指定工具的情况下，依据实时 `tools/list` 完成工程任务。每个工程任务
必须按以下闭环执行；任何一步缺失都只能报告“部分完成”：

```text
理解目标
  → 刷新 app/local/lan 三层目录并验证身份、在线和目录摘要
  → 读取候选工具的完整 Schema、风险、资源和完成合同
  → 分解为 preflight / action / observe / verify / recover
  → 选择同层最高信誉且满足作用域的工具
  → 生成幂等键并按 Schema 调用
  → 短任务读取终态；长任务保存 taskId 并自动轮询 status
  → 用设备状态、传感器读数、接收回执或制品哈希验证物理结果
  → 失败时按稳定错误码重试、恢复、取消或换候选
  → 输出结果、证据、未验证项并更新全局信誉
```

Harness 不得：根据工具名猜参数；把 `announce` 当可调用；把 `accepted/running` 当
完成；网络失败后静默改走 shell；因调用端重启丢掉 `taskId`；只复述提供方的
“成功”文字而不检查完成合同；为了自动化而绕过首次持久授权。

对于“测试 62 机器稳定性”这类目标，合格 Harness 应自行完成：刷新目录 → 找到
声明稳定性测试能力的已验证实例 → 比较 Schema/风险/评分 → 调用 run → 保存
taskId/traceId → 按建议间隔调用 status 到 `final=true` → 校验报告哈希、分数和
设备身份 → 返回证据。用户不需要先告诉 Harness 每个具体工具名。

### 6.4 物理工具的机器可理解自描述

所有允许 Harness 自动选择的工具，除 MCP 标准 `name`、`title`、`description`、
`inputSchema`、`annotations` 外，必须提供 `outputSchema`，并在 MCP 标准 `_meta` 的命名空间键
`com.caucy.vibekits/lmcp-engineering` 下提供以下工程合同。其他 MCP 客户端可按标准
忽略未知 `_meta`，但 LMCP/2 工程验收必须读取；该字段属于目录摘要输入，变化必须
提升 `catalogRevision`。禁止自创会被严格 MCP Schema 拒绝的顶层字段。

```json
{
  "name": "kemi.benchmark.run",
  "title": "运行设备稳定性测试",
  "description": "在指定设备上启动真实稳定性基准。返回 taskId，不代表测试已完成；必须调用声明的 statusTool 直到 final=true。",
  "inputSchema": {
    "type": "object",
    "properties": {
      "mode": {
        "type": "string",
        "enum": ["quick", "stability"],
        "description": "quick 用于约两分钟预检；stability 用于发布前长时验收"
      },
      "idempotencyKey": {
        "type": "string",
        "minLength": 8,
        "maxLength": 128,
        "description": "调用方为一次逻辑任务生成；重试必须复用"
      }
    },
    "required": ["mode", "idempotencyKey"],
    "additionalProperties": false
  },
  "outputSchema": {
    "type": "object",
    "required": ["schemaVersion", "ok", "final", "state", "instanceId", "toolName", "catalogRevision", "traceId", "taskId"],
    "properties": {
      "schemaVersion": {"const": 1},
      "ok": {"type": "boolean"},
      "final": {"type": "boolean"},
      "instanceId": {"type": "string"},
      "toolName": {"const": "kemi.benchmark.run"},
      "catalogRevision": {"type": "integer", "minimum": 1},
      "traceId": {"type": "string"},
      "taskId": {"type": "string"},
      "state": {"enum": ["accepted", "running", "succeeded", "failed", "cancelled", "unknown"]}
    }
  },
  "annotations": {
    "readOnlyHint": false,
    "destructiveHint": false,
    "idempotentHint": true,
    "openWorldHint": false
  },
  "_meta": {
    "com.caucy.vibekits/lmcp-engineering": {
      "contractVersion": 1,
      "capabilityId": "device.stability.benchmark",
      "domains": ["device-testing", "performance", "stability"],
      "verbs": ["measure", "stress", "report"],
      "riskClass": "controlsDevice",
      "executionMode": "asynchronous",
      "resources": [{"kind": "device", "selector": "provider-instance"}],
      "preconditions": ["provider MCP is ON", "no benchmark is already running"],
      "effects": ["creates CPU/GPU/input load", "writes a benchmark report"],
      "statusTool": "kemi.benchmark.status",
      "cancelTool": "kemi.benchmark.cancel",
      "recoveryTool": "kemi.benchmark.last_result",
      "defaultPollAfterMs": 5000,
      "completion": {
        "terminalStates": ["succeeded", "failed", "cancelled"],
        "successState": "succeeded",
        "requiredEvidence": ["reportSha256", "finalScore", "grade", "completedAt"]
      },
      "retry": {
        "requiresIdempotencyKey": true,
        "retryableCodes": ["ENDPOINT_UNAVAILABLE", "CALL_TIMEOUT"],
        "nonRetryableCodes": ["INVALID_ARGUMENTS", "AUTH_SCOPE_REQUIRED"]
      }
    }
  }
}
```

字段合同：

| 字段 | 必须表达的内容 |
|---|---|
| `capabilityId` | 与设备实例无关的稳定能力类别；同能力多设备候选可比较，不作为安全身份 |
| `domains/verbs` | 让 Harness 按目标检索，而不是只做工具名模糊匹配 |
| `riskClass` | `readOnly/writesData/controlsDevice/destructive` 之一，必须与首次授权一致 |
| `executionMode` | `synchronous/asynchronous/streaming`；不得让客户端猜是否需要轮询 |
| `resources` | 操作的设备、文件根、端口、账号或项目选择方式及边界 |
| `preconditions/effects` | 调用前必须成立的条件，以及会真实改变或占用什么 |
| `statusTool/cancelTool/recoveryTool` | 长任务的查询、取消和断线恢复入口；异步工具必须提供 |
| `completion` | 哪个状态才算成功，以及必须取得哪些证据字段 |
| `retry` | 哪些错误可安全重试、是否必须复用幂等键、哪些错误必须停止 |

只写“执行测试”“发送文件”“控制设备”不合格。`description` 必须明确：何时调用、
何时不要调用、参数如何选择、返回是受理还是终态、怎样验证、可能的副作用和失败。

### 6.5 标准结果信封和长任务恢复

每次 `tools/call` 的 `structuredContent` 必须返回一个可机器判断的信封。同步成功
直接 `final=true`；异步受理必须 `final=false`，且给出后续工具和参数，不能只在
自然语言 `content` 中说“已开始”。按 MCP 2025-06-18 兼容要求，返回
`structuredContent` 时还应在一个 `TextContent` 中返回同一 JSON 的序列化文本；
`outputSchema` 存在时服务端必须保证 structuredContent 符合它，客户端必须验证。

```json
{
  "schemaVersion": 1,
  "ok": true,
  "final": false,
  "state": "running",
  "instanceId": "com.newlink.kemiscrollbench:41B8C7FDF4",
  "toolName": "kemi.benchmark.run",
  "catalogRevision": 4,
  "traceId": "b0abf463-271d-4f80-8bed-317b19227ea4",
  "taskId": "73f07dc1-b686-42cb-a26b-b264ae70f929",
  "startedAt": "2026-09-01T01:20:00Z",
  "pollAfterMs": 5000,
  "status": {"toolName": "kemi.benchmark.status", "arguments": {"taskId": "73f07dc1-b686-42cb-a26b-b264ae70f929"}},
  "cancel": {"toolName": "kemi.benchmark.cancel", "requiresNewIdempotencyKey": true},
  "recovery": {"toolName": "kemi.benchmark.last_result", "retentionSeconds": 604800},
  "progress": {"completed": 1, "total": 4, "unit": "phase"},
  "result": null,
  "evidence": [],
  "warnings": []
}
```

终态必须保留同一 `taskId`，每次调用拥有自己的 `traceId`，并返回：

```json
{
  "schemaVersion": 1,
  "ok": true,
  "final": true,
  "state": "succeeded",
  "instanceId": "com.newlink.kemiscrollbench:41B8C7FDF4",
  "toolName": "kemi.benchmark.status",
  "catalogRevision": 4,
  "traceId": "87f11dc6-063c-4f87-a789-b06f51984649",
  "taskId": "73f07dc1-b686-42cb-a26b-b264ae70f929",
  "startedAt": "2026-09-01T01:20:00Z",
  "completedAt": "2026-09-01T01:21:14Z",
  "result": {"finalScore": 99.54, "grade": "S"},
  "evidence": [{
    "kind": "artifact",
    "name": "benchmark-report",
    "sha256": "sha256:db6d5ff14dd3a060469a5c5d21804a0c6f196b3e967a4a6c0760384f34cfc363",
    "observedAt": "2026-09-01T01:21:14Z",
    "sourceInstanceId": "com.newlink.kemiscrollbench:41B8C7FDF4"
  }],
  "sideEffects": ["benchmark report persisted"],
  "warnings": []
}
```

失败时 `isError=true`，同时保留结构化信封：`ok=false`、`final=true`、稳定
`error.code`、有界脱敏 `message`、`retryable`、`category` 和可选 `retryAfterMs`。
HTTP 200 只代表 MCP 信封成功传输；`isError=false` 只代表工具没有报告错误；只有
`ok=true && final=true && state=succeeded` 且完成证据通过 Schema 和身份校验，
Harness 才能宣布工程任务完成。

客户端必须把 `taskId/provider instanceId/tool/catalogRevision/status arguments` 写入
任务恢复记录。APP、Harness 或网络重启后先刷新并重新验证目录，再调用 status；
若 taskId 已过期则调用 recoveryTool。不得因重启重复执行物理副作用。

### 6.6 物理世界任务的结果验真

物理操作必须区分四个阶段：`requested`（请求已发送）、`accepted`（提供者受理）、
`executed`（动作代码返回）、`verified`（目标世界状态已观察并满足完成条件）。前
三个阶段都不能单独写“已完成”。优先使用独立只读工具或目标端回执验证，不得只
相信发起动作的同一字符串。

| 任务 | 最低完成证据 |
|---|---|
| 远程文件发送 | 接收目标稳定身份、实际保存状态/路径摘要、字节数、接收端 SHA-256；发送端上传完成不够 |
| APP 安装/启动 | 目标设备 ID、安装后包版本/签名摘要、进程或 Activity 状态、观察时间；ADB exit 0 不够 |
| 稳定性/性能测试 | 新 taskId、run/status traceId、终态、完整指标、报告 SHA-256、开始/完成时间 |
| 设备开关/控制 | 动作前状态、动作回执、动作后只读状态或传感器读数；仅“命令已下发”不够 |
| 数据写入/配置 | 目标资源 ID、写入版本/ETag/哈希、读回值或服务端提交回执 |
| 采集/测量 | 设备/传感器身份、单位、采样时间、样本数、量程/置信度、原始制品哈希或可追溯摘要 |

每条证据必须标注 `sourceInstanceId/observedAt/kind`；制品使用
`sha256:<64 位小写十六进制>`。Harness 最终报告必须把结论分为：已验证事实、提供
方声明但未独立验证、推断、阻塞项。任何无法取得最低证据的任务必须返回
`verification=partial|failed`，不能为了让流程全绿而补写虚假成功。

### 6.7 自动选型、组合调用和降级规则

1. Harness 先按工程 `_meta` 中的 `capabilityId/domains/verbs/resources` 找候选，再验证工具 Schema；
   只有旧工具没有工程扩展时才退回 `name/title/description` 语义匹配并明确降低置信度。
2. 固定层级仍是 `app → local → lan`；同层同能力按兼容性、授权范围、在线状态、
   完成证据能力、全局信誉、延迟排序。评分不能让未验证端点越过安全门禁。
3. 多工具任务必须形成显式执行图；例如“向 62 发包并压力测试”至少包含设备查询、
   文件发送、接收验证、安装、启动、测试、status、结果验真和清理，不得在中途成功
   后跳过后续目标。
4. 可并行的只读观察可并行；共享设备、端口、文件或控制会话的副作用操作默认串行，
   除非工具明确声明并发安全和锁语义。
5. `AUTH_SCOPE_REQUIRED/INVALID_ARGUMENTS/CALLER_BLOCKED` 不自动换工具规避授权；
   `ENDPOINT_UNAVAILABLE/CALL_TIMEOUT` 才可在保留幂等键和审计的前提下重试或换同层候选。
6. 降级到更低层、不同设备或功能较弱工具前，Harness 必须确认仍能满足原完成合同；
   不能把“做了类似动作”当成完成用户目标。

每次调用结束后，自动完成质量由“调用成功、终态取得、证据完整、结果满足目标、
无需人工补救”共同计算。HTTP 成功但没有终态/物理证据应降权；错误结果、虚假完成、
重复副作用或任务完成率低必须显著降权。

### 6.8 Harness 面向用户的最终报告

Harness 完成工程任务后至少输出：

- 用户目标及实际执行范围；
- 使用的每个 `instanceId/toolName/catalogRevision` 和选择原因；
- 关键输入的脱敏摘要、幂等键摘要、taskId 与各阶段 traceId；
- 每一步 `state/final/duration`，以及重试、换工具、取消和恢复记录；
- `result` 中与目标相关的字段和最低物理证据；
- 明确的 `completed/partially_completed/failed/cancelled` 结论；
- 未验证项、残留副作用、需要人工处理的下一步；
- 对实际工具完成质量的信誉更新。

自然语言可以解释结果，但不得替代结构化结果和证据。敏感路径、Token、私钥、完整
文件内容、远程会话密码不得进入报告；需要关联时使用稳定资源 ID、basename、大小和
哈希。

### 6.9 指挥官—作战单位架构与大规模实时调度

LMCP/2 把角色明确分成两类：Harness/Codex 等任务规划器是“指挥官
（commander）”；完整遵守本文、接受已授权自动调用并能返回可验证结果的 MCP
Provider 是“作战单位（worker）”。同一局域网允许多个指挥官和至少 100 个同类型
作战单位同时存在。发现在线只代表“看见”，满足身份、能力、授权、负载、租约、取消、
结果和验真合同后才可标记为 `schedulable=true` 并接受调度。

#### 6.9.1 作战单位必须实时声明的运行状态

每个 LMCP/2 `announce` 除身份和目录摘要外必须携带以下有界 `runtime` 摘要；状态变化
时立即发送一次，稳定时仍按 4 秒周期发送，连续变化最多每 250 ms 合并一次，整个 UDP
包仍不得超过 1200 bytes：

```json
{
  "runtime": {
    "state": "idle",
    "capacity": 4,
    "inFlight": 0,
    "queueDepth": 0,
    "availableSlots": 4,
    "loadRevision": 318,
    "oldestTaskAgeMs": 0,
    "draining": false,
    "acceptingReservations": true
  }
}
```

`state` 只能是 `idle/busy/saturated/draining/error`。`capacity` 是该实例允许同时执行的
副作用任务数；`availableSlots` 必须由 Provider 权威计算，不能由调用方用
`capacity-inFlight` 猜测。状态查询、目录读取和租约控制不占业务槽位。负载变化必须
递增 `loadRevision`；数值矛盾、版本倒退或超过 TTL 的状态视为未知，不进入自动选择。
详细任务、资源类型和预计释放时间通过强制只读工具 `lmcp.node.status` 获取，不塞进 UDP。

#### 6.9.2 四个强制调度控制工具

每个可调度 Provider 必须实现下列保留工具，并在 `tools/list` 提供完整 Schema：

| 工具 | 必填参数 | 成功结果 | 语义 |
|---|---|---|---|
| `lmcp.node.status` | `{}` | runtime、各 capabilityGroup 槽位、活动租约数、服务时间 | 只读、快速、不得弹窗 |
| `lmcp.capacity.reserve` | `toolName,idempotencyKey,commanderId,requestedSlots,ttlSeconds,scopeDigest` | `leaseId,leaseToken,expiresAt,slot,loadRevision` | 在执行前原子占位；容量不足返回 `CAPACITY_BUSY` |
| `lmcp.capacity.renew` | `leaseId,leaseToken,ttlSeconds` | 新 `expiresAt` | 长任务续租；身份和原 commander 必须匹配 |
| `lmcp.capacity.release` | `leaseId,leaseToken,reason` | `released=true` | 完成、失败、取消或放弃时幂等释放 |

`reserve` 的 Provider 处理必须是原子的：多个指挥官同时抢最后一个槽位时最多一个成功。
租约默认 30 秒、允许范围 10～120 秒；未续租自动释放。`leaseToken` 是短期随机秘密，
只在签名 HTTPS 响应/请求中出现，绝不进入 UDP、日志或最终报告。后续业务
`tools/call` 必须携带 `leaseId` 和同一 `idempotencyKey`；租约的 tool、作用域摘要、
调用方身份不匹配时返回 `LEASE_SCOPE_MISMATCH`。Provider 崩溃恢复后未完成租约进入
`unknown/interrupted`，不得静默重做副作用。

#### 6.9.3 指挥官的节点表与最优选择

每个指挥官维护 `instanceId + fingerprint` 为键的实时节点表。无论 Provider 先启动还是
指挥官后启动，指挥官都必须加入组播、主动发送一次 `discover`，Provider 收到后在
0～500 ms 随机抖动内重发 `announce`；8 秒内必须收齐当前局域网在线节点。节点表按
TTL 自动下线，并保留有界历史健康数据但不得把历史节点伪装在线。

执行任务时固定按以下顺序：

1. 先过滤：在线、LMCP/2 严格验签、证书固定、`callable/schedulable=true`、工具与
   Schema/风险/作用域匹配、持久授权有效、非 draining/error、至少一个可预约槽位；
2. 再保持既有层级：本机 VibeKits MCP（app）→ 本地其他进程 MCP（local）→ 局域网
   MCP（lan）；低层级不能只靠高分越级抢占；
3. 同一层、同一工具类型按加权值排序：空闲槽位 35%、工具类型全局质量分 25%、
   节点近期可靠性 15%、预计排队/延迟 15%、状态新鲜度 5%、公平性 5%；
4. 用户对同一工具类型的评分是全局共享分，多台设备显示相同评分；节点掉线率、超时率、
   当前负载只形成独立健康权重，不篡改用户给工具类型的评价；
5. 对最高候选调用 `reserve`。若返回 `CAPACITY_BUSY/REVISION_STALE`，立即刷新该节点
   并尝试下一候选；成功后才调用业务工具。不得仅凭 UDP 的 `idle` 直接开工；
6. 同分使用 `hash(taskId + instanceId)` 稳定打散，避免多个指挥官永远冲击同一台设备。

“垃圾/错误 MCP”、结构化结果不合规、完成质量低、频繁超时或无物理证据时必须降权并
触发有界熔断；身份异常、Schema 欺骗或凭据泄漏直接隔离。熔断只影响该节点健康权重，
工具类型全局评分仍按用户规则共享。半开探测只能执行只读健康检查，不用真实副作用试错。

#### 6.9.4 任务编排、失败转移与完成判定

指挥官可以把一个工程目标拆给多个作战单位并行执行，但每个子任务必须有全局
`taskId/traceId/idempotencyKey`、输入/输出 Schema、资源作用域、deadline、取消策略、
前置依赖和完成证据。只有无副作用或 Provider 明确声明可幂等恢复的任务才能自动换队；
副作用结果处于 `unknown` 时必须先用 status/last_result 对账，禁止直接在另一节点重做。

业务完成后，指挥官先取得 Provider 的标准结果信封，再按 6.6 独立验真；HTTP 200、
`accepted=true`、租约释放或进度 100% 都不等于物理目标完成。最终报告必须列出候选数、
被选节点与选择理由、租约、重试/换队、每个 traceId/taskId、结果摘要、独立证据和
`executed/partial/verified` 等级。任何阶段都必须在 finally 路径释放租约；指挥官掉线则
由 TTL 回收，Provider 的用户“强制关闭”仍可立即终止并记为 `USER_TERMINATED`。

#### 6.9.5 100 节点、多指挥官强制验收

上线前必须用至少 100 个同名工具 Provider 和 10 个并发指挥官完成真实或协议级压力
验收：晚启动指挥官 8 秒内发现全部节点；空闲/忙/饱和变化 1 秒内进入节点表；100 次
同时争抢单槽位从不超卖；同类型全局评分一致；空闲节点优先且负载分散；节点断电在
12 秒内剔除；租约到期回收；幂等重试不重复副作用；取消释放槽位；最终结果可恢复并
验真。报告必须保存每次选择、reserve 冲突、峰值槽位、P50/P95 调度延迟、重复执行数
和泄漏租约数；后两项必须为 0。

## 7. 第三方 APP 交付检查表

- [ ] 显示名称包含 APP 名、主机名和 10 位硬件识别码。
- [ ] `app.id`、`hardwareCode`、`instanceId` 重启后稳定。
- [ ] 有用户可见、可持久化的 MCP 开关。
- [ ] 从关闭到打开会先显示完整工具清单、证书身份、风险和撤销方法；拒绝时保持关闭。
- [ ] 首次授权持久化调用方、工具、风险和资源作用域；范围内调用、重启、重连和 status/last_result 恢复均不再弹窗。
- [ ] 每次命中授权的调用自动执行，同时显示至少 3 秒的非阻塞运行提示；包含“调用信息”和真正取消工作的“强制关闭”。
- [ ] MCP 调用方连接面板第一项明确显示谁在调用：APP/设备、instanceId、证书指纹、连接状态、持续时间和活动调用数。
- [ ] 权限区由实际 tools/list/风险/资源授权动态生成，每项显示开/部分/关及完整工具和作用域；扩权必须重新确认。
- [ ] “调用记录”只记录真实 MCP 调用审计，包含 traceId/taskId、脱敏参数、状态、结果、物理证据和终止原因，不与开发调试日志混用。
- [ ] “断开连接”能停止选中调用方的新调用和全部在途工作，释放资源并返回 `USER_TERMINATED`；不会误关其他调用方或全局 MCP。
- [ ] 调用方身份绑定实例证书；匿名私网 IP 不能获得持久高风险授权；证书变化重新授权。
- [ ] 强制关闭返回 `USER_TERMINATED` 并释放网络、文件、设备会话；可继续撤销工具授权或拉黑调用方。
- [ ] 未授权或扩权调用立即返回 `AUTH_SCOPE_REQUIRED`，不得占用调用超时等待人工批准。
- [ ] OFF/STARTING/ON/DRAINING/ERROR 的状态有明显区别。
- [ ] 打开发送 `announce`，关闭发送 `goodbye` 并停止服务。
- [ ] 周期 announce 与监听恢复不依赖启动顺序：提供方先启动 10 秒、调用方后启动时仍在 8 秒内发现，反向顺序和调用方重启同样通过。
- [ ] 实现标准 `initialize/tools/list/tools/call`。
- [ ] 每个工具具有完整描述和 JSON Schema。
- [ ] 工程工具提供 `outputSchema` 与完整 `_meta["com.caucy.vibekits/lmcp-engineering"]`；Harness 不看源码也能知道能力、资源、前置条件、副作用、完成证据和恢复方式。
- [ ] 文件传输能力提供显式 send 和可查终态；异步长任务另有 status/cancel，不能只列设备。
- [ ] 异步工具返回 taskId/traceId/pollAfterMs/status/cancel/recovery，调用方重启后能恢复，重复请求不会重复物理副作用。
- [ ] 物理工具区分 requested/accepted/executed/verified，只有取得工具声明的最低证据才标记完成。
- [ ] 结果使用标准信封；成功必须 `ok=true/final=true/state=succeeded`，错误提供稳定 code/retryable/category。
- [ ] 已用一个包含至少三个工具的真实工程任务验证自动选型、编排、终态轮询、物理验真、失败恢复和最终报告。
- [ ] 每个工具已写明用途、全部参数、风险、成功结果、错误码和实际验收状态。
- [ ] 接口变化更新目录版本并发出通知。
- [ ] announce 携带自洽的 runtime/capacity/loadRevision；状态变化立即公告，过期状态不参与调度。
- [ ] 实现 `lmcp.node.status` 与 reserve/renew/release，多个指挥官竞争时原子占位、不超卖、不泄漏租约。
- [ ] 100 个同类型节点和 10 个并发指挥官验收通过：晚启动发现、空闲优先、公平分散、熔断换队、幂等和验真均有机器报告。
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

VibeKits 不再把扩展控件横向铺在 Harness 顶栏，也不把 Flutter 浮层叠在 Windows 原生 WebView 上。Harness Web 内容和一条 60px 的右侧工具轨采用物理分栏；不再保留“工具”总按钮。MCP 图标直接表示“打开本机 MCP”，与本机 MCP、局域网 MCP、飞书、日志、远程操作和设置使用同尺寸小图标纵向排列，悬浮后展示完整设备名、接口范围和当前状态。点击已关闭的 MCP 图标或设置面板开关时，必须先弹出权限和风险说明，仅“确认开启”后才启动服务、持久化授权并广播；关闭可立即执行。确认页必须包含远程 Harness/设备控制的可选范围；用户选中后该范围持续自动执行，不再独立逐次审批。本机/局域网设备数量使用右上角小徽标。设置图标打开统一面板，可查看设备身份、授权范围、切换 MCP、撤销授权、读取三层设备数和刷新目录。工具轨不得随主机名长度变化，不得遮挡 WebView，不得把控件挤向左侧。

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

其中必须覆盖：持久 P-256 证书重载指纹不变；严格公告 `<=1200` bytes；两个进程/实例共享一个 UDP 端口并收到 LMCP/2；提供方先启动 10 秒、调用方后启动仍在 8 秒内发现，反向顺序和调用方重启同样通过；RFC1918 多网卡地址全部入选且公网/回环排除；真实 TLS 指纹固定；调用方实例证书身份绑定；initialize→分页 tools/list→tools/call；错误 schema 不执行；持久授权命中后写入/控制工具无弹窗自动完成且显示非阻塞调用提示；调用信息可查、强制关闭返回 `USER_TERMINATED` 并释放资源；扩权立即返回 `AUTH_SCOPE_REQUIRED`；关闭清公告、endpoint 和授权。

### 9.1 VibeKits ↔ VibeKits

优先使用两台不同机器 A/B；同机验证时第一个服务使用 9443，第二个服务必须广播其真实动态端口：

1. 两边 MCP 初始为关；确认 UDP 47831 在监听但 TCP 9443 未监听、无 LMCP/2 announce。
2. A 先打开并保持至少 10 秒，再启动 B；确认 A 的授权框列出证书指纹和全部工具，抓包看到 A 每 4 秒 announce，B 启动后 8 秒内出现 A。随后重启 B，A 不重启，B 仍须在 8 秒内重新发现。
3. B 对 A 依次发送 initialize、notifications/initialized、完整分页 tools/list；重算摘要必须等于公告。
4. B 调用 `vibekits.calculator.programmer`，参数 `{"expression":"1+1"}`；结果 `isError=false`，并精确回显 A 的 instanceId、工具名、revision 和 traceId。
5. 在 A 的首次确认页仅授权一个无破坏性的 writesData/controlsDevice 测试工具；B 连续调用两次，确认 A 均不再弹审批且自动完成，但每次出现至少 3 秒的非阻塞调用提示。A 的调用方面板第一项必须显示 B 的 APP/设备、instanceId/指纹、连接时间和活动数；权限区显示实际授权工具和资源。展开“调用记录”核对两次 traceId、结果和证据。再发起两个可取消测试：先用“强制关闭本次调用”确认只取消一个 taskId；再用底部“断开连接”确认 B 的全部在途任务都得到 `USER_TERMINATED`、新请求得到 `CALLER_DISCONNECTED`，A 的其他调用方与全局 listener 不受影响。随后 A 撤销该工具授权，B 新建会话再调必须立即得到 `AUTH_SCOPE_REQUIRED` 且无副作用。禁止拿真实用户文件做破坏测试。
6. 交换 A/B 重复 2–5，证明双向而非单向。
7. A 关闭：先抓到 goodbye，B 立即移除；模拟断电不发 goodbye，B 在最后有效公告 12 秒后移除；A 公告的 TCP 端口不再接受连接。

### 9.2 VibeKits ↔ KEMI传书

已完成的生产证据是：Mac VibeKits 能固定 KEMI build102 证书、读取四工具目录并真实调用三个只读工具。这只证明了本机接收与调用。2026-08-31 的 10 秒实时监听只收到 Mac KEMI LMCP/2，没有收到 Windows VibeKits 任何公告；Windows 端也尚未给出“收到 KEMI announce”的抓包。因此当前跨机双向发现为**未验收**，必须按以下步骤补齐，不能用同机单元测试冒充：

1. KEMI 的 MCP 面板出现 VibeKits LMCP/2（不是兼容 LMCP/1），显示与抓包一致的 `instanceId/192.168.x.x:<实际端口>/mcp/fingerprint/revision/digest`。
2. KEMI 初始化 VibeKits 并读取完整目录，调用同一个只读计算器用例成功；VibeKits 审计记录来源工具、结果和耗时。
3. VibeKits 首次授权页选定一个无破坏性的高风险测试工具后，KEMI 连续调用应自动完成且不再弹窗；撤销授权后下一次调用立即收到结构化 `AUTH_SCOPE_REQUIRED`，不得自动改走 shell。
4. 分别关闭 KEMI 和 VibeKits，另一端验证 goodbye 立即消失、断电 TTL 消失、证书篡改拒绝、digest/revision 改变重新加载。
5. Windows 必须运行包含 LMCP/2 接收器的新构建，不能只核对 `1.9.0-dev.137+2137` 文本版本；验收记录必须同时保存 Git/source revision 或产物 SHA-256。
6. Windows 签名安装程序必须为实际 VibeKits 可执行文件创建 Private profile 入站 UDP 47831 和公告 TCP 端口规则；先用 `pktmon`/抓包证明收到 KEMI 报文，再调查 UI 解析。

验收记录至少保存：两端版本/SHA-256、两端私网 IP、10 秒 UDP 抓包、公告 TCP 端口建连、initialize 与每页 tools/list 的脱敏 JSON、摘要重算、一次只读调用、一次持久授权范围内的自动高风险调用、一次撤销后 `AUTH_SCOPE_REQUIRED` 审计、goodbye/TTL 时间。不得保存私钥、Token、完整用户路径或文件内容。

### 9.3 通用物理工程任务验收

每个第三方 APP 至少提交一个由 VibeKits Harness 自主执行的真实工程任务；不能由
开发者预先把每个工具名和调用顺序硬编码到测试脚本。验收提示只描述目标和目标
设备，例如“检查 62 机器当前能力，运行一次 quick 稳定性测试并给出可验证报告”。
Harness 必须自行完成：

1. 调用 `vibekits.mcp.catalog_list` 刷新目录，并记录目标的 instanceId、版本、
   revision、指纹和 catalogState；
2. 读取完整 `tools/list`，按工程 `_meta` 分析全部候选工具，输出所选工具、
   未选工具及原因；
3. 用完整 Schema 生成参数和唯一幂等键，通过 `vibekits.mcp.tool_call` 发起副作用
   工具；首次持久授权已覆盖时不得出现第二次审批；
4. 保存 run traceId/taskId，自动轮询声明的 statusTool 到终态；在中途重启 Harness
   一次，确认能从恢复记录继续而不重复副作用；
5. 取得 completion 声明的全部证据，并至少调用一个独立只读观察/验证工具；
6. 模拟一次可重试网络错误，确认复用幂等键；再模拟一次不可重试 Schema/授权错误，
   确认立即停止且不改走 shell；
7. 生成 6.8 规定的最终报告，并按真实完成质量更新信誉。

通过条件：目标完成、`final=true/state=succeeded`、实例与 revision 未串用、全部必需
证据可验证、无重复物理动作、无额外审批、恢复后结果一致。若设备本身拒绝、离线或
证据不足，Harness 正确输出 `partially_completed/failed` 也可证明错误处理合同工作，
但不能把该业务任务计为“成功完成”。

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
  └─AUTH_SCOPE_REQUIRED → 首次授权范围不足或已撤销；在设置中显式扩权后自动重试，禁止逐次弹窗

调用已返回但工程目标未完成
  ├─final=false → 保存 taskId，按 pollAfterMs 调 status；调用方重启后从恢复记录继续
  ├─state=succeeded 但无 requiredEvidence → 标记 verification=partial，不得宣布完成
  ├─物理状态与结果冲突 → 以目标端/独立观察证据为准，记录冲突并降低工具信誉
  └─任务失联 → 先 status，再 recoveryTool；不得直接重跑副作用工具
```

如果 `lsof`/`Get-NetTCPConnection` 显示 9443 已被同机另一个 LMCP APP 占用，VibeKits 允许绑定 OS 分配的动态端口，但必须在 announce 的两个 endpoint 精确广播这个端口并通过同样的 TLS/摘要校验；KEMI 的严格解析器接受 `1..65535` 的真实端口。任何端口都不得“偷偷”使用而不更新公告。自动化测试必须通过依赖注入使用隔离的 TCP/UDP 端口。
