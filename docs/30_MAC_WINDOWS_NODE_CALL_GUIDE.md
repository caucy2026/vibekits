# VibeKits：Windows 节点供 Mac 远程仿真的完整搭建手册

版本：2.0
更新日期：2026-08-22
适用范围：把一台新的 Windows 10/11 x64 电脑配置成仅限可信局域网、供一台或多台 Mac 通过 SSH/SFTP 使用的 VibeKits/KEMI 远程仿真节点。

## 1. 完成标准

只有同时满足以下条件，才能告诉 Mac“节点已经可以使用”：

1. Windows 使用专用标准账户，不属于 Administrators。
2. OpenSSH Server 自动启动，TCP 22 仅允许可信 Private 局域网。
3. 每台 Mac 使用不同的 Ed25519 私钥；Windows 只保存公钥。
4. Mac 核对并固定 Windows ED25519 host key，不自动接受变化。
5. Windows 在通知 Mac 前，已经用一把临时本地 Ed25519 密钥完成 `127.0.0.1:22` 公钥登录。
6. Mac 使用目标公钥完成真实局域网登录。
7. `pwsh -NoProfile` 可用，工作目录与 TEMP/TMP 均位于 `D:\KEMI-Test`。
8. 小文件 SFTP 上传、远端、下载三次 SHA-256 一致。
9. VibeKits MCP 只监听各设备本机 `127.0.0.1`，不向局域网暴露 token 或 HTTP bridge。

“TCP 22 可达”或“sshd 正在运行”都不等于完成。

## 2. 拓扑与安全边界

```text
Mac / Codex / VibeKits
        |
        | SSH + SFTP，TCP 22，独立 Ed25519 身份
        v
Windows 标准账户 kemi-test
        |
        +-- D:\KEMI-Test\inbox
        +-- D:\KEMI-Test\work
        +-- D:\KEMI-Test\tmp
        +-- D:\KEMI-Test\results
```

- Mac 与 Windows 之间只使用 SSH/SFTP。
- 不开放 SMB 445、WinRM 5985、公网 SSH 或路由器端口映射。
- 不共享 Windows 密码、Mac 私钥、VibeKits bearer token 或 connection file。
- 不使用 `StrictHostKeyChecking=no`。
- 项目、安装包、缓存、日志和测试结果只进入 `D:\KEMI-Test`。
- SSH 非交互会话适合命令、安装器、SFTP、日志和性能探针；真实点击、拖放、窗口截图仍需要运行在 Windows 交互桌面的测试代理。

## 3. 先填写节点参数

在 Windows 管理员 PowerShell 中填写实际值：

```powershell
$NodeUser = 'kemi-test'
$NodeRoot = 'D:\KEMI-Test'
$AllowedCidr = '192.168.3.0/24'  # 必须改为实际可信网段，/24 或更窄
$FirewallRule = 'VIBEKITS-TEST-NODE-SSH-LAN'
```

记录 Windows 的局域网 IPv4：

```powershell
Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' } |
  Select-Object InterfaceAlias,IPAddress,PrefixLength
```

目标网络必须是 Private：

```powershell
Get-NetConnectionProfile | Select-Object InterfaceAlias,NetworkCategory,IPv4Connectivity
```

不要根据示例盲用 `192.168.3.0/24`。

## 4. 安装并启动基础组件

在 Windows 管理员 PowerShell 中执行：

```powershell
$capability = Get-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0'
if ($capability.State -ne 'Installed') {
  Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0'
}

Start-Service sshd
Set-Service sshd -StartupType Automatic

Get-Service sshd | Select-Object Name,Status,StartType
Get-NetTCPConnection -LocalPort 22 -State Listen |
  Select-Object LocalAddress,LocalPort,OwningProcess
```

安装 PowerShell 7 x64 后验证：

```powershell
pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
```

VibeKits 产品需要的 WebView2、VC++ Runtime 或其他运行时按 Release 清单安装；SSH 节点本身不应靠系统里碰巧存在的业务依赖掩盖产品打包遗漏。

## 5. 创建专用标准账户

不要复用个人微软账户，也不要把测试账户加入 Administrators。

