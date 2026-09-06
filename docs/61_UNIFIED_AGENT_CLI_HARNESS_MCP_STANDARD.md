# VibeKits 统一智能体 CLI、Harness 与 MCP 设计规范

## 1. 目标与边界

VibeKits 为多种智能体 CLI 提供同一套发现、检查、同步执行和长任务接口。Harness 不根据命令名称猜参数；每个新任务先读取动态 MCP `tools/list` 和 CLI 目录，再按实际可用性选择提供方。

第一期适配：OpenAI Codex CLI、Claude Code、GitHub Copilot CLI、Cursor Agent、Gemini CLI、Aider、OpenCode。DeepSeek Harness 继续作为 VibeKits 主调度器，不由本接口递归启动自身。

本规范不承诺重新分发第三方闭源运行时。运行时来源必须在目录中声明：

- `bundled`：许可证允许且经过固定版本、来源和哈希验证，由 APP 随包提供；
- `system`：只发现用户已经安装的官方命令，不复制、不修改、不自动升级；
- `unavailable`：找不到可执行文件，接口必须返回明确状态，不能静默换成其他智能体。

Windows、macOS、Linux 使用同一 JSON/MCP 合同。Android/iOS 不直接运行桌面 CLI，可通过已配对的 LMCP/2 桌面节点调用。

## 2. 提供方标识与命令合同

| `providerId` | 显示名称 | 默认命令 | 非交互建议 | MCP/协议能力 |
| --- | --- | --- | --- | --- |
| `codex` | OpenAI Codex CLI | `codex` | `codex exec <prompt>` | MCP、App Server、SDK |
| `claude` | Claude Code | `claude` | `claude -p <prompt>` | MCP |
| `copilot` | GitHub Copilot CLI | `copilot` | `copilot -p <prompt>` | MCP、ACP |
| `cursor` | Cursor Agent | `cursor-agent` | 按运行时 `--help` | 版本相关 |
| `gemini` | Gemini CLI | `gemini` | `gemini -p <prompt> --output-format json` | MCP、ACP |
| `aider` | Aider | `aider` | `aider --message <prompt>` | 无统一 MCP |
| `opencode` | OpenCode | `opencode` | 按运行时 `--help` | 版本相关 |

提供方能力来自本机真实探测，而不是上表的静态宣传。`inspect` 只执行版本命令；不得在发现阶段启动登录、修改配置或联网任务。

## 3. 对外工具

### `vibekits.agent_cli.catalog`

输入 `{}`。返回全部提供方的 `providerId`、名称、平台、可用性、可执行文件来源、路径、版本探测状态、推荐非交互模式和已知协议。路径只用于诊断，调用方不得绕过 MCP 直接执行。

风险：`readOnly`。

### `vibekits.agent_cli.inspect`

- `providerId`：必填，上表枚举。

重新解析一个提供方并执行有界版本探测。风险：`readOnly`。

### `vibekits.agent_cli.execute`

- `providerId`：必填；
- `arguments`：必填字符串数组，1～128 项；
- `workingDirectory`：可选、必须已存在的绝对目录；
- `timeoutSeconds`：5～3600，默认 300。

同步执行并返回 `ok`、`exitCode`、`stdout`、`stderr`、实际提供方和截断标记。只传 argv，不经过 shell，不接受 stdin。风险：`controlsDevice`。

### `vibekits.agent_cli.task_start`

参数与 `execute` 相同，另外：

- `timeoutSeconds`：5～86400，默认 3600。

启动后立即返回 `taskId`。后台同时读取 stdout/stderr，不能因管道缓冲导致子进程卡死。风险：`controlsDevice`。

### `vibekits.agent_cli.task_status`

- `taskId`：必填。

返回 `running/succeeded/failed/cancelled/timedOut`、开始/完成时间、PID、exitCode、当前有界输出。终态至少保留 30 分钟。风险：`readOnly`。

### `vibekits.agent_cli.task_cancel`

- `taskId`：必填。

只终止由当前 VibeKits 实例创建且仍在运行的任务；重复取消幂等。风险：`controlsDevice`。

## 4. 安全规范

1. 禁止 shell：`Process.start(executable, arguments, runInShell: false)`；参数包含空格也必须作为单独数组元素。
2. 禁止通过参数传入常见密钥选项，例如 `--api-key`、`--token`、`--client-secret`、`--password`；认证使用各官方 CLI 自己的 OAuth、系统凭据库或受控环境配置。
3. stdout/stderr 对 OpenAI、Anthropic、GitHub、Google 等常见令牌格式二次脱敏，并限制为 256 KiB。
4. 固定关闭 pager、颜色、更新提示和交互提示；需要交互登录时返回 `interactive_required`，由用户在受信任终端完成。
5. 本机 Harness 按 VibeKits 内部工具策略调用；远程 LMCP/2 调用必须经过配对、目录摘要校验、工具级授权、风险审批和审计。
6. 工作目录必须存在。接口不得自动扩大到父目录、用户目录或系统盘。
7. 不存在的提供方、任务 ID、已过期任务、超时和非零退出码均返回稳定结构，不伪报成功。

## 5. 验收流程

### A. 静态合同

1. `flutter analyze --no-pub` 为 0 issue。
2. 能力目录生成测试通过，六个接口出现在 Harness 可执行目录和 MCP `tools/list`。
3. JSON Schema 包含必填项、枚举、范围、默认值和 `additionalProperties=false`。

### B. 单元测试

1. 七个提供方候选路径和版本参数正确；不存在时返回 `available=false`。
2. bundled 路径优先于 PATH；自定义测试路径优先级最高。
3. 参数逐项原样传递，不通过 shell；工作目录校验有效。
4. 密钥参数被拒绝，输出令牌被脱敏，超长输出被截断。
5. 同步成功、非零退出和超时都产生真实状态。
6. 长任务启动后立即返回；状态可轮询；stdout/stderr 并行收集；完成、超时、取消和重复取消行为正确。
7. 一个 VibeKits 实例不能取消外部 PID 或伪造 taskId。

### C. 平台与真机

1. Windows x64、macOS x86_64/arm64、Linux amd64/arm64 分别运行 `catalog`。
2. 对每个实际安装的提供方执行 `inspect` 和一条只读非交互命令。
3. 在空白系统上验证未安装提供方只显示不可用，不影响 APP 启动。
4. LMCP/2 远端读取目录；只读检查可按授权执行；控制级调用弹出审批，拒绝后无子进程。
5. 启动 10 分钟以上测试任务，客户端断开后任务继续，重连可用同一 `taskId` 查询；取消后无遗留进程。

### D. 发布门禁

1. Windows Debug/Release 编译和包内运行时验证；macOS Universal 签名与兼容性验证；Linux 对应架构构建。
2. 生成带日期、版本、提交、平台、通过/失败/跳过数和未验收边界的测试报告。
3. `git diff --check`、工作区范围审计通过，只提交本任务文件，不加入缓存、下载运行时或 `.skills-publish/`。
4. 推送 `cloud/main` 后，用远端 ref 核对提交 SHA。

## 6. 完成定义

代码写完不等于完成。只有设计、实现、自动化测试、至少当前平台真实构建、报告、提交、云端 SHA 核验全部完成，才能声明本轮完成；无法在当前机器执行的 macOS/Linux/局域网真机项目必须明确标记为待对应环境验收。
