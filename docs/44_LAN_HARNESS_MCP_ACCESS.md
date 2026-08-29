# 局域网 Harness MCP 跨设备调用

## 调用链

```text
局域网智能体
  → SSH（主机IP、固定host key、每设备独立Ed25519公钥）
  → start_vibekits_mcp_ssh.ps1（私网来源门禁）
  → stdio MCP
  → APP本机127.0.0.1随机Token桥接
  → Vibekits Harness工具、审批和审计
```

不把 APP 的 HTTP bridge、连接文件或 Bearer Token 暴露到局域网。远端只有同时满足以下条件才能调用：

1. 知道 Harness 所在电脑的私网 IPv4 和 SSH 端口。
2. 核对过服务器 host key 指纹。
3. 使用该设备独立的 Ed25519 私钥；公钥已由主机用户明确授权。
4. SSH `authorized_keys` 使用 `restrict` 和强制 MCP 命令，不能获得通用远程 Shell。
5. 控制、写入和破坏性 MCP 仍需 VibeKits APP 按当前权限模式批准并记录审计。

## 主机授权

为每个远端智能体单独登记公钥，不复用私钥。授权行应采用以下结构，其中 Release 路径必须替换为真实 D 盘路径：

```text
restrict,command="powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File D:\...\tools\harness\start_vibekits_mcp_ssh.ps1 -DeviceId mac-agent-01" ssh-ed25519 <PUBLIC_KEY> vibekits:mac-agent-01
```

撤销时只删除或禁用对应公钥，不影响其他设备。禁止移除 `restrict`、改成任意 PowerShell 或共享另一台设备的私钥。

## 远端智能体 MCP 配置

远端 MCP 客户端以 SSH 本身作为 stdio server，例如：

```json
{
  "mcpServers": {
    "vibekits-lan": {
      "command": "ssh",
      "args": ["-T", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "vibekits-windows-node"]
    }
  }
}
```

SSH alias 中固定 `HostName`、`User`、`IdentityFile`、`IdentitiesOnly yes` 和 `HostKeyAlias`/known_hosts。连接建立后使用标准 `initialize → tools/list → tools/call`，工具参数与本机 Harness 完全一致。

## 授权层次

- 连接授权：每设备 Ed25519 公钥，决定谁能进入 MCP。
- 能力授权：MCP 工具目录和平台门禁，决定当前可发现、可执行什么。
- 控制授权：APP 的 Harness 权限模式和工具审批，决定本次写入/控制是否允许。
- 审计：保存设备 ID、工具、目标、结果和时间；不保存私钥、Token 或飞书 Secret。

当前脚本拒绝非 SSH 调用、非私网 IPv4 和无效设备 ID。跨设备正式验收仍必须从另一台真实局域网设备执行，localhost 不能替代。