```powershell
$existing = Get-LocalUser -Name $NodeUser -ErrorAction SilentlyContinue
if (-not $existing) {
  $SecurePassword = Read-Host "为 $NodeUser 输入本机恢复密码（不要发送给 Mac/Codex）" -AsSecureString
  New-LocalUser -Name $NodeUser -Password $SecurePassword `
    -AccountNeverExpires -UserMayNotChangePassword:$false `
    -Description 'VibeKits LAN test node standard account'
}

Enable-LocalUser -Name $NodeUser

$isAdmin = @(Get-LocalGroupMember -Group 'Administrators' |
  Where-Object { $_.Name -match "\\$([regex]::Escape($NodeUser))$" }).Count -gt 0
if ($isAdmin) { throw "$NodeUser must not be an Administrator" }
```

密码只用于本机恢复；至少一台 Mac 公钥登录成功前，不要删除恢复路径。外部验收成功后可关闭 SSH 密码认证，见第 13 节。

## 6. 创建 D 盘目录并收紧 ACL

```powershell
if (-not (Test-Path 'D:\')) { throw 'D: drive is required' }

@(
  $NodeRoot,
  "$NodeRoot\inbox",
  "$NodeRoot\inbox\release",
  "$NodeRoot\inbox\test-docs",
  "$NodeRoot\work",
  "$NodeRoot\app",
  "$NodeRoot\tools",
  "$NodeRoot\agent",
  "$NodeRoot\cache",
  "$NodeRoot\tmp",
  "$NodeRoot\results",
  "$NodeRoot\results\logs",
  "$NodeRoot\results\screenshots",
  "$NodeRoot\results\dumps",
  "$NodeRoot\results\traces"
) | ForEach-Object { New-Item -ItemType Directory -Force -Path $_ | Out-Null }

$machineUser = "$env:COMPUTERNAME\$NodeUser"
icacls $NodeRoot /inheritance:r | Out-Null
icacls $NodeRoot /grant:r `
  "${machineUser}:(OI)(CI)M" `
  'Administrators:(OI)(CI)F' `
  'SYSTEM:(OI)(CI)F' | Out-Null
```

检查结果中不得出现 Everyone 或普通 Users 的写权限：

```powershell
icacls $NodeRoot
```

每个远程任务入口都设置进程级环境变量，不修改系统全局 TEMP/TMP：

```powershell
$env:TEMP = 'D:\KEMI-Test\tmp'
$env:TMP = 'D:\KEMI-Test\tmp'
$env:KEMI_REMOTE_ROOT = 'D:\KEMI-Test'
Set-Location 'D:\KEMI-Test\work'
```

## 7. 把防火墙限制到可信局域网

OpenSSH 安装产生的默认宽泛规则应禁用；新规则只允许 Private 网络和指定 CIDR：

```powershell
Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue |
  Set-NetFirewallRule -Enabled False

Get-NetFirewallRule -Name $FirewallRule -ErrorAction SilentlyContinue |
  Remove-NetFirewallRule

New-NetFirewallRule `
  -Name $FirewallRule `
  -DisplayName 'VibeKits SSH from trusted LAN' `
  -Direction Inbound `
  -Action Allow `
  -Protocol TCP `
  -LocalPort 22 `
  -RemoteAddress $AllowedCidr `
  -Profile Private
```

只读核验：

```powershell
Get-NetFirewallRule -Name $FirewallRule |
  Select-Object Name,Enabled,Direction,Action,Profile
Get-NetFirewallRule -Name $FirewallRule | Get-NetFirewallPortFilter
Get-NetFirewallRule -Name $FirewallRule | Get-NetFirewallAddressFilter
```

## 8. 固定标准用户的 authorized_keys 路径

### 8.1 为什么必须显式固定

不要假定 `C:\Users\<user>` 一定等于 Windows 注册的 `%USERPROFILE%`。如果管理员先手工创建了同名目录，Windows 第一次登录时可能注册为：

```text
C:\Users\kemi-test.COMPUTERNAME
```

而公钥仍在：

```text
C:\Users\kemi-test\.ssh\authorized_keys
```

此时网络、host key、账户令牌都正常，但 sshd 会在 `preauth` 阶段拒绝正确公钥。为避免新机器重复踩坑，本手册固定绝对路径。

### 8.2 写入 sshd 配置

先备份：

```powershell
$SshdConfig = 'C:\ProgramData\ssh\sshd_config'
$SshdBackup = 'C:\ProgramData\ssh\sshd_config.vibekits-pre-node.bak'
if (-not (Test-Path $SshdBackup)) {
  Copy-Item $SshdConfig $SshdBackup
}
```

检查是否已经存在标记：

```powershell
$Marker = "# VibeKits $NodeUser absolute authorized_keys"
$Current = [IO.File]::ReadAllText($SshdConfig)
```

若不存在，追加以下块。`Match all` 用于退出前一个 Match 块：

```powershell
if (-not $Current.Contains($Marker)) {
  $Block = @"

Match all
$Marker
Match User $NodeUser
    AuthorizedKeysFile C:/Users/$NodeUser/.ssh/authorized_keys
Match all
"@
  [IO.File]::AppendAllText($SshdConfig, $Block, [Text.UTF8Encoding]::new($false))
}

