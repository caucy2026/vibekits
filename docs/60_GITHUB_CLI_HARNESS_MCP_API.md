# GitHub CLI 内置运行时与 Harness/MCP 接口

## 目标

VibeKits 把官方 GitHub CLI 作为 APP 私有运行时发布。Harness、本机 MCP 客户端和已经配对授权的 LMCP/2 局域网客户端调用同一组工具，不检查系统 `PATH`，也不要求用户安装 Homebrew、winget、apt 或独立 `gh`。

桌面支持范围：Windows x64、macOS Universal（x86_64/arm64）、Linux amd64/arm64。Android/iOS 不直接执行桌面二进制；移动端智能体应通过已授权的桌面 LMCP 节点调用。

## 动态发现

调用方每个新任务都应先执行 MCP `tools/list`，不得缓存猜测参数。VibeKits 工具 ID 到 MCP 名称的映射如下：

| 工具 ID | MCP 名称 | 风险 | 用途 |
| --- | --- | --- | --- |
| `vibekits.github.cli_inspect` | `github__cli_inspect` | `readOnly` | 检查内置版本、路径、平台和架构 |
| `vibekits.github.cli_auth_status` | `github__cli_auth_status` | `readOnly` | 检查 GitHub.com 或企业主机授权，不返回令牌 |
| `vibekits.github.cli_execute` | `github__cli_execute` | `controlsDevice` | 执行官方 `gh` 参数；可能写仓库、创建 PR、发布 Release 或触发工作流 |

局域网发现只表示“可见”，不表示“获准执行”。远程 `cli_execute` 必须经过 LMCP/2 配对、工具授权和 VibeKits 风险审批；拒绝、过期或工具目录已变更时应重新申请，调用方不得降级到 SSH shell 绕过。

## 接口参数

### `github__cli_inspect`

输入为 `{}`。成功结果包含 `available`、`executable`、`version`、`platform`、`architecture`、`upstream`、`license` 和 `bundled`。

### `github__cli_auth_status`

- `hostname`：可选字符串，例如 `github.com` 或企业 GitHub 主机；只接受主机名和可选端口。

### `github__cli_execute`

- `arguments`：必填字符串数组，1～128 项；每项最大 16384 字符。数组内容是 `gh` 后面的原生参数，不能传 shell 命令字符串。
- `workingDirectory`：可选、必须已存在的绝对目录。需要从本地仓库推断 owner/repo 时传入仓库目录；否则优先显式传 `--repo owner/repo`。
- `timeoutSeconds`：可选整数，5～3600，默认 300。超过时终止子进程并返回超时错误。

示例：

```json
{
  "arguments": ["pr", "list", "--repo", "owner/repo", "--json", "number,title,state"],
  "timeoutSeconds": 60
}
```

```json
{
  "arguments": ["api", "repos/owner/repo/actions/runs", "--jq", ".workflow_runs[:5] | map({id,status,conclusion})"]
}
```

调用方应优先使用 `--json`、`--jq` 或 `gh api` 获取稳定机器结果。返回结构固定包含 `ok`、`exitCode`、原始 `arguments`，以及有内容时的 `stdout`/`stderr`；输出超过 256 KiB 时保留首尾并标记截断。

## 凭据与非交互约束

- MCP 参数不得携带 `--with-token`、`--token` 或 `--client-secret`，也禁止执行 `gh auth token`。
- 运行时沿用官方 `gh` 的安全凭据存储和 `GH_TOKEN`/`GH_ENTERPRISE_TOKEN` 环境合同，但 VibeKits 不在结果或审计中回显令牌；常见 GitHub token 格式会二次脱敏。
- 子进程固定设置 `GH_PROMPT_DISABLED=1`、关闭 pager、更新提示和遥测；工具不会等待终端输入，也不会启动 shell。
- 首次登录属于用户交互，应在受信任设备上使用官方 OAuth/浏览器流程完成。外部智能体只能检查授权状态，不能把令牌通过 MCP 注入。

## 打包合同

版本固定为官方 `2.100.0`。准备脚本把临时文件和最终运行时都放在项目盘：

- Windows：`tool/prepare_github_cli_runtime.ps1` → `native/github_cli/windows/runtime/bin/gh.exe`
- macOS：`tool/prepare_github_cli_runtime_macos.sh` → Universal `native/github_cli/macos/runtime/bin/gh`
- Linux：`tool/prepare_github_cli_runtime_linux.sh` → 当前 amd64/arm64 的 `native/github_cli/linux/runtime/bin/gh`

每个脚本固定官方 Release URL 和 SHA-256，版本或资产变化必须同时更新脚本、包验证器、测试和本文件。Windows/macOS Release 缺少 `gh` 或 runtime manifest 时必须构建失败，不能静默回退到系统安装。
