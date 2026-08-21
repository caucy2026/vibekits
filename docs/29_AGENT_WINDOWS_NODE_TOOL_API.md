# Windows 节点智能体工具接口

协议：`vibekits.tools.v1`
适用：Harness、Codex 或其他通过 MCP `tools/list` 调用 VibeKits 的智能体。

## 通用返回

调用结果统一为：

```json
{"ok":true,"cancelled":false,"data":{}}
```

失败返回 `ok=false` 和脱敏 `error`；用户拒绝时 `cancelled=true`。系统写入必须逐次审批，工具日志不得保存密码、Token、私钥或完整公钥。

## 标准编排

```text
helper_status → inspect → plan → apply
→ ensure_client_identity → enroll_device → export_onboarding
→ verify → list_devices → revoke_device / rollback
```

## 接口表

| 工具 | 风险 | 输入 | 核心输出 | dev.61 状态 |
|---|---|---|---|---|
| `vibekits.windows_node.helper_status` | readOnly | 无 | `available,absolutePath,signatureValid,publisher,sha256,fileVersion,protocolVersion,manifestMatch,executableActions,unavailableReason` | 可执行；真实报告缺失状态 |
| `vibekits.windows_node.inspect` | readOnly | `rootPath?`，只能为 `D:\KEMI-Test` | `inspectionId,digest,checks,facts` | 可执行 |
| `vibekits.windows_node.plan` | readOnly | `inspectionId` | `planId,digest,actions,blockers,rollbackId,expiresAt` | 可执行 |
| `vibekits.windows_node.apply` | controlsDevice | `planId,planDigest,approvedActionIds[]` | helper 绑定回执、动作前后摘要、重检结果 | helper 未签名时不进入 executable catalog |
| `vibekits.windows_node.ensure_client_identity` | writesLocalCredentials | `deviceLabel,algorithm=ed25519,rotate=false` | `deviceIdentityId,publicKey,publicKeyFingerprint,credentialReference,createdAt` | 等待 macOS Keychain 适配器 |
| `vibekits.windows_node.enroll_device` | writesData | `planId,planDigest,deviceLabel,publicKey,expiresAt?` | `deviceId,fingerprint,status,authorizedKeysDigest,requiresLoginVerification` | 等待签名 helper 原子同步 |
| `vibekits.windows_node.list_devices` | readOnly | 无 | 设备 ID、标签、指纹、状态、最近连接；不返回公钥正文 | 可执行 |
| `vibekits.windows_node.export_onboarding` | readOnly | `host,port?,hostKeyFingerprint,allowedCidr` | 主机事实、固定 host key、SSH config、说明 | 可执行 |
| `vibekits.windows_node.revoke_device` | controlsDevice | `deviceId,expectedRegistryDigest` | 状态变化、active 数量、keys 摘要、回执 | 等待签名 helper 原子同步 |
| `vibekits.windows_node.verify` | remoteControl | `nodeProfileId,deviceIdentityId,checks[],enableLargeTransfer,enableDisconnectTest` | `NodeVerificationReport,WorkflowArtifact` | 等待 macOS 外部执行器 |
| `vibekits.windows_node.rollback` | controlsDevice | `rollbackId,expectedCurrentStateDigest` | helper 回执和重检结果 | 等待签名 helper |

## 调用规则

1. 必须先调用 `helper_status`；`available=false` 时不得反复调用写入工具，应把 `unavailableReason` 告知用户。
2. `planId/digest/rollbackId/registryDigest` 都是短期绑定值，状态变化后必须重新 inspect/list。
3. `publicKey` 只能来自 `ensure_client_identity`；不得要求用户粘贴私钥。
4. `verify` 必须在外部设备执行，localhost 报告会被拒绝。
5. apply、enroll、revoke、rollback 需要分别批准；一次批准不能跨工具复用。
6. GitHub 备份继续使用 `git.backup_preview → backup_commit → backup_push → verify_remote_ref`，commit 与 push 必须两次独立批准。

## 可用性发现

智能体以 MCP `tools/list` 为准：handler、签名 helper 或平台适配器缺失的工具只存在于完整能力说明，不会出现在 executable catalog。不要用任意 PowerShell、管理员 shell、共享私钥或全局代理绕过门禁。

## 外部 Codex 的本机 STDIO 配置

VibeKits APP 启动后会在当前用户目录原子发布短期 connection file；内容只包含 loopback endpoint、随机 token、进程 ID 和创建时间。工具桥关闭时自动删除，Codex 不需要保存或复制 token。外部工具调用写入与 Harness 相同的可删除活动日志；非只读调用在 APP 内逐次批准，APP 无法显示审批界面时默认拒绝。

Windows 默认 connection file：

```text
%LOCALAPPDATA%\Vibekits\Mcp\tool-bridge.json
```

仓库提供的 Windows 启动命令：

```powershell
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File D:\vibecode\vibekits\tool\start_vibekits_mcp.ps1
```

脚本优先使用 Release 内置 Node/MCP；VibeKits 未运行时会启动 Release APP，并等待 loopback bridge 就绪。项目级配置已写入 `.codex/config.toml`。如需所有本地项目共享，可执行：

```powershell
codex mcp add vibekits -- powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File D:\vibecode\vibekits\tool\start_vibekits_mcp.ps1
```

macOS 默认 connection file：

```text
~/Library/Application Support/Vibekits/Mcp/tool-bridge.json
```

在 `~/.codex/config.toml` 注册外部 Codex stdio MCP。启动器只使用 Node 标准库，不需要额外安装 MCP SDK：

```toml
[mcp_servers.vibekits]
command = "/usr/bin/env"
args = ["node", "/绝对路径/vibekits/native/harness/vibekits-codex-mcp.mjs"]
startup_timeout_sec = 30
```

操作顺序：

1. 启动 VibeKits；App 启动即发布本机桥，无需先进入 Harness 页面；
2. 保存 Codex MCP 配置并重启 Codex；
3. 在 Codex 输入 `/mcp` 或运行 `codex mcp list` 检查 `vibekits`；
4. 以实际 `tools/list` 为准调用工具；
5. VibeKits 退出后 connection file 自动删除，后续调用安全失败。

把 `/绝对路径/vibekits` 替换为 Mac 上的真实仓库路径。如果 Mac 的 Node 不在 shell PATH，也可以把 `command` 改为 Node 的绝对路径，并把 `args` 改为只包含脚本绝对路径。也可通过 `VIBEKITS_TOOL_BRIDGE_FILE` 指定非默认 connection file。写入或设备控制工具会在 VibeKits 窗口逐次显示“允许一次/拒绝”，没有可见窗口或用户未批准时安全拒绝。禁止配置局域网 HTTP URL；bridge 必须保持 `127.0.0.1`。