& "$env:WINDIR\System32\OpenSSH\sshd.exe" -t
if ($LASTEXITCODE -ne 0) {
  Copy-Item $SshdBackup $SshdConfig -Force
  throw 'sshd_config validation failed; backup restored'
}

Restart-Service sshd
```

不要把 `kemi-test` 加入 Administrators。管理员账户会命中 Windows 默认的 `administrators_authorized_keys` 分支，改变授权文件位置。

## 9. Mac 生成独立身份并提交公钥

每台 Mac 使用不同的文件名和 `deviceLabel`：

```bash
DEVICE_LABEL="mac-$(scutil --get LocalHostName)"
KEY="$HOME/.ssh/vibekits_windows_node_ed25519"

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
ssh-keygen -t ed25519 -a 100 -f "$KEY" -C "$DEVICE_LABEL"
ssh-keygen -lf "$KEY.pub" -E sha256
```

Mac 只把以下三项交给 Windows：

```text
deviceLabel
publicKey（.pub 文件的一整行）
publicKeyFingerprint（SHA256:...）
```

禁止发送无 `.pub` 后缀的私钥文件。

## 10. Windows 登记 Mac 公钥

### 10.1 优先使用 VibeKits 工具

先执行 MCP `tools/list`。只有 `vibekits.windows_node.enroll_device` 出现在 executable catalog 时才能调用；未出现时不得伪称工具已完成。

当前版本若只有 `inspect`、`plan`、`list_devices`、`export_onboarding` 等只读能力，使用下面的管理员引导方式。

### 10.2 管理员引导方式

把 Mac 返回的值填入变量：

```powershell
$DeviceLabel = 'mac-example'
$ExpectedFingerprint = 'SHA256:替换为Mac返回指纹'
$PublicKey = 'ssh-ed25519 AAAA... mac-example'
```

先独立核验，不直接相信聊天文本中的指纹：

```powershell
$VerifyFile = Join-Path $env:TEMP 'vibekits-enroll-key.pub'
[IO.File]::WriteAllText($VerifyFile, $PublicKey + "`n", [Text.UTF8Encoding]::new($false))
$Actual = (& ssh-keygen -lf $VerifyFile -E sha256) -join ' '
Remove-Item -LiteralPath $VerifyFile -Force
if ($Actual -notmatch [regex]::Escape($ExpectedFingerprint)) {
  throw "Public key fingerprint mismatch: $Actual"
}
```

建立授权目录。标准用户文件最终只保留该用户和 SYSTEM；写入期间如需管理员临时访问，完成后必须移除：

```powershell
$ProfileRoot = "C:\Users\$NodeUser"
$SshDir = Join-Path $ProfileRoot '.ssh'
$AuthorizedKeys = Join-Path $SshDir 'authorized_keys'
$UserSid = (Get-LocalUser -Name $NodeUser).SID.Value

New-Item -ItemType Directory -Path $SshDir -Force | Out-Null
takeown /F $SshDir /A /R /D Y | Out-Null
icacls $SshDir /inheritance:r | Out-Null
icacls $SshDir /grant:r `
  "*$UserSid`:(OI)(CI)F" `
  'SYSTEM:(OI)(CI)F' `
  'Administrators:(OI)(CI)F' | Out-Null
```

首次设备可写一行；新增设备必须保留所有仍 active 的已有行：

