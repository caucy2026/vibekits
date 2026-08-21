# Windows 测试节点与 GitHub 受控备份

版本：1.0
日期：2026-08-21
来源：`VIBEKITS_WINDOWS_TEST_NODE_AND_GITHUB_BACKUP_TOOL_REQUIREMENTS.md`

## 1. 目标与边界

在现有 SSH/SFTP、GitHub 网络诊断、Git 工作区、ToolSpec、Harness MCP、系统凭据、Mihomo 和统一审计上形成三条任务链：

1. Windows 测试节点：只读体检 → 幂等计划 → UAC 窄权限执行 → 真机验证 → 精确回滚。
2. GitHub 网络：分层诊断 → 回环代理候选 → GitHub host-scoped 修复 → `ls-remote` 验证 → 失败自动恢复。
3. GitHub 备份：仓库预览 → 秘密/产物阻断 → 分离审批 commit/push → 远端 SHA 核验。

不新增一级导航，不实现另一套 SSH 客户端，不接受任意管理员脚本，不共享私钥，不记录密码/Token/私钥/CA 私钥，不开放公网 SSH/SMB/明文 WinRM，不提供 force push、删远端 ref 或改 tag。

## 2. Windows 节点合同

### NODE-001 只读体检

普通权限先返回可见结果，逐项给出 `pass/warning/blocked/unknown`，需要 UAC 的检查列入 `requiresElevation`。报告至少覆盖 Windows 版本、CPU/RAM/GPU/显示、D 盘空间、默认路由网卡与 CIDR、OpenSSH capability/服务/二进制/配置/主机密钥/监听/事件、防火墙、PowerShell 7、WebView2、VC++、电源、`D:\KEMI-Test`、ACL、专用账户、公钥指纹和最近验证时间。

### NODE-002 幂等计划

计划使用随机短期 ID、体检摘要和到期时间。每个 action 保存稳定 ID、当前/目标值、原因、风险、UAC/网络/重启、耗时、取消、依赖、停止边界和回滚。状态变化、摘要篡改或过期时拒绝执行。

### NODE-003 受限执行

主 App 保持普通权限。签名 helper 只接受版本化 JSON、nonce、摘要和预定义 action ID。首版白名单为 OpenSSH 安装/修复、sshd 配置/启用、LAN 防火墙、网络 Private、标准账户、公钥、D 盘 ACL、PowerShell、电源和 rollback；禁止任意 shell 文本。

### NODE-004～010 门禁

- 根路径固定为绝对 `D:\KEMI-Test`，D 盘缺失或剩余不足 30 GiB 阻断。
- 固定创建 `inbox/{release,test-docs}`、`work`、`app`、`tools`、`agent`、`cache`、`tmp`、`results/{logs,screenshots,dumps,traces}`；TEMP/TMP 仅作用于远端进程。
- OpenSSH 判定必须合并 capability、服务、文件版本、配置、host key ACL、TCP 22 和事件日志；安装超时取消后重新体检。
- 防火墙只允许用户确认的 RFC1918/ULA 私网，IPv4 最宽 `/24`，Profile 仅 Private；不做 UPnP/端口映射。
- 默认标准账户 `kemi-test`；至少一把公钥真实登录成功前不得切换 key-only。
- 每设备独立 Ed25519 公钥，支持重复拒绝、禁用、撤销；onboarding 不含秘密。SSH CA 私钥永不进入节点或 Harness。
- 完成验收必须由另一台设备校验 host key、公钥登录、`pwsh -NoProfile`、D 盘 cwd/TEMP、SFTP 双向 SHA-256、取消无残留和断网恢复。

## 3. GitHub 网络合同

### NET-001 分层诊断

分别报告：GCM 账号标签、DNS、TCP 443/22/SSH443、TLS/HTTPS、WinINet/WinHTTP/环境/Git 代理、受支持代理进程与监听端口、内置 MinGit `ls-remote`。结论区分未登录、直连失败但代理可用、代理运行但 Git 未使用、远端权限不足。

