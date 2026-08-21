# Mac 端调用 Windows 测试节点指南

版本：1.0
日期：2026-08-21
协议：`vibekits.tools.v1`
目标：Mac 上的 VibeKits Harness、Codex 或其他 MCP 智能体使用独立身份接入 Windows 测试节点，并通过 SSH/SFTP 执行仿真测试。

## 1. 当前 Windows 节点事实

2026-08-21 已通过 VibeKits 真实只读 `inspect → plan` 获得：

```text
Windows host: 192.168.3.58
SSH port: 22
SSH host key: SHA256:ikZ6NXAH3VFBGooSCeKW0JY9+h0cIcQOzib4fxmvz6M (ED25519)
Allowed LAN candidate: 192.168.3.0/24
Network profile: Private
Remote user: kemi-test
Remote root: D:\KEMI-Test
Work directory: D:\KEMI-Test\work
Remote TEMP/TMP: D:\KEMI-Test\tmp
OpenSSH: installed
sshd: Running
TCP 22: Listening
PowerShell: 7.6.5
D drive free: 185.8 GiB
```

Windows 端当前计划仍包含三项动作：

```text
windows.firewall.apply_lan_rule
windows.local_user.create_standard
windows.local_user.set_authorized_keys
```

因此 Mac 不应在 Windows 端 apply 和 enroll 成功前反复尝试登录。

host key 指纹已由 Windows 管理员只读核验，并通过 `export_onboarding` 返回。Mac 首次连接仍必须逐字核对，禁止自动接受变化后的指纹。

## 2. 调用边界

VibeKits MCP 桥接只监听各设备自己的 `127.0.0.1`，随机 bearer token 只交给该设备上由 VibeKits 启动的 Harness 子进程。

- Mac 智能体调用 Mac 本机 VibeKits MCP；
- Windows 智能体调用 Windows 本机 VibeKits MCP；
- Mac 与 Windows 之间的测试连接使用 SSH/SFTP；
- 禁止把 VibeKits MCP HTTP 端口暴露到局域网；
- 禁止把 bearer token、Mac 私钥或 Windows 密码复制到另一台设备。

Mac 端以 MCP `tools/list` 返回值为准，不根据文档假定工具可执行。

### 2.1 Codex MCP 注册

VibeKits 启动 Harness 后，会发布当前用户专属、权限为 `0600` 的短期连接文件：

```text
~/Library/Application Support/Vibekits/Mcp/tool-bridge.json
```

Mac 的 `~/.codex/config.toml` 使用固定 stdio 启动命令：

```toml
[mcp_servers.vibekits]
command = "/usr/bin/env"
args = ["node", "/绝对路径/vibekits/native/harness/vibekits-codex-mcp.mjs"]
startup_timeout_sec = 30
```

把脚本路径替换为 Mac 上 VibeKits 仓库的真实绝对路径。先启动 VibeKits App，再重启 Codex；无需进入 Harness 页面。stdio 启动器自动读取 connection file，不要把 token 写入 `config.toml`。脚本只依赖 Node 标准库；Node 不在 PATH 时把 `command` 改为 Node 的绝对路径。写入和设备控制工具会回到 VibeKits 窗口逐次请求“允许一次”，用户未批准时不会执行。

## 3. 一次性 Windows 端准备

这一阶段在 Windows 本机 VibeKits/Harness 执行。

### 3.1 检查 helper

调用：

```json
{
  "name": "vibekits.windows_node.helper_status",
  "arguments": {}
}
```

继续条件：

```text
available=true
signatureValid=true
manifestMatch=true
protocolVersion 与 App 一致
```

任一条件不成立时停止 Windows 写入，不允许改用任意管理员 shell 绕过。

### 3.2 体检与计划

```json
{
  "name": "vibekits.windows_node.inspect",
  "arguments": {"rootPath": "D:\\KEMI-Test"}
}
```

保存返回的 `inspectionId`，随后调用：

```json
{
  "name": "vibekits.windows_node.plan",
  "arguments": {"inspectionId": "<inspectionId>"}
}
```

保存 `planId`、`digest`、`actions`、`rollbackId` 和 `expiresAt`。计划过期或系统状态变化后重新 inspect，不复用旧 ID。

### 3.3 用户审批并应用

```json
{
  "name": "vibekits.windows_node.apply",
  "arguments": {
    "planId": "<planId>",
    "planDigest": "<digest>",
    "approvedActionIds": [
      "windows.firewall.apply_lan_rule",
      "windows.local_user.create_standard"
    ]
  }
}
```

每次调用必须由 Windows 用户确认并接受 UAC。完成后使用返回的重检报告确认：

- `kemi-test` 存在且不是 Administrators 成员；
- TCP 22 规则仅允许 `192.168.3.0/24` 或更窄范围；
- Profile 仅 Private；
- `D:\KEMI-Test` 及目录树存在且 ACL 合格。

公钥动作应在收到 Mac 公钥后单独审批，不向计划中填入私钥。

## 4. Mac 端生成独立身份

这一阶段在准备接入的每台 Mac 本机执行。每台 Mac 必须使用不同 `deviceLabel`。

先调用 MCP `tools/list`，确认存在：

```text
vibekits.windows_node.ensure_client_identity
vibekits.windows_node.verify
```

随后调用：

```json
{
  "name": "vibekits.windows_node.ensure_client_identity",
  "arguments": {
    "deviceLabel": "mac-<stable-device-name>",
    "algorithm": "ed25519",
    "rotate": false
  }
}
```

Mac 端只保留以下可传递字段：