```powershell
$Normalized = ($PublicKey -split '\s+')[0..1] -join ' '
$Line = "$Normalized vibekits:$DeviceLabel"
$Existing = if (Test-Path $AuthorizedKeys) {
  @(Get-Content $AuthorizedKeys | Where-Object { $_.Trim() })
} else { @() }

if ($Existing -notcontains $Line) { $Existing += $Line }
[IO.File]::WriteAllText(
  $AuthorizedKeys,
  (($Existing -join "`n") + "`n"),
  [Text.UTF8Encoding]::new($false)
)

icacls $AuthorizedKeys /inheritance:r | Out-Null
icacls $AuthorizedKeys /grant:r `
  "*$UserSid`:F" `
  'SYSTEM:F' | Out-Null
icacls $AuthorizedKeys /setowner "*$UserSid" | Out-Null
icacls $SshDir /grant:r "*$UserSid`:(OI)(CI)F" 'SYSTEM:(OI)(CI)F' | Out-Null
icacls $SshDir /setowner "*$UserSid" | Out-Null
icacls $AuthorizedKeys /remove:g 'Administrators' | Out-Null
icacls $SshDir /remove:g 'Administrators' | Out-Null
```

文件要求：UTF-8 无 BOM 或 ASCII、每把公钥一整行、不得包含私钥、不得让 Everyone/Users/其他普通账户写入。

## 11. Windows 必须先做本机轻量验收

这是通知 Mac 之前的强制步骤。不要用目标 Mac 私钥；生成一把临时本地密钥，只执行 `whoami`。

仓库提供轻量脚本：

```powershell
Set-Location D:\vibecode\vibekits
.\tool\windows_node_local_ssh_smoke.ps1 `
  -UserName 'kemi-test' `
  -AuthorizedKeysPath 'C:\Users\kemi-test\.ssh\authorized_keys' `
  -ExpectedHostKeyFingerprint 'SHA256:替换为本机host-key指纹'
```

脚本必须在管理员 PowerShell 中运行。其操作原则：

1. 生成临时 Ed25519 密钥。
2. 把临时公钥作为额外一行加入 `authorized_keys`。
3. 扫描并核对本机 host key。
4. 使用 `127.0.0.1:22`、`BatchMode=yes`、`IdentitiesOnly=yes` 登录。
5. `whoami` 必须返回 `<computer>\kemi-test`。
6. 无论成功失败，都删除临时私钥和临时授权行，只保留真实 Mac 公钥。

成功日志应包含：

```text
Accepted publickey for kemi-test from 127.0.0.1
```

只读查看：

```powershell
Get-WinEvent -LogName 'OpenSSH/Operational' -MaxEvents 30 |
  Where-Object { $_.Message -match 'Accepted publickey|kemi-test|Server listening' } |
  Select-Object TimeCreated,Message
```

如果本机测试失败，不要让 Mac 反复测试。先在 Windows 修复授权路径、ACL、账户或 sshd 配置。

## 12. 导出 onboarding

Windows 取得真实 host key 指纹：

```powershell
ssh-keygen -lf 'C:\ProgramData\ssh\ssh_host_ed25519_key.pub' -E sha256
```

交给 Mac 的 onboarding 只包含：

```text
HostName: <Windows LAN IPv4>
Port: 22
User: kemi-test
Allowed CIDR: <可信网段>
Host key type: ED25519
Host key fingerprint: SHA256:...
Remote root: D:\KEMI-Test
Remote work: D:\KEMI-Test\work
Remote TEMP/TMP: D:\KEMI-Test\tmp
```

如果 VibeKits `windows_node.export_onboarding` 可执行，可用它生成同样的不含秘密的资料。不得发送 VibeKits loopback endpoint、token 或 Windows 密码。

## 13. Mac 固定 host key 并连接

先扫描到临时文件：

```bash
WINDOWS_HOST="192.168.3.58"  # 替换
ssh-keyscan -T 5 -t ed25519 -p 22 "$WINDOWS_HOST" > /tmp/vibekits-windows.hostkey
ssh-keygen -lf /tmp/vibekits-windows.hostkey -E sha256
```

只有指纹与 Windows onboarding 逐字一致时才写入：

```bash
cat /tmp/vibekits-windows.hostkey >> "$HOME/.ssh/known_hosts"
chmod 600 "$HOME/.ssh/known_hosts"
rm /tmp/vibekits-windows.hostkey
```