### NET-002/003 代理发现和修复

代理端口来自 Mihomo/Clash 进程、回环监听和已选配置，不假定 7890。候选只允许 loopback，分别验证 HTTPS 和 Git。默认只写：

```text
http.https://github.com.proxy=http://127.0.0.1:<port>
```

应用前保存旧值，随后真实 `ls-remote`；失败自动恢复。计划过期、摘要不一致或端口不再监听时拒绝应用。

### NET-004 系统代理

系统代理/TUN 尚未完成 WinINet、WinHTTP、PAC、绕过列表、TUN 和崩溃恢复前不得提供可执行入口。默认作用域始终是“仅 GitHub Git”。

## 4. Git 备份合同

### GIT-001 预览

只接受已选择的本地 Git 仓库和已存在 remote 名称，不接受 URL。返回根目录、分支、脱敏 remote、staged/unstaged/untracked、文件范围、大文件、构建产物、忽略风险、疑似秘密、代理/凭据/远端状态和目标 `backup/<device-or-project>/<date>`。

私钥、Token、`.env`、凭据、SSH key、证书私钥为 blocker。计划绑定仓库状态摘要、随机短期 ID、included paths、remote ID 和目标分支。

### GIT-002/003 写入与审批

- commit 只接受有效 preview ID、已预览文件集合和 message；不得越界 stage。
- push 使用独立审批，只接受计划生成的 commit SHA、remote ID 和目标分支。
- 禁止 force/force-with-lease、删除 ref、修改 tag 和绕过 hooks。
- push 后 `ls-remote` 核对 SHA；断网保留本地 commit并返回可重试状态，不重复 commit。
- 审计只记录摘要、数量、SHA 和 remote 标签，不记录正文或凭据。

## 5. ToolSpec 与 Harness

`remote_workspace`：`windows_node.inspect/plan/apply/verify/list_devices/enroll_device/revoke_device/export_onboarding/rollback`。

`github_diagnostics`：`github.diagnose/proxy_candidates/proxy_plan/proxy_apply/proxy_rollback`。

`git_workspace`：`git.inspect/compare_refs/create_local_branch/backup_preview/backup_commit/backup_push/verify_remote_ref`。

所有工具由 ToolSpec 单一注册；读取为 `readOnly`，配置/stage/commit 为 `writesData`，push 独立审批。每次调用进入模块日志，可关闭和删除。结果进入 `WorkflowArtifact`，最多推荐三个下一步。

## 6. 发布门禁

自动门禁覆盖 tools/list、一致性与幂等、计划篡改/过期、D 盘门禁、网络类别/CIDR、OpenSSH 矛盾状态、超时取消、公钥/ACL、key-only 登录门禁、代理发现/回滚、秘密扫描、commit/push 分离审批、禁止 force、日志脱敏、后台取消和资源释放。

真实门禁必须另外取得：Windows 管理员配置；两台 Mac 独立密钥连接和单设备撤销；1 GiB SFTP 取消与 50% 断网；双向 SHA-256；真实代理端口与 GitHub 私有仓库备份；截图、日志、哈希、远端 SHA 和节点报告。模拟测试不能替代。

## 7. 实施状态规则

- P0：节点体检、GitHub 分层诊断、结构化报告。
- P1：签名 UAC helper、plan/apply/rollback、单设备公钥。
- P2：多设备、onboarding、host-scoped 代理、受控 Git 备份。
- P3：外部 SSH CA 签发服务。
- P4：复用已验证 SSH/SFTP 编排业务提供的签名 KEMI 测试代理。

只有代码、自动测试、Windows Release、签名 helper、两台 Mac/一台 Windows 实证和一次私有仓库远端 SHA 验证全部存在时才可宣称完整完成；其余必须保持“待实证”。