```text
deviceIdentityId
deviceLabel
algorithm
publicKey
publicKeyFingerprint
credentialReference
createdAt
```

规则：

- 私钥必须留在该 Mac 的 Keychain/受保护文件中；
- 不把私钥发送给用户、Windows、Harness 日志、GitHub 或另一台 Mac；
- 默认 `rotate=false`，重复运行应复用现有身份；
- 只有公钥可以交给 Windows 端登记。

## 5. Windows 端登记 Mac 公钥

Windows 端重新执行 inspect/plan，取得仍有效的 `planId` 和 `planDigest`，再调用：

```json
{
  "name": "vibekits.windows_node.enroll_device",
  "arguments": {
    "planId": "<fresh-planId>",
    "planDigest": "<fresh-planDigest>",
    "deviceLabel": "mac-<stable-device-name>",
    "publicKey": "<Mac ensure_client_identity 返回的 Ed25519 公钥>",
    "expiresAt": null
  }
}
```

成功条件：

- 返回唯一 `deviceId` 和与 Mac 一致的 `publicKeyFingerprint`；
- `status` 为 active 或 pendingVerification；
- 返回 `authorizedKeysDigest`；
- Windows 系统文件中不出现私钥；
- 重复指纹登记被拒绝。

登记后调用：

```json
{
  "name": "vibekits.windows_node.list_devices",
  "arguments": {}
}
```

核对目标设备存在，且返回值不包含完整公钥正文。

## 6. Windows 导出 onboarding

Windows 端先取得真实 SSH host key 指纹，然后调用：

```json
{
  "name": "vibekits.windows_node.export_onboarding",
  "arguments": {
    "host": "192.168.3.58",
    "port": 22,
    "hostKeyFingerprint": "SHA256:ikZ6NXAH3VFBGooSCeKW0JY9+h0cIcQOzib4fxmvz6M",
    "allowedCidr": "192.168.3.0/24"
  }
}
```

onboarding 可以发送给已登记的 Mac，但必须确认其中不含密码、Token、私钥或 bearer token。

## 7. Mac 端验证节点

Mac 导入 onboarding，使用 `credentialReference` 建立 SSH profile，并固定 onboarding 中的 host key 指纹。

先执行基础验证：

```json
{
  "name": "vibekits.windows_node.verify",
  "arguments": {
    "nodeProfileId": "<Mac 保存的 SSH profile ID>",
    "deviceIdentityId": "<ensure_client_identity 返回的 ID>",
    "checks": [
      "host_key",
      "public_key_login",
      "powershell",
      "working_directory",
      "temp_directory",
      "sftp_sha256",
      "firewall_scope"
    ],
    "enableLargeTransfer": false,
    "enableDisconnectTest": false
  }
}
```

基础验证通过后，经用户单独确认再执行压力验证：

```json
{
  "name": "vibekits.windows_node.verify",
  "arguments": {
    "nodeProfileId": "<Mac 保存的 SSH profile ID>",
    "deviceIdentityId": "<deviceIdentityId>",
    "checks": [
      "host_key",
      "public_key_login",
      "sftp_sha256",
      "large_transfer_cancel",
      "disconnect_retry"
    ],
    "enableLargeTransfer": true,
    "enableDisconnectTest": true
  }
}
```

成功判定：

- `overallStatus=pass`；
- host key 与 onboarding 完全一致；
- `pwsh -NoProfile` 成功；
- cwd 和 TEMP/TMP 位于 `D:\KEMI-Test`；
- SFTP 上传、远端和下载 SHA-256 一致；
- 1 GiB 取消后没有临时残留；
- 断网明确失败，恢复后可重试且仍为同一 host key；
- 返回 `NodeVerificationReport` 和 `WorkflowArtifact`。

## 8. 后续新增 Mac

每新增一台 Mac，只重复以下步骤：

```text
Mac ensure_client_identity
→ Windows enroll_device
→ Windows export_onboarding
→ Mac verify
```

不得复制旧 Mac 私钥。Windows 端不需要重新安装 OpenSSH，也不需要重建节点。

## 9. 单设备撤销

Windows 端先调用 `list_devices` 获取最新设备状态摘要，再由用户审批：

```json
{
  "name": "vibekits.windows_node.revoke_device",
  "arguments": {
    "deviceId": "<目标设备 ID>",
    "expectedRegistryDigest": "<最新设备登记摘要>"
  }
}
```

撤销后：

- 被撤销 Mac 登录必须失败；
- 其他 active Mac 必须继续成功；
- 不删除设备历史；
- 不修改其他设备公钥。

## 10. 错误处理

统一返回：

```json
{"ok":true,"cancelled":false,"data":{}}
```

处理规则：

- `cancelled=true`：用户拒绝；停止，不重试或绕过；
- `ok=false`：显示脱敏 `error`，按错误要求重新 list/inspect/plan；
- helper `available=false`：停止 Windows 写入；
- 计划过期、摘要或状态漂移：重新 inspect/plan；
- host key 不一致：立即阻断，禁止自动接受；
- 重复公钥：复用已有 device ID，不生成共享密钥；
- 网络失败：保留身份和登记，不重复生成 key，恢复后重试 verify；
- 工具未出现在 `tools/list`：报告该设备/版本缺少该可执行接口，不使用 shell 替代。

## 11. Mac 端最终交付结果

Mac 智能体完成后只需返回：

```text
deviceLabel
publicKeyFingerprint
Windows host / port
hostKeyFingerprint
NodeVerificationReport ID
WorkflowArtifact ID
overallStatus
```

不得返回私钥、密码、Token、完整公钥正文或测试文件正文。