写入 `~/.ssh/config`：

```sshconfig
Host vibekits-windows-node
  HostName 192.168.3.58
  Port 22
  User kemi-test
  IdentityFile ~/.ssh/vibekits_windows_node_ed25519
  IdentitiesOnly yes
  BatchMode yes
  StrictHostKeyChecking yes
```

首次连接只运行：

```bash
ssh -v vibekits-windows-node whoami
```

必须看到目标公钥被服务器接受；不能让 SSH 自动轮询其他部署密钥来混淆结果。

## 14. PowerShell 与 D 盘验证

为避免 Bash/PowerShell 引号冲突，Mac 使用 UTF-16LE EncodedCommand：

```bash
REMOTE_PS=$(cat <<'POWERSHELL'
$env:TEMP = 'D:\KEMI-Test\tmp'
$env:TMP = 'D:\KEMI-Test\tmp'
$env:KEMI_REMOTE_ROOT = 'D:\KEMI-Test'
Set-Location 'D:\KEMI-Test\work'
[pscustomobject]@{
  User = $env:USERNAME
  Pwd = (Get-Location).Path
  Temp = $env:TEMP
  Pwsh = $PSVersionTable.PSVersion.ToString()
} | ConvertTo-Json -Compress
POWERSHELL
)

ENCODED=$(printf '%s' "$REMOTE_PS" | iconv -f UTF-8 -t UTF-16LE | base64)
ssh vibekits-windows-node "pwsh -NoProfile -EncodedCommand $ENCODED"
```

成功输出必须满足：

- `User=kemi-test`；
- `Pwd=D:\KEMI-Test\work`；
- `Temp=D:\KEMI-Test\tmp`；
- `Pwsh` 有版本号。

## 15. 小文件 SFTP SHA-256 闭环

基础认证通过后再做，不先上传大型安装器：

```bash
RUN_ID="smoke-$(date +%Y%m%d-%H%M%S)"
LOCAL_FILE="$(mktemp)"
DOWN_FILE="$(mktemp)"
dd if=/dev/urandom of="$LOCAL_FILE" bs=1024 count=64 status=none
LOCAL_SHA=$(shasum -a 256 "$LOCAL_FILE" | awk '{print $1}')

ssh vibekits-windows-node "pwsh -NoProfile -Command New-Item -ItemType Directory -Force -Path D:\\KEMI-Test\\work\\$RUN_ID"
sftp -b - vibekits-windows-node <<SFTP
put "$LOCAL_FILE" /D:/KEMI-Test/work/$RUN_ID/smoke.bin
get /D:/KEMI-Test/work/$RUN_ID/smoke.bin "$DOWN_FILE"
SFTP

DOWN_SHA=$(shasum -a 256 "$DOWN_FILE" | awk '{print $1}')
echo "local=$LOCAL_SHA downloaded=$DOWN_SHA"
```

再让 Windows 对远端文件执行 `Get-FileHash -Algorithm SHA256`。三者必须一致，然后仅删除本轮 `$RUN_ID` 目录和 Mac 临时文件。

## 16. 首台 Mac 成功后关闭远程密码认证

必须先保留本机恢复能力，并确认至少一台外部 Mac 公钥登录成功。然后在 `sshd_config` 的全局区域设置以下值；它们必须位于第一个 `Match` 块之前：

```text
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
```

执行：

```powershell
& "$env:WINDIR\System32\OpenSSH\sshd.exe" -t
if ($LASTEXITCODE -ne 0) { throw 'sshd_config validation failed' }
Restart-Service sshd
```

再次确认已登记 Mac 仍可登录，未登记密钥被拒绝。

## 17. 多台 Mac 与撤销

新增 Mac 不重装 Windows 节点，只重复：

```text
新 Mac 生成独立 Ed25519
→ Windows 核对指纹并新增一行公钥
→ Windows 本机临时密钥轻量验收
→ 新 Mac 固定 host key
→ 新 Mac SSH + PowerShell + 小文件 SFTP 验收
```

撤销设备时按设备标签和指纹删除唯一对应行，不能重写或删除其他 active 设备。撤销后证明：

- 被撤销 Mac 登录失败；
- 其他 active Mac 继续成功；
- Windows host key 未变化。

不得复制旧 Mac 私钥给新 Mac。

