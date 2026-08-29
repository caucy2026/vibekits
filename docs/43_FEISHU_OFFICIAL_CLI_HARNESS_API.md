# 飞书官方 CLI 移植与 Harness MCP 接口

## 目标与来源

Vibekits 内嵌官方开源项目 `larksuite/cli` 的运行时能力，并由 Harness MCP 以结构化参数调用。上游固定来源为 <https://github.com/larksuite/cli>，许可证为 MIT；当前移植基线提交为 `6646386e0996b1ff5df640bccff834a20bcb203b`，CLI 报告版本 `v1.0.92`。

源码、Go SDK、模块缓存、编译缓存、配置和二进制全部位于 D 盘。上游源码默认位于 `D:\vibecode\upstream\larksuite-cli`；Vibekits 的缓存位于 `.cache`，打包输入位于被 Git 忽略的 `native/lark_cli/windows/runtime`。

## 构建与打包

运行 `tool/prepare_lark_cli_runtime.ps1`。脚本会：

1. 从项目路径推导 D 盘上游源码和 Go SDK，不依赖系统盘 PATH。
2. 调用上游 `scripts/fetch_meta.py --force`，从飞书官方开放平台获取完整 API 元数据。
3. 把 Go 的 `GOCACHE`、`GOMODCACHE` 和 `GOPATH` 固定到项目 `.cache`。
4. 编译 `native/lark_cli/windows/runtime/lark-cli.exe` 并执行版本冒烟检查。
5. Windows CMake Release 安装阶段把它复制到 `tools/lark-cli/lark-cli.exe`。

## MCP 工具

| 工具 | 参数 | 作用与返回 | 风险 |
|---|---|---|---|
| `vibekits.feishu.inspect` | 无 | 返回是否可用、绝对路径、版本、上游、许可证和 JSON 契约 | 只读 |
| `vibekits.feishu.auth_status` | 无 | 调用 `auth status`；未配置时返回官方 `not_configured` typed error | 只读 |
| `vibekits.feishu.schema` | `command?: string` | 查询命令参数、身份、scope 与风险；空字符串查询目录 | 只读 |
| `vibekits.feishu.execute` | `arguments: string[1..64]`；`timeoutSeconds?: 5..1800`，默认 300 | 不经过 shell 执行官方命令，返回 `exitCode/ok/envelope/stdout/stderr/configDirectory` | 设备控制审批 |

标准调用顺序为 `inspect → auth_status → schema → execute`。写操作应先按上游支持情况使用 `--dry-run`。`arguments` 必须是数组，例如：

```json
{
  "arguments": ["calendar", "events", "get", "--calendar-id", "...", "--event-id", "..."],
  "timeoutSeconds": 120
}
```

## 安全与可靠性边界

- 不调用 shell，参数不会被命令拼接解释。
- MCP 拒绝 App Secret、Access Token、Refresh Token、Tenant/User Access Token 参数及 `--flag=value` 形式。
- 凭据只能进入官方配置/OAuth 流程；配置目录由 Vibekits 隔离，结果不得回显秘密。
- stdout/stderr 单项最多保留约 64 KiB；非零退出码保留官方 typed error。
- 超时会终止 CLI 子进程，避免 Harness 长任务留下孤儿进程。
- `execute` 是通用底层能力，不等于自动授予飞书权限；租户权限、scope、用户 OAuth 与写操作审批仍分别生效。

## 当前验收口径

没有飞书应用身份时，`inspect` 成功且 `auth_status` 返回 `not_configured` 是正确结果。真实读写验收还需要用户在官方流程中配置应用并授权所需 scope；秘密不进入源码、Git、MCP 参数或测试报告。
