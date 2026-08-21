# Mac → Windows 测试节点 Onboarding

生成日期：2026-08-21

## 连接事实

```text
Host alias: vibekits-windows-node
HostName: 192.168.3.58
Port: 22
User: kemi-test
Allowed LAN: 192.168.3.0/24
Host key type: ED25519
Host key fingerprint: SHA256:ikZ6NXAH3VFBGooSCeKW0JY9+h0cIcQOzib4fxmvz6M
Remote root: D:\KEMI-Test
Remote work: D:\KEMI-Test\work
Remote TEMP/TMP: D:\KEMI-Test\tmp
```

## SSH config

在该 Mac 已生成并登记独立 Ed25519 身份后使用：

```sshconfig
Host vibekits-windows-node
  HostName 192.168.3.58
  Port 22
  User kemi-test
  IdentitiesOnly yes
  StrictHostKeyChecking yes
```

私钥路径由 Mac 本机 VibeKits 的 `credentialReference` 管理，不写入此文件。

## Mac 端调用顺序

1. MCP `tools/list` 确认 `windows_node.ensure_client_identity` 和 `windows_node.verify` 可执行。
2. 调用 `windows_node.ensure_client_identity`，`algorithm=ed25519`、`rotate=false`。
3. 只把返回的 `publicKey`、`publicKeyFingerprint` 和 `deviceLabel`交给 Windows 端登记。
4. Windows 完成 `enroll_device` 并返回相同指纹后，再进行首次连接。
5. 首次连接必须核对上述 ED25519 host key 指纹。
6. 先执行基础 verify；用户另行确认后再执行 1 GiB 取消和断网测试。

## 当前门禁

Windows 的 OpenSSH、sshd、TCP 22、Private 网络、D 盘目录和受限防火墙规则已经就绪。`kemi-test` 当前故意保持禁用，设备列表为 0；收到并登记第一台 Mac 公钥后才能启用账户和开始登录验证。

禁止共享另一台设备的私钥，禁止关闭 host key 校验，禁止把 VibeKits MCP loopback token 暴露到局域网。