## 18. VibeKits 与 Codex 的正确边界

VibeKits App 可以提供只读体检、计划、设备摘要、onboarding 和本机 MCP。以 MCP `tools/list` 为唯一事实：未出现的 `apply/enroll_device/revoke_device/verify/ensure_client_identity` 不得假装可调用。

VibeKits MCP connection file 仅供同一台电脑使用：

```text
Windows: %LOCALAPPDATA%\Vibekits\Mcp\tool-bridge.json
macOS:   ~/Library/Application Support/Vibekits/Mcp/tool-bridge.json
```

Mac 不连接 Windows 的 loopback MCP HTTP 地址。跨机仿真始终走 SSH/SFTP。

Windows Codex 的 stdio 注册可使用仓库脚本：

```toml
[mcp_servers.vibekits]
command = "powershell.exe"
args = ["-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", "D:\\vibecode\\vibekits\\tool\\start_vibekits_mcp.ps1"]
startup_timeout_sec = 30
```

Mac 本机安装并启动 VibeKits 时可使用：

```toml
[mcp_servers.vibekits]
command = "/usr/bin/env"
args = ["node", "/绝对路径/vibekits/native/harness/vibekits-codex-mcp.mjs"]
startup_timeout_sec = 30
```

保存配置后新建 Codex 任务验证；已存在的旧任务可能保留创建时的工具清单。

## 19. 高效故障定位顺序

### TCP 22 不通

只检查：Windows IP、Private 网络、sshd、监听端口、防火墙 CIDR。不要修改公钥。

### host key 正确，但认证前连接被重置

检查账户是否禁用、sshd 是否能生成账户令牌、Windows 安全日志 4624/4625。

### 正确公钥仍 Permission denied

按顺序检查，不让 Mac 反复试：

1. Mac `Offering public key` 指纹是否等于已登记指纹；
2. `sshd -T` 是否启用 publickey；
3. 标准账户是否误入 Administrators；
4. `AuthorizedKeysFile` 是否为本手册的绝对路径；
5. 文件是否 UTF-8 无 BOM、一行一把 Ed25519；
6. `.ssh` 与文件是否只允许用户和 SYSTEM；
7. Windows 先用临时本地密钥登录 `127.0.0.1`；
8. 只有本机成功后才让 Mac 再试一次。

按 Mac 提供的精确时间读取：

```powershell
Get-WinEvent -LogName 'OpenSSH/Operational' -MaxEvents 100 |
  Select-Object TimeCreated,Id,LevelDisplayName,Message
```

`Connection closed ... [preauth]` 只说明认证未完成，不说明 Mac 用错密钥。`Accepted publickey` 才是服务器接受证据。

### 已 Accepted publickey，但命令失败

检查默认 shell、PowerShell 7、引号编码、D 盘目录与 ACL；不要再改公钥。

### SSH 能用，但 UI 自动化失败

SSH 是非交互会话。真实窗口点击、拖放、DPI、截图和首帧计时必须由当前交互桌面中的签名测试代理执行。

## 20. 最终交付清单

Windows 维护者交给 Mac：

```text
Windows LAN host / port
专用标准用户名
Allowed CIDR
ED25519 host key fingerprint
目标 Mac public key fingerprint
Remote root/work/tmp/results
本机 publickey smoke PASS 证据时间
```

Mac 完成后返回：

```text
deviceLabel
publicKeyFingerprint
hostKeyFingerprint
SSH publickey login PASS
PowerShell/D盘 PASS
SFTP SHA-256 PASS
测试时间与必要的脱敏日志
```

不得返回私钥、密码、token、完整业务文件正文。

## 21. 当前已验证节点示例

以下仅用于对照，不得复制到不同网络后直接使用：

```text
Host: 192.168.3.58
Port: 22
User: kemi-test
Allowed CIDR: 192.168.3.0/24
Host key: SHA256:ikZ6NXAH3VFBGooSCeKW0JY9+h0cIcQOzib4fxmvz6M
Mac key: SHA256:hpYI+CFcXcCgdLNnllblFfemUcT+SpAk5m8uwFYh+ww
Remote root: D:\KEMI-Test
Windows local publickey smoke: PASS
```

新节点必须生成自己的 host key、IP、CIDR、账户 Profile 和设备公钥，不能复制上述身份数据。
