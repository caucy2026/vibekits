# VibeKits 外部智能体 MCP 与 Harness 工具接口目录

> 本文由 `tool/export_harness_capability_catalog.dart` 从实际 `ToolSpec` 与 `VibekitsHarnessToolBridge` 生成。带 `*` 的参数为必填；运行时以 MCP `inputSchema` 为最终准则。

## 数量口径

- 产品一级页面：5（智能体、解压缩、系统清理、文档阅读、开发工具）。
- 开发工具业务能力条目：79。
- 开发工具独立工作区入口：19。
- Harness 定义接口：168。
- Harness 当前可执行接口：146。
- 当前不可公开接口：22。

不要把以上数字相加称为“总功能数”：页面、业务条目和机器接口是三种不同层级。Harness 回答时先调用 `vibekits.system.capability_check` 获取本次运行的动态数字。

## 外部智能体接入

VibeKits 对 Codex、Claude Desktop、Cursor、VS Code 智能体和其他支持 stdio MCP 的客户端开放同一套工具。客户端不需要接触 Harness API Key，也不需要复制内部实现。

Windows 源码工作区推荐把下面命令注册为一个 stdio MCP server：

```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -File <VIBEKITS_ROOT>\tool\start_vibekits_mcp.ps1
```

通用 MCP JSON 配置：

```json
{
  "mcpServers": {
    "vibekits": {
      "command": "powershell.exe",
      "args": ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "<VIBEKITS_ROOT>\\tool\\start_vibekits_mcp.ps1"]
    }
  }
}
```

Codex `config.toml` 配置：

```toml
[mcp_servers.vibekits]
command = "powershell.exe"
args = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "<VIBEKITS_ROOT>\\tool\\start_vibekits_mcp.ps1"]
startup_timeout_sec = 30
tool_timeout_sec = 600
```

运行链路：启动脚本确保 VibeKits APP 在运行 → APP 在 `127.0.0.1` 随机端口发布带随机 Bearer Token 的桥接文件 → stdio MCP 读取目录并转发调用。监听不暴露到局域网，连接文件不包含模型 API Key。写入、设备控制和破坏性操作仍遵守 APP 当前权限策略，并写入对应工具日志。

需要自行实现适配器时，可读取 `%LOCALAPPDATA%\Vibekits\Mcp\tool-bridge.json` 中的临时 `baseUrl` 和 `token`，使用 `Authorization: Bearer <token>` 调用 `GET /catalog`、`POST /invoke` 与 `POST /native-approval`。这是仅限本机的底层协议；普通客户端应优先使用 stdio MCP，以免自行处理令牌轮换和 APP 生命周期。

MCP 对外名称会去掉 `vibekits.` 前缀并把点转换为双下划线，例如 `vibekits.adb.shell` 对外为 `adb__shell`。客户端必须以运行时 `tools/list` 返回值为准。

## 统一调用协议

1. 通过 MCP 工具目录发现 `vibekits.*`。
2. 读取目标工具的 `description`、风险级别和 `inputSchema`。
3. 使用符合 Schema 的 JSON 对象调用；没有参数的工具传 `{}`。
4. 只读工具直接执行；写数据、控制设备或破坏性操作按当前权限模式审批。
5. 读取结构化结果，并在对应模块 Harness 记录中核对真实日志。
6. 需要精确参数时先调用 `system.describe_tool`；可发现或可安全试探的参数自动配置，仅账号/身份缺失、密码/API Key/Token/私钥口令等秘密才询问用户。

外部 MCP 客户端采用标准 `tools/list` 与 `tools/call`；下表同时给出内部稳定 ID 和实际 MCP 名称。VibeKits 内置 Harness 自动完成这层协议。

## 模块汇总

| 模块 | 定义接口数 |
| --- | ---: |
| 系统诊断 | 27 |
| 文件工具 | 7 |
| 格式处理 | 10 |
| 加密生成 | 9 |
| 计算调试 | 9 |
| 编码转换 | 13 |
| 网络开发 | 25 |
| 时间文本 | 10 |
| 智能开发 | 1 |
| 音频调试 | 6 |
| 远程连接 | 33 |
| 数据库 | 5 |
| 版本控制 | 10 |
| 虚拟化 | 3 |

## 系统诊断（定义 27）

| 内部工具 ID | MCP 名称 | 名称 | 当前可用 | 用途 | 风险 | 参数 |
| --- | --- | --- | --- | --- | --- | --- |
| `vibekits.adb_workspace` | `adb_workspace` | 安卓调试（ADB） | 否（环境/接线门禁） | 管理 Android USB/无线设备、Shell、文件、Logcat、截图和 APK。 适合：用户明确需要“安卓调试（ADB）”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `controlsDevice` | `input`* (string), `params` (string) |
| `vibekits.api_workspace` | `api_workspace` | 接口调试（API） | 否（环境/接线门禁） | 发送有界 HTTP 请求，查看状态、响应头、耗时和正文。 适合：用户明确需要“接口调试（API）”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.audio_analyzer` | `audio_analyzer` | 音频调试（PCM/WAV） | 是 | 打开 PCM/WAV，查看多声道波形、播放声音并分析格式、峰值、RMS、谐波、THD、THD+N、SNR、噪声底、削波、静音和直流偏置。 适合：需要判断 PCM/WAV 参数、信号是否削波或静音、查看音频基础质量指标时。 不适合：需要修改原始音频、主观评价内容或分析未知压缩编码时不要直接使用。 示例：分析这份 PCM 的波形和信号质量；检查 WAV 是否削波、静音或存在直流偏置 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.cleaner.analyze_drive` | `cleaner__analyze_drive` | 分析磁盘占用 | 是 | 在独立后台线程分析指定磁盘根目录，按系统、软件和用户数据解释占用是否合理并给出安全建议；不删除任何文件。 | `readOnly` | `root`* (string) |
| `vibekits.database_manager` | `database_manager` | 数据库管理（SQL） | 否（环境/接线门禁） | 拖入 SQLite 数据库，浏览表和视图并运行有界只读 SQL。 适合：用户明确需要“数据库管理（SQL）”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.duplicate_files` | `duplicate_files` | 重复文件（Duplicate） | 否（环境/接线门禁） | 按大小预筛并用完整 SHA-256 确认重复内容，复核后移入回收站。 适合：用户明确需要“重复文件（Duplicate）”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `writesData` | `input`* (string), `params` (string) |
| `vibekits.file_search` | `file_search` | 文件搜索（Search） | 否（环境/接线门禁） | 按文件名或内容快速搜索，结果可定位、复制路径并继续计算哈希。 适合：用户明确需要“文件搜索（Search）”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.git_workspace` | `git_workspace` | 版本控制（Git） | 否（环境/接线门禁） | 查看仓库、Diff 和提交；读取 Gerrit/远端 refs 与 manifest，按需浅克隆单仓；通过预览、秘密阻断及分离审批安全备份。 适合：用户明确需要“版本控制（Git）”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.github_diagnostics` | `github_diagnostics` | 网络诊断（GitHub） | 否（环境/接线门禁） | 分层检查 GitHub 凭据与网络，发现真实回环代理并可回滚地只修复 GitHub Git。 适合：用户明确需要“网络诊断（GitHub）”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.harness.diagnostics` | `harness__diagnostics` | 查询 Harness 诊断日志 | 是 | 只读返回 Harness 最近的启动/运行日志和 Vibekits 工具调用记录，用于定位超时、退出、工具失败和耗时异常；敏感字段会脱敏。 | `readOnly` | `limit` (integer；最小=1；最大=50), `includeLogTail` (boolean) |
| `vibekits.network.download` | `network__download` | 下载网络文件 | 是 | 把 HTTP/HTTPS 文件流式下载到 APP 配置的下载目录，完成后返回绝对路径、大小、SHA-256 和 HTTP 证据。APK 会校验 ZIP/APK 签名，适合随后调用 adb.install_apk。 | `writesData` | `url`* (string), `fileName` (string), `outputDirectory` (string), `overwrite` (boolean；默认=false), `expectedSha256` (string), `timeoutSeconds` (integer；默认=300；最小=5；最大=1800), `maxBytes` (integer；默认=2147483648；最小=1；最大=8589934592) |
| `vibekits.network_virtualization` | `network_virtualization` | 网络代理（Clash Verge） | 否（环境/接线门禁） | 使用内置 Mihomo 管理订阅、节点、测速、连接、规则、日志与系统代理。 适合：用户明确需要“网络代理（Clash Verge）”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.ocr.capture_screen` | `ocr__capture_screen` | 截图并 OCR 分析 | 否（环境/接线门禁） | 让用户框选屏幕区域并在本机 OCR。返回原图尺寸、文字、像素框 boundsPx、0..1 归一化框 boundsRelative、九宫格 region 和 spatialText；没有多模态视觉的智能体应依据这些字段理解控件位置、阅读顺序和空间关系。 | `controlsDevice` | `{}` |
| `vibekits.packet_capture` | `packet_capture` | 网络抓包（PCAP） | 否（环境/接线门禁） | 使用内置 WinDivert 实时抓取和过滤网络包，保存、读取并分析标准 PCAP 文件。 适合：用户需要抓包、保存网络流量、读取 PCAP、定位协议或端点流量时。 不适合：不得抓取未获授权的第三方设备流量；实时抓包在 Windows 需要管理员权限。 示例：抓 30 秒 DNS 包并保存；分析这个 PCAP 里流量最多的端点 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.programmer_calculator` | `programmer_calculator` | 程序员计算器（HEX/DEC） | 否（环境/接线门禁） | 整数表达式、进制转换、位运算和有符号/无符号解释。 适合：用户明确需要“程序员计算器（HEX/DEC）”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.project.build` | `project__build` | 验证并编译 Vibekits APP | 是 | 在指定源码工作区依次执行 Analyze、Harness 自动注册合同测试和目标平台 Release 构建。只生成 build 产物，不覆盖运行中的 APP。 | `writesData` | `workspace`* (string), `target`* (string；枚举=windows/android/macos), `flutterExecutable` (string), `runTests` (boolean) |
| `vibekits.project.iteration_inspect` | `project__iteration_inspect` | 检查 APP 自迭代工作区 | 是 | 检查 Vibekits 源码、ToolSpec 单一注册表和 Harness 桥接位置，并返回新增工具必须遵循的自动发现流程。 | `readOnly` | `workspace`* (string) |
| `vibekits.remote_workspace` | `remote_workspace` | 远程连接（SSH/SFTP） | 否（环境/接线门禁） | 统一管理安全终端、双栏文件和本地/远程/SOCKS5 端口转发。 适合：用户明确需要“远程连接（SSH/SFTP）”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `controlsDevice` | `input`* (string), `params` (string) |
| `vibekits.serial.auto_detect` | `serial__auto_detect` | 自动探测串口配置 | 是 | 自动选择物理 USB 串口，并以只监听、不发送数据的方式分阶段尝试常见波特率、数据位、停止位、奇偶校验和全部 8 种流控组合；返回逐项证据及推荐配置，不要求用户手工填写。 | `controlsDevice` | `port` (string), `baudRates` (array), `listenMs` (integer；默认=300；最小=100；最大=3000) |
| `vibekits.serial_port` | `serial_port` | 串口调试（Serial） | 否（环境/接线门禁） | 打开 Windows/macOS 串口，配置波特率和帧格式并进行文本或 HEX 收发。 适合：用户明确需要“串口调试（Serial）”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `controlsDevice` | `input`* (string), `params` (string) |
| `vibekits.system.capability_check` | `system__capability_check` | 检查智能体工具链 | 是 | 只读核对 Vibekits 向 Harness 公开的每个工具是否具有本地执行器，并列出因安全或环境原因未公开的能力。用于任务前自检，不能替代硬件和外部服务的真实验收。 | `readOnly` | `{}` |
| `vibekits.system.describe_tool` | `system__describe_tool` | 精确说明工具参数 | 是 | 按工具 ID 返回当前运行版本的完整 inputSchema、必填项、枚举、默认值、风险和自动配置原则。回答参数配置问题前必须调用。 | `readOnly` | `toolId`* (string) |
| `vibekits.system.resources` | `system__resources` | 检查系统资源 | 是 | 只读采样本机 Windows/macOS/Android，或通过 Vibekits 内置 ADB 采样指定 Android 设备。返回 CPU、内存、GPU、磁盘、Top 进程、异常建议和证据来源。单次快照正常时不得断言间歇性卡顿已排除。 | `readOnly` | `adbSerial` (string), `samples` (integer；最小=1；最大=10), `intervalMs` (integer；最小=250；最大=5000) |
| `vibekits.system_resources` | `system_resources` | 资源诊断（CPU/GPU） | 否（环境/接线门禁） | 采样 Windows、macOS、Android 的 CPU、内存、GPU、磁盘和 Top 进程，也可通过内置 ADB 分析 Android 设备。 适合：用户说系统卡顿、发热、快死机、内存不足、CPU/GPU 占用高或想找异常进程时。 不适合：一次快照不能证明间歇性问题；不得据此直接结束进程或删除文件。 示例：帮我分析当前系统为什么卡；检查这台 Android 设备的 CPU、内存和磁盘 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.virtual_machine` | `virtual_machine` | 轻量虚拟机（QEMU） | 否（环境/接线门禁） | 使用内置 QEMU 创建虚拟磁盘并运行 Windows、Linux 等本地虚拟机。 适合：用户明确需要“轻量虚拟机（QEMU）”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.windows_node.ensure_client_identity` | `windows_node__ensure_client_identity` | 确保客户端独立身份 | 否（环境/接线门禁） | 等待 macOS Keychain/受保护文件实现；只返回公钥和不透明凭据引用，永不返回私钥。 | `writesData` | `{}` |
| `vibekits.windows_node.helper_status` | `windows_node__helper_status` | 检查 Windows 节点 Helper | 是 | 读取当前 Release 中 helper 实体和 manifest 状态；缺失或不匹配时明确关闭系统写入工具。 | `readOnly` | `{}` |

## 文件工具（定义 7）

| 内部工具 ID | MCP 名称 | 名称 | 当前可用 | 用途 | 风险 | 参数 |
| --- | --- | --- | --- | --- | --- | --- |
| `vibekits.batch_rename` | `batch_rename` | 批量重命名（Rename） | 是 | 选择文件夹，预览并安全执行查找替换、前后缀、大小写和序号规则。 适合：用户明确需要“批量重命名（Rename）”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `writesData` | `input`* (string), `params` (string) |
| `vibekits.code_statistics` | `code_statistics` | 代码统计（LOC） | 是 | 后台统计项目或单文件的语言、文件数、代码、注释和空白行，自动跳过依赖与构建目录。 适合：需要快速了解项目规模、主要语言、代码与注释构成时，优先于逐文件读取。 不适合：需要语义分析、复杂度、安全漏洞判断或精确编译器 AST 结果时不要使用。 示例：统计当前工作区主要语言和代码行数 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.code_structure_search` | `code_structure_search` | 代码结构搜索（Structure） | 是 | 后台按声明结构查找类、类型和函数，返回文件、行号与声明；不修改源码。 适合：需要定位类、函数或类型定义时，优先于读取整个仓库或普通全文搜索。 不适合：需要完整编译器语义、引用关系、宏展开或自动改写时不要使用。 示例：在工作区定位 class\|HarnessToolBridge 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.file_diff` | `file_diff` | 比较两个文件 | 是 | 在独立后台线程读取两个有界文本或源码文件，自动识别编码并返回行级差异；不修改文件。 | `readOnly` | `leftPath`* (string), `rightPath`* (string), `ignoreWhitespace` (boolean), `ignoreCase` (boolean) |
| `vibekits.file_hash` | `file_hash` | 文件哈希（Hash） | 是 | 计算文件哈希，参数为算法（md5/sha1/sha256/sha512），输入为路径。 适合：用户明确需要“文件哈希（Hash）”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.files.duplicate_scan` | `files__duplicate_scan` | 扫描重复文件 | 是 | 在独立后台线程按大小和完整 SHA-256 扫描重复文件；只返回建议，不自动删除。 | `readOnly` | `root`* (string), `recursive` (boolean), `minimumSize` (integer；最小=1；最大=1099511627776) |
| `vibekits.files.search` | `files__search` | 搜索文件 | 是 | 按文件名或文本内容进行有界搜索，不跟随符号链接。 | `readOnly` | `root`* (string), `query`* (string), `mode` (string；枚举=name/content), `maxResults` (integer；最小=1；最大=500) |

## 格式处理（定义 10）

| 内部工具 ID | MCP 名称 | 名称 | 当前可用 | 用途 | 风险 | 参数 |
| --- | --- | --- | --- | --- | --- | --- |
| `vibekits.csv_to_json` | `csv_to_json` | CSV 转 JSON | 是 | 以首行为表头，将标准 CSV 转为对象数组。 适合：需要确定、离线地完成CSV 转 JSON时。 不适合：输入格式不明确、需要联网验证或需要修改源文件时不要使用。 示例：使用CSV 转 JSON处理当前输入 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.json_escape` | `json_escape` | JSON 字符串转义 | 是 | 把任意文本转换为合法 JSON 字符串字面量。 适合：需要确定、离线地完成JSON 字符串转义时。 不适合：输入格式不明确、需要联网验证或需要修改源文件时不要使用。 示例：使用JSON 字符串转义处理当前输入 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.json_format` | `json_format` | JSON 格式化 | 是 | 校验并格式化 JSON。 适合：用户明确需要“JSON 格式化”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.json_minify` | `json_minify` | JSON 压缩 | 是 | 校验 JSON 并移除无意义空白。 适合：需要确定、离线地完成JSON 压缩时。 不适合：输入格式不明确、需要联网验证或需要修改源文件时不要使用。 示例：使用JSON 压缩处理当前输入 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.json_query` | `json_query` | 结构化数据查询 | 是 | 安全查询 JSON/YAML/TOML/XML，支持点路径、数组下标和通配，例如 auto\|.items[*].id。 适合：需要从 API 响应、配置或日志中精确提取字段时，优先于读取整段文本。 不适合：需要执行任意 jq/yq 表达式、修改源文件或输入不是结构化数据时不要使用。 示例：从 API 响应提取 auto\|.data.items[*].id 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.json_to_csv` | `json_to_csv` | JSON 转 CSV | 是 | 将 JSON 对象数组转换为带表头的 CSV。 适合：需要确定、离线地完成JSON 转 CSV时。 不适合：输入格式不明确、需要联网验证或需要修改源文件时不要使用。 示例：使用JSON 转 CSV处理当前输入 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.json_unescape` | `json_unescape` | JSON 字符串反转义 | 是 | 解析 JSON 字符串字面量并还原原文。 适合：需要确定、离线地完成JSON 字符串反转义时。 不适合：输入格式不明确、需要联网验证或需要修改源文件时不要使用。 示例：使用JSON 字符串反转义处理当前输入 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.json_validate` | `json_validate` | JSON 校验 | 是 | 校验 JSON 并报告顶层类型。 适合：用户明确需要“JSON 校验”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.xml_format` | `xml_format` | XML 格式化 | 是 | 校验并缩进 XML。 适合：需要确定、离线地完成XML 格式化时。 不适合：输入格式不明确、需要联网验证或需要修改源文件时不要使用。 示例：使用XML 格式化处理当前输入 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.xml_minify` | `xml_minify` | XML 压缩 | 是 | 校验 XML 并移除格式化空白。 适合：需要确定、离线地完成XML 压缩时。 不适合：输入格式不明确、需要联网验证或需要修改源文件时不要使用。 示例：使用XML 压缩处理当前输入 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |

## 加密生成（定义 9）

| 内部工具 ID | MCP 名称 | 名称 | 当前可用 | 用途 | 风险 | 参数 |
| --- | --- | --- | --- | --- | --- | --- |
| `vibekits.hmac_sha256` | `hmac_sha256` | HMAC-SHA256 | 是 | 使用密钥计算消息的 HMAC-SHA256。 适合：用户明确需要“HMAC-SHA256”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.jwt_decode` | `jwt_decode` | JWT 解码 | 是 | 离线解码 JWT header/payload，并明确标注未验证签名。 适合：需要确定、离线地完成JWT 解码时。 不适合：输入格式不明确、需要联网验证或需要修改源文件时不要使用。 示例：使用JWT 解码处理当前输入 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.jwt_expiry` | `jwt_expiry` | JWT 过期检查 | 是 | 读取 JWT exp 并计算过期时间；不验证签名。 适合：需要确定、离线地完成JWT 过期检查时。 不适合：输入格式不明确、需要联网验证或需要修改源文件时不要使用。 示例：使用JWT 过期检查处理当前输入 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.md5` | `md5` | MD5 | 是 | 计算 UTF-8 文本的 MD5。 适合：用户明确需要“MD5”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.random_password` | `random_password` | 随机密码 | 是 | 生成随机密码，参数为长度（默认 16）。 适合：用户明确需要“随机密码”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.sha1` | `sha1` | SHA-1 | 是 | 计算 UTF-8 文本的 SHA-1。 适合：用户明确需要“SHA-1”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.sha256` | `sha256` | SHA-256 | 是 | 计算 UTF-8 文本的 SHA-256。 适合：用户明确需要“SHA-256”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.sha512` | `sha512` | SHA-512 | 是 | 计算 UTF-8 文本的 SHA-512。 适合：用户明确需要“SHA-512”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.uuid_v4` | `uuid_v4` | UUID v4 | 是 | 生成随机 UUID v4，参数为数量（默认 1）。 适合：用户明确需要“UUID v4”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |

## 计算调试（定义 9）

| 内部工具 ID | MCP 名称 | 名称 | 当前可用 | 用途 | 风险 | 参数 |
| --- | --- | --- | --- | --- | --- | --- |
| `vibekits.bytes_convert` | `bytes_convert` | 存储单位转换 | 是 | 转换 B/KB/MB/GB 与 KiB/MiB/GiB。 适合：需要确定、离线地完成存储单位转换时。 不适合：输入格式不明确、需要联网验证或需要修改源文件时不要使用。 示例：使用存储单位转换处理当前输入 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.calculator.programmer` | `calculator__programmer` | 程序员计算器 | 是 | 计算整数、进制和位运算表达式，并返回固定位宽的二/八/十/十六进制结果。 | `readOnly` | `expression`* (string), `width` (integer；枚举=8/16/32/64/128), `inputRadix` (integer；枚举=2/8/10/16) |
| `vibekits.chmod_decode` | `chmod_decode` | chmod 权限解码 | 是 | 将八进制 Unix 权限转换为 rwx 符号。 适合：需要确定、离线地完成chmod 权限解码时。 不适合：输入格式不明确、需要联网验证或需要修改源文件时不要使用。 示例：使用chmod 权限解码处理当前输入 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.chmod_encode` | `chmod_encode` | chmod 权限编码 | 是 | 将九位 rwx 符号转换为八进制权限。 适合：需要确定、离线地完成chmod 权限编码时。 不适合：输入格式不明确、需要联网验证或需要修改源文件时不要使用。 示例：使用chmod 权限编码处理当前输入 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.duration_convert` | `duration_convert` | 时间单位转换 | 是 | 转换毫秒、秒、分钟、小时和天。 适合：需要确定、离线地完成时间单位转换时。 不适合：输入格式不明确、需要联网验证或需要修改源文件时不要使用。 示例：使用时间单位转换处理当前输入 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.endian_swap` | `endian_swap` | 字节序反转 | 是 | 按字节反转十六进制数据的端序。 适合：需要确定、离线地完成字节序反转时。 不适合：输入格式不明确、需要联网验证或需要修改源文件时不要使用。 示例：使用字节序反转处理当前输入 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.number_base_convert` | `number_base_convert` | 2～36 进制转换 | 是 | 使用任意精度整数在 2～36 进制间转换。 适合：需要确定、离线地完成2～36 进制转换时。 不适合：输入格式不明确、需要联网验证或需要修改源文件时不要使用。 示例：使用2～36 进制转换处理当前输入 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.safe_benchmark` | `safe_benchmark` | 安全性能基准（Benchmark） | 是 | 对内置 SHA-256、JSON 解析或 Base64 做预热和多轮统计，不执行任意命令。 适合：需要在当前机器比较内置数据处理操作的相对耗时时使用。 不适合：需要运行 shell、外部程序、清缓存或得出跨机器绝对性能结论时不要使用。 示例：对这段 JSON 执行 json_parse\|50 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.semver_compare` | `semver_compare` | 语义版本比较 | 是 | 按 SemVer 规则比较正式版和预发布版本。 适合：需要确定、离线地完成语义版本比较时。 不适合：输入格式不明确、需要联网验证或需要修改源文件时不要使用。 示例：使用语义版本比较处理当前输入 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |

## 编码转换（定义 13）

| 内部工具 ID | MCP 名称 | 名称 | 当前可用 | 用途 | 风险 | 参数 |
| --- | --- | --- | --- | --- | --- | --- |
| `vibekits.ascii_inspect` | `ascii_inspect` | 字符码检查 | 是 | 列出字符的 Unicode、十进制码点和原字符。 适合：需要确定、离线地完成字符码检查时。 不适合：输入格式不明确、需要联网验证或需要修改源文件时不要使用。 示例：使用字符码检查处理当前输入 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.base64_decode` | `base64_decode` | Base64 解码 | 是 | 将 Base64 解码为 UTF-8 文本。 适合：用户明确需要“Base64 解码”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.base64_encode` | `base64_encode` | Base64 编码 | 是 | 将 UTF-8 文本编码为 Base64。 适合：用户明确需要“Base64 编码”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.hex_decode` | `hex_decode` | Hex 解码 | 是 | 将十六进制字节串解码为 UTF-8 文本。 适合：用户明确需要“Hex 解码”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.hex_encode` | `hex_encode` | Hex 编码 | 是 | 将 UTF-8 文本转为十六进制字节串。 适合：用户明确需要“Hex 编码”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.hex_to_rgb` | `hex_to_rgb` | HEX 转 RGB | 是 | 将 #RGB/#RRGGBB 转为结构化 RGB。 适合：需要确定、离线地完成HEX 转 RGB时。 不适合：输入格式不明确、需要联网验证或需要修改源文件时不要使用。 示例：使用HEX 转 RGB处理当前输入 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.html_decode` | `html_decode` | HTML 实体解码 | 是 | 将 HTML 实体还原为字符。 适合：用户明确需要“HTML 实体解码”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.html_encode` | `html_encode` | HTML 实体编码 | 是 | 将 & < > " ' 转义为 HTML 实体。 适合：用户明确需要“HTML 实体编码”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.rgb_to_hex` | `rgb_to_hex` | RGB 转 HEX | 是 | 将三个 RGB 分量转换为十六进制颜色。 适合：需要确定、离线地完成RGB 转 HEX时。 不适合：输入格式不明确、需要联网验证或需要修改源文件时不要使用。 示例：使用RGB 转 HEX处理当前输入 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.unicode_escape` | `unicode_escape` | Unicode 转义 | 是 | 将非 ASCII 字符转为 \uXXXX 转义序列。 适合：用户明确需要“Unicode 转义”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.unicode_unescape` | `unicode_unescape` | Unicode 反转义 | 是 | 将 \uXXXX 转义序列还原为字符。 适合：用户明确需要“Unicode 反转义”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.url_decode` | `url_decode` | URL 解码 | 是 | 对百分号编码进行解码。 适合：用户明确需要“URL 解码”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.url_encode` | `url_encode` | URL 编码 | 是 | 对文本进行百分号编码。 适合：用户明确需要“URL 编码”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |

## 网络开发（定义 25）

| 内部工具 ID | MCP 名称 | 名称 | 当前可用 | 用途 | 风险 | 参数 |
| --- | --- | --- | --- | --- | --- | --- |
| `vibekits.capture.analyze` | `capture__analyze` | 分析 PCAP 流量 | 是 | 只读统计协议、字节数和 Top 端点，给智能体提供可核验的网络流量证据。 | `readOnly` | `path`* (string) |
| `vibekits.capture.read` | `capture__read` | 读取 PCAP 数据包 | 是 | 只读解析标准 PCAP，返回时间、协议、源、目标、长度及汇总；不会修改原文件。 | `readOnly` | `path`* (string), `maxPackets` (integer；最小=1；最大=10000) |
| `vibekits.capture.start` | `capture__start` | 开始网络抓包 | 是 | 使用 APP 内置 WinDivert 在后台抓取本机网络包，按过滤器筛选并持续保存为标准 PCAP。Windows 首次加载驱动需要管理员权限。 | `controlsDevice` | `outputPath` (string), `filter` (string), `maxPackets` (integer；最小=0；最大=1000000) |
| `vibekits.capture.status` | `capture__status` | 检查网络抓包状态 | 是 | 只读返回内置 WinDivert 抓包内核、当前任务、已收包数、输出 PCAP 和最近错误。 | `readOnly` | `{}` |
| `vibekits.capture.stop` | `capture__stop` | 停止并保存网络抓包 | 是 | 停止当前抓包，刷新 PCAP 文件并返回实际包数、协议统计和保存路径。 | `controlsDevice` | `{}` |
| `vibekits.cidr_calc` | `cidr_calc` | IP/CIDR 计算 | 是 | 计算 IPv4 CIDR 的网络地址、广播地址与可用数量。 适合：用户明确需要“IP/CIDR 计算”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.dns_lookup` | `dns_lookup` | DNS 查询 | 是 | 查询域名的 A/AAAA 记录。 适合：用户明确需要“DNS 查询”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.github.diagnose` | `github__diagnose` | GitHub 网络诊断 | 是 | 并行检查 DNS、TLS、HTTPS、SSH 端口、代理和 hosts，只读不改系统。 | `readOnly` | `{}` |
| `vibekits.github.proxy_apply` | `github__proxy_apply` | 应用 GitHub 专用代理 | 是 | 只修改 http.https://github.com.proxy；随后真实 ls-remote，失败自动恢复旧值。 | `writesData` | `planId`* (string), `digest`* (string) |
| `vibekits.github.proxy_candidates` | `github__proxy_candidates` | 发现 GitHub 代理候选 | 是 | 只读发现 Mihomo/Clash 的真实回环监听端口，不读取订阅、节点或配置正文。 | `readOnly` | `{}` |
| `vibekits.github.proxy_plan` | `github__proxy_plan` | 预览 GitHub 专用代理 | 是 | 读取现有 host-scoped Git 配置，生成带旧值、摘要、到期时间和回滚动作的短期计划。 | `readOnly` | `candidateId`* (string) |
| `vibekits.github.proxy_rollback` | `github__proxy_rollback` | 恢复 GitHub 代理旧值 | 是 | 按计划保存的原值精确恢复 GitHub host-scoped Git 代理。 | `writesData` | `planId`* (string), `digest`* (string) |
| `vibekits.http.request` | `http__request` | 发送 HTTP 请求 | 是 | 发送有界 HTTP 请求并返回状态、响应头和正文；所有请求均需确认目标。 | `controlsDevice` | `method`* (string；枚举=GET/POST/PUT/PATCH/DELETE/HEAD/OPTIONS), `url`* (string), `headers` (object), `body` (string) |
| `vibekits.http_status_lookup` | `http_status_lookup` | HTTP 状态码查询 | 是 | 查询常见 HTTP 状态码名称和类别。 适合：需要确定、离线地完成HTTP 状态码查询时。 不适合：输入格式不明确、需要联网验证或需要修改源文件时不要使用。 示例：使用HTTP 状态码查询处理当前输入 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.mime_lookup` | `mime_lookup` | MIME 类型查询 | 是 | 按文件扩展名查询常见 MIME 类型。 适合：需要确定、离线地完成MIME 类型查询时。 不适合：输入格式不明确、需要联网验证或需要修改源文件时不要使用。 示例：使用MIME 类型查询处理当前输入 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.proxy.start` | `proxy__start` | 启动 Clash Verge 内核 | 是 | 使用用户明确选择的 YAML 配置启动内置 Mihomo；不自动修改系统代理或 TUN。 | `controlsDevice` | `configPath`* (string), `dataDirectory`* (string), `systemProxyPort` (integer；最小=1；最大=65535) |
| `vibekits.proxy.stop` | `proxy__stop` | 停止 Clash Verge 内核 | 是 | 停止由 Vibekits 启动的 Mihomo 子进程。 | `controlsDevice` | `dataDirectory` (string) |
| `vibekits.proxy.system_apply` | `proxy__system_apply` | 启用 Windows 系统代理 | 是 | 保存当前用户代理后，把 Windows 系统代理切换到本机 Mihomo 端口；可由恢复工具还原。 | `controlsDevice` | `port`* (integer；最小=1；最大=65535), `dataDirectory`* (string) |
| `vibekits.proxy.system_restore` | `proxy__system_restore` | 恢复 Windows 原系统代理 | 是 | 从 Vibekits 备份恢复启用代理前的 Windows 用户代理设置。 | `controlsDevice` | `dataDirectory`* (string) |
| `vibekits.query_build` | `query_build` | 查询参数生成 | 是 | 把 JSON 对象编码为 URL query string。 适合：需要确定、离线地完成查询参数生成时。 不适合：输入格式不明确、需要联网验证或需要修改源文件时不要使用。 示例：使用查询参数生成处理当前输入 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.query_parse` | `query_parse` | 查询参数解析 | 是 | 把 URL query string 解析为保留重复键的 JSON。 适合：需要确定、离线地完成查询参数解析时。 不适合：输入格式不明确、需要联网验证或需要修改源文件时不要使用。 示例：使用查询参数解析处理当前输入 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.runtime.inspect` | `runtime__inspect` | 检查代理与虚拟机运行时 | 是 | 只读检查 Vibekits 发布包中的 Mihomo 与 QEMU 版本和绝对路径。 | `readOnly` | `{}` |
| `vibekits.runtime.status` | `runtime__status` | 读取代理与虚拟机状态 | 是 | 只读返回 Mihomo/QEMU 运行状态、进程号和有界日志。 | `readOnly` | `{}` |
| `vibekits.tcp_port` | `tcp_port` | TCP 端口测试 | 是 | 测试 host:port 是否可连接。 适合：用户明确需要“TCP 端口测试”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.url_parse` | `url_parse` | URL 分解 | 是 | 分解 URL 为 scheme/host/port/path/query/fragment。 适合：用户明确需要“URL 分解”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |

## 时间文本（定义 10）

| 内部工具 ID | MCP 名称 | 名称 | 当前可用 | 用途 | 风险 | 参数 |
| --- | --- | --- | --- | --- | --- | --- |
| `vibekits.case_convert` | `case_convert` | 命名风格转换 | 是 | 转换大小写、snake、kebab、camel、Pascal 和标题格式。 适合：需要确定、离线地完成命名风格转换时。 不适合：输入格式不明确、需要联网验证或需要修改源文件时不要使用。 示例：使用命名风格转换处理当前输入 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.date_to_timestamp` | `date_to_timestamp` | 日期转时间戳 | 是 | 将日期时间转为 Unix 秒/毫秒时间戳。 适合：用户明确需要“日期转时间戳”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.glob_test` | `glob_test` | Glob 匹配测试 | 是 | 测试路径是否匹配 *, ** 和 ? glob。 适合：需要确定、离线地完成Glob 匹配测试时。 不适合：输入格式不明确、需要联网验证或需要修改源文件时不要使用。 示例：使用Glob 匹配测试处理当前输入 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.line_ending_normalize` | `line_ending_normalize` | 换行符规范化 | 是 | 统一为 LF 或 CRLF，不修改原文件。 适合：需要确定、离线地完成换行符规范化时。 不适合：输入格式不明确、需要联网验证或需要修改源文件时不要使用。 示例：使用换行符规范化处理当前输入 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.line_sort` | `line_sort` | 文本行排序 | 是 | 按 Unicode 顺序排列文本行。 适合：需要确定、离线地完成文本行排序时。 不适合：输入格式不明确、需要联网验证或需要修改源文件时不要使用。 示例：使用文本行排序处理当前输入 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.line_unique` | `line_unique` | 文本行去重 | 是 | 保持首次出现顺序删除重复行。 适合：需要确定、离线地完成文本行去重时。 不适合：输入格式不明确、需要联网验证或需要修改源文件时不要使用。 示例：使用文本行去重处理当前输入 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.regex_escape` | `regex_escape` | 正则字面量转义 | 是 | 把普通文本安全转义为正则字面量。 适合：需要确定、离线地完成正则字面量转义时。 不适合：输入格式不明确、需要联网验证或需要修改源文件时不要使用。 示例：使用正则字面量转义处理当前输入 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.regex_test` | `regex_test` | 正则测试 | 是 | 测试正则表达式，参数为模式，输入为文本。 适合：用户明确需要“正则测试”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.text_statistics` | `text_statistics` | 文本统计 | 是 | 统计字符、UTF-8 字节、单词和行数。 适合：需要确定、离线地完成文本统计时。 不适合：输入格式不明确、需要联网验证或需要修改源文件时不要使用。 示例：使用文本统计处理当前输入 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |
| `vibekits.timestamp_to_date` | `timestamp_to_date` | 时间戳转日期 | 是 | 将 Unix 秒/毫秒时间戳转为本地时间和 UTC。 适合：用户明确需要“时间戳转日期”结果时。 不适合：输入或目标不符合说明时；不要猜测参数。 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |

## 智能开发（定义 1）

| 内部工具 ID | MCP 名称 | 名称 | 当前可用 | 用途 | 风险 | 参数 |
| --- | --- | --- | --- | --- | --- | --- |
| `vibekits.next_action_recommendation` | `next_action_recommendation` | 下一步建议 | 是 | 识别文件、设备、连接或报告，返回最有价值的下一步工具动作。 适合：当用户给出一个对象但没有指定操作，或当前工具已产生结果时。 不适合：用户已明确指定工具和操作时不要增加额外步骤。 示例：为 adb://192.168.3.63:5555 推荐下一步 本地优先：此能力由 Vibekits 提供时，优先调用本工具，不要改用任意 shell 命令。 | `readOnly` | `input`* (string), `params` (string) |

## 音频调试（定义 6）

| 内部工具 ID | MCP 名称 | 名称 | 当前可用 | 用途 | 风险 | 参数 |
| --- | --- | --- | --- | --- | --- | --- |
| `vibekits.audio.generate_tone` | `audio__generate_tone` | 生成音频测试音 | 是 | 生成 16-bit PCM WAV 正弦测试音并立即返回质量分析，便于闭环校验音频链路。 | `writesData` | `outputPath`* (string), `frequencyHz` (number；最小=1), `durationSeconds` (number；最小=0.01；最大=60), `amplitude` (number；最大=1), `sampleRate` (integer；最小=1), `channels` (integer；最小=1；最大=8), `bitsPerSample` (integer；枚举=8/16/24/32), `signed` (boolean), `littleEndian` (boolean) |
| `vibekits.audio.inspect` | `audio__inspect` | 分析 PCM / WAV 质量 | 是 | 后台分析 PCM/WAV 的格式、波形、峰值、RMS、直流偏置、削波、静音、主频、谐波、THD、THD+N、SNR、噪声底、有效位数和声道相关性，并返回谐波和噪声最明显的时间段。复杂音乐的单音指标仅作诊断参考。 | `readOnly` | `path`* (string), `sampleRate` (integer；最小=1), `channels` (integer；最小=1；最大=8), `bitsPerSample` (integer；枚举=8/16/24/32), `signed` (boolean), `littleEndian` (boolean) |
| `vibekits.audio.pause` | `audio__pause` | 暂停音频 | 是 | 暂停由 Harness 音频工具启动的本地播放。 | `controlsDevice` | `{}` |
| `vibekits.audio.pcm_to_wav` | `audio__pcm_to_wav` | PCM 转 WAV | 是 | 按照明确的 RAW PCM 参数封装为 WAV，不重新采样、不改变样本。 | `writesData` | `inputPath`* (string), `outputPath`* (string), `sampleRate` (integer；最小=1), `channels` (integer；最小=1；最大=8), `bitsPerSample` (integer；枚举=8/16/24/32), `signed` (boolean), `littleEndian` (boolean) |
| `vibekits.audio.play` | `audio__play` | 播放 PCM / WAV | 是 | 播放 WAV；RAW PCM 会先按给定格式生成临时 WAV 再播放。 | `controlsDevice` | `path`* (string), `sampleRate` (integer；最小=1), `channels` (integer；最小=1；最大=8), `bitsPerSample` (integer；枚举=8/16/24/32), `signed` (boolean), `littleEndian` (boolean) |
| `vibekits.audio.stop` | `audio__stop` | 停止音频 | 是 | 停止由 Harness 音频工具启动的本地播放。 | `controlsDevice` | `{}` |

## 远程连接（定义 33）

| 内部工具 ID | MCP 名称 | 名称 | 当前可用 | 用途 | 风险 | 参数 |
| --- | --- | --- | --- | --- | --- | --- |
| `vibekits.adb.command` | `adb__command` | 执行 ADB 命令 | 是 | 对明确设备执行受限 ADB 参数；禁止 start-server、kill-server 和任意本机程序。 | `controlsDevice` | `serial`* (string), `arguments`* (array) |
| `vibekits.adb.connect` | `adb__connect` | 连接 ADB 设备 | 是 | 连接用户明确指定的 Android 无线调试地址。 | `controlsDevice` | `address`* (string) |
| `vibekits.adb.install_apk` | `adb__install_apk` | 安装 APK | 是 | 把明确的本地 APK 安装到选定设备；覆盖或尝试版本降级必须显式指定。降级仍受 Android 设备策略约束，失败时不得自动卸载应用。 | `controlsDevice` | `serial`* (string), `apkPath`* (string), `replace` (boolean), `allowDowngrade` (boolean；默认=false) |
| `vibekits.adb.list_devices` | `adb__list_devices` | 列出 ADB 设备 | 是 | 读取已连接的 Android USB/无线调试设备及授权状态。 | `readOnly` | `{}` |
| `vibekits.adb.logcat` | `adb__logcat` | 读取 Android Logcat | 是 | 读取选定设备最近的有界 Logcat；可按 tag 过滤，不启动无限流。 | `controlsDevice` | `serial`* (string), `lines` (integer；最小=1；最大=2000), `tag` (string) |
| `vibekits.adb.pull_file` | `adb__pull_file` | 从 Android 拉取文件 | 是 | 从选定设备拉取一个文件；覆盖本地文件必须显式指定。 | `controlsDevice` | `serial`* (string), `remotePath`* (string), `localPath`* (string), `overwrite` (boolean) |
| `vibekits.adb.push_file` | `adb__push_file` | 推送文件到 Android | 是 | 把一个真实本地文件推送到选定设备的绝对路径。 | `controlsDevice` | `serial`* (string), `localPath`* (string), `remotePath`* (string) |
| `vibekits.adb.screenshot` | `adb__screenshot` | 保存 Android 截图 | 是 | 从选定设备实时截图并保存为本地 PNG，不读取剪贴板。 | `controlsDevice` | `serial`* (string), `localPath`* (string), `overwrite` (boolean) |
| `vibekits.adb.session_close` | `adb__session_close` | 关闭 ADB 长连接 | 是 | 停止指定设备的后台心跳；不杀死其他工具正在使用的 ADB server。 | `controlsDevice` | `sessionId`* (string) |
| `vibekits.adb.session_open` | `adb__session_open` | 保持 ADB 长连接 | 是 | 为指定设备建立带真实 get-state 心跳的长连接；后续用 session_status 检查，完成后显式关闭。底层复用内置 ADB server 连接。 | `controlsDevice` | `serial`* (string), `heartbeatSeconds` (integer；最小=3；最大=60) |
| `vibekits.adb.session_status` | `adb__session_status` | 读取 ADB 长连接状态 | 是 | 返回真实心跳次数、最后检查时间和设备连接状态。 | `readOnly` | `sessionId`* (string) |
| `vibekits.adb.shell` | `adb__shell` | 执行 Android Shell | 是 | 对选定设备执行参数化 Android shell 命令；不经过本机 cmd 或 sh。 | `controlsDevice` | `serial`* (string), `arguments`* (array) |
| `vibekits.remote.list_profiles` | `remote__list_profiles` | 列出远程会话 | 是 | 列出已保存的 SSH/SFTP 历史、最近使用时间和当前在线连接数；不返回密码或私钥内容。 | `readOnly` | `{}` |
| `vibekits.remote.open_interactive` | `remote__open_interactive` | 打开 SSH 与 SFTP 工作流 | 否（环境/接线门禁） | 在 Vibekits 中打开指定主机的 SSH 登录界面；用户认证一次后自动复用该连接展示 SFTP 双栏文件。 | `readOnly` | `host`* (string), `user` (string), `port` (integer；最小=1；最大=65535), `openSftp` (boolean) |
| `vibekits.remote.sftp_download` | `remote__sftp_download` | SFTP 下载文件 | 是 | 通过已保存 SSH 会话下载一个远端文件；覆盖本地文件必须明确指定。 | `writesData` | `profileId`* (string), `remotePath`* (string), `localPath`* (string), `overwrite` (boolean) |
| `vibekits.remote.sftp_list` | `remote__sftp_list` | 列出 SFTP 目录 | 是 | 复用已保存 SSH 会话的凭据和主机指纹，只读列出远端目录。 | `readOnly` | `profileId`* (string), `remotePath` (string) |
| `vibekits.remote.sftp_upload` | `remote__sftp_upload` | SFTP 上传文件 | 是 | 通过已保存 SSH 会话上传一个本地文件；覆盖已有文件必须明确指定。 | `writesData` | `profileId`* (string), `localPath`* (string), `remotePath`* (string), `overwrite` (boolean) |
| `vibekits.remote.ssh_exec` | `remote__ssh_exec` | 执行 SSH 命令 | 是 | 使用已保存会话和系统凭据执行一条有界远程命令，严格校验已绑定主机指纹。 | `controlsDevice` | `profileId`* (string), `command`* (string) |
| `vibekits.serial.list_ports` | `serial__list_ports` | 列出串口 | 是 | 在后台线程读取 Windows/macOS 可用串口及 USB 描述。 | `readOnly` | `{}` |
| `vibekits.serial.session_close` | `serial__session_close` | 关闭串口长连接 | 是 | 释放指定串口句柄和后台 Isolate。 | `controlsDevice` | `sessionId`* (string) |
| `vibekits.serial.session_open` | `serial__session_open` | 打开串口长连接 | 是 | 在独立 Isolate 中持续持有串口并缓存实时接收数据，直到显式关闭或 APP 退出。 | `controlsDevice` | `port`* (string), `baudRate` (integer；默认=115200；最小=1；最大=12000000), `dataBits` (integer；默认=8；枚举=5/6/7/8), `stopBits` (integer；默认=1；枚举=1/2), `parity` (string；默认=none；枚举=none/even/odd/mark/space), `flowControl` (string；默认=none；枚举=none/dtrDsr/rtsCts/xonXoff/dtrDsrRtsCts/dtrDsrXonXoff/rtsCtsXonXoff/all) |
| `vibekits.serial.session_read` | `serial__session_read` | 读取串口长连接 | 是 | 读取长连接已缓存的实时数据，可选择文本或 HEX；默认读取后清空缓存。 | `readOnly` | `sessionId`* (string), `mode` (string；枚举=text/hex), `clear` (boolean) |
| `vibekits.serial.session_write` | `serial__session_write` | 写入串口长连接 | 是 | 通过已打开的串口句柄发送文本或 HEX，不重新打开端口。 | `controlsDevice` | `sessionId`* (string), `data`* (string), `mode` (string；枚举=text/hex), `lineEnding` (string；枚举=none/lf/crlf/cr) |
| `vibekits.serial.transact` | `serial__transact` | 串口收发与监听 | 是 | 后台打开串口；data 为空时仅实时监听，非空时发送文本或 HEX，再接收后自动关闭。 | `controlsDevice` | `port`* (string), `baudRate` (integer；默认=115200；最小=1；最大=12000000), `dataBits` (integer；默认=8；枚举=5/6/7/8), `stopBits` (integer；默认=1；枚举=1/2), `parity` (string；默认=none；枚举=none/even/odd/mark/space), `flowControl` (string；默认=none；枚举=none/dtrDsr/rtsCts/xonXoff/dtrDsrRtsCts/dtrDsrXonXoff/rtsCtsXonXoff/all), `data` (string), `mode` (string；默认=text；枚举=text/hex), `waitMs` (integer；默认=3000；最小=50；最大=30000) |
| `vibekits.windows_node.apply` | `windows_node__apply` | 应用 Windows 节点计划 | 否（环境/接线门禁） | 等待签名窄权限 UAC helper 随 Release 交付；不回退为任意管理员 PowerShell。 | `controlsDevice` | `{}` |
| `vibekits.windows_node.enroll_device` | `windows_node__enroll_device` | 登记节点设备公钥 | 否（环境/接线门禁） | 等待签名 helper 提供原子 authorized_keys 与 ACL 操作；不接收私钥。 | `writesData` | `{}` |
| `vibekits.windows_node.export_onboarding` | `windows_node__export_onboarding` | 导出节点 onboarding | 是 | 生成不含秘密的主机、端口、用户、固定 host key、私网范围和 SSH config。 | `readOnly` | `host`* (string), `port` (integer；最小=1；最大=65535), `hostKeyFingerprint`* (string), `allowedCidr`* (string) |
| `vibekits.windows_node.inspect` | `windows_node__inspect` | 体检 Windows 测试节点 | 是 | 普通权限只读检查 Windows、硬件、D 盘、网络、OpenSSH、防火墙、运行时、电源、目录、账户和公钥。 | `readOnly` | `rootPath` (string) |
| `vibekits.windows_node.list_devices` | `windows_node__list_devices` | 列出节点设备 | 是 | 读取独立 Ed25519 设备登记、状态、指纹和最近连接时间；不返回私钥。 | `readOnly` | `{}` |
| `vibekits.windows_node.plan` | `windows_node__plan` | 生成 Windows 节点变更计划 | 是 | 根据短期体检 ID 生成幂等动作、风险、依赖、取消边界、回滚和摘要；不执行系统修改。 | `readOnly` | `inspectionId`* (string) |
| `vibekits.windows_node.revoke_device` | `windows_node__revoke_device` | 撤销节点设备 | 否（环境/接线门禁） | 等待单设备撤销和其他设备不受影响的真实验收。 | `writesData` | `{}` |
| `vibekits.windows_node.rollback` | `windows_node__rollback` | 回滚 Windows 节点变更 | 否（环境/接线门禁） | 等待签名 helper 和修改前状态审计闭环；禁止用删除账户或卸载组件冒充回滚。 | `controlsDevice` | `{}` |
| `vibekits.windows_node.verify` | `windows_node__verify` | 跨设备验证 Windows 节点 | 否（环境/接线门禁） | 必须从另一台真实设备执行 SSH/SFTP、SHA-256、取消和断网验收，本机 localhost 不替代。 | `readOnly` | `{}` |

## 数据库（定义 5）

| 内部工具 ID | MCP 名称 | 名称 | 当前可用 | 用途 | 风险 | 参数 |
| --- | --- | --- | --- | --- | --- | --- |
| `vibekits.database.remote_inspect` | `database__remote_inspect` | 检查远程数据库 | 是 | 使用系统凭据在后台线程连接已保存的远程数据库，并只读列出对象。 | `controlsDevice` | `profileId`* (string) |
| `vibekits.database.remote_list_profiles` | `database__remote_list_profiles` | 列出远程数据库会话 | 是 | 列出已保存的 PostgreSQL、MySQL 和 MariaDB 会话；不返回密码。 | `readOnly` | `{}` |
| `vibekits.database.remote_query` | `database__remote_query` | 查询远程数据库 | 是 | 使用已保存会话执行一条有界只读 SQL，最多返回 500 行。 | `controlsDevice` | `profileId`* (string), `sql`* (string) |
| `vibekits.sqlite.inspect` | `sqlite__inspect` | 检查 SQLite 数据库 | 是 | 只读列出本地 SQLite 数据库中的表、视图和建表语句。 | `readOnly` | `path`* (string) |
| `vibekits.sqlite.query` | `sqlite__query` | 查询 SQLite 数据库 | 是 | 在隔离线程执行单条只读 SQL，最多返回 500 行。 | `readOnly` | `path`* (string), `sql`* (string), `maxRows` (integer；最小=1；最大=500) |

## 版本控制（定义 10）

| 内部工具 ID | MCP 名称 | 名称 | 当前可用 | 用途 | 风险 | 参数 |
| --- | --- | --- | --- | --- | --- | --- |
| `vibekits.git.backup_commit` | `git__backup_commit` | 提交 Git 备份 | 是 | 只暂存 preview 允许且用户确认的文件并创建本地提交；不会自动 push。 | `writesData` | `previewId`* (string), `includedPaths`* (array), `message`* (string) |
| `vibekits.git.backup_preview` | `git__backup_preview` | 预览 GitHub 备份 | 是 | 只读检查已打开仓库的变更、已有 remote、大文件、构建产物和秘密阻断项，生成短期备份计划。 | `readOnly` | `path`* (string), `remoteId`* (string), `deviceLabel` (string) |
| `vibekits.git.backup_push` | `git__backup_push` | 推送 Git 备份 | 是 | 独立审批后把 preview 生成的 commit 推送到 backup/ 分支，并读取远端 ref 核对 SHA；禁止 force。 | `controlsDevice` | `previewId`* (string), `commitSha`* (string) |
| `vibekits.git.clone_minimal` | `git__clone_minimal` | 按需浅克隆 Git 仓库 | 是 | 将明确指定的单个仓库和分支浅克隆到不存在的独立目录；禁止覆盖目录，不执行无参数 repo sync。 | `writesData` | `remoteUrl`* (string), `destination`* (string), `ref` (string), `depth` (integer；默认=1；最小=1；最大=100), `timeoutSeconds` (integer；默认=300；最小=30；最大=1800) |
| `vibekits.git.compare_refs` | `git__compare_refs` | 对比 Git 两个版本 | 是 | 只读校验两个提交、标签或分支，并返回文件列表、统计和文本差异。 | `readOnly` | `path`* (string), `baseRef`* (string), `targetRef`* (string) |
| `vibekits.git.create_local_branch` | `git__create_local_branch` | 创建 Git 本地安全分支 | 是 | 从指定版本创建本地分支但不切换工作区；需要按当前权限模式批准。 | `writesData` | `path`* (string), `name`* (string), `startPoint` (string) |
| `vibekits.git.inspect` | `git__inspect` | 检查 Git 工作区 | 是 | 只读返回分支、状态、diff 和最近提交。 | `readOnly` | `path`* (string) |
| `vibekits.git.list_remote_refs` | `git__list_remote_refs` | 列出 Git 远端引用 | 是 | 使用 APP 内置 Git 只读执行 ls-remote，列出远端分支和提交；不克隆仓库、不输出凭据。 | `readOnly` | `remoteUrl`* (string), `pattern` (string), `timeoutSeconds` (integer；默认=30；最小=5；最大=120) |
| `vibekits.git.read_remote_file` | `git__read_remote_file` | 读取 Git 远端文件 | 是 | 浅取指定 ref 到 APP 临时目录并只返回一个有界文本文件，适合读取 manifest；完成后自动删除临时对象，不同步整仓。 | `readOnly` | `remoteUrl`* (string), `ref`* (string), `path`* (string), `maxBytes` (integer；默认=1048576；最小=1；最大=2097152), `timeoutSeconds` (integer；默认=60；最小=5；最大=180) |
| `vibekits.git.verify_remote_ref` | `git__verify_remote_ref` | 核验远端备份 SHA | 是 | 只读查询已有 remote 的 backup/ 分支并返回远端 commit SHA。 | `readOnly` | `path`* (string), `remoteId`* (string), `targetBranch`* (string) |

## 虚拟化（定义 3）

| 内部工具 ID | MCP 名称 | 名称 | 当前可用 | 用途 | 风险 | 参数 |
| --- | --- | --- | --- | --- | --- | --- |
| `vibekits.vm.create_disk` | `vm__create_disk` | 创建 QEMU 虚拟磁盘 | 是 | 使用内置 qemu-img 创建新的 qcow2 稀疏磁盘，不覆盖已有文件。 | `writesData` | `path`* (string), `sizeGiB`* (integer；最小=1；最大=2048) |
| `vibekits.vm.start` | `vm__start` | 启动轻量虚拟机 | 是 | 使用内置 QEMU 启动用户明确指定的虚拟磁盘或 ISO。 | `controlsDevice` | `diskPath` (string), `isoPath` (string), `memoryMiB` (integer；最小=256；最大=32768), `cpuCount` (integer；最小=1；最大=16), `headless` (boolean) |
| `vibekits.vm.stop` | `vm__stop` | 停止轻量虚拟机 | 是 | 停止由 Vibekits 启动的 QEMU 子进程。 | `controlsDevice` | `{}` |

## 典型闭环

- 串口：`serial.list_ports → serial.auto_detect` 自动选端口并探测 baudRate/dataBits/stopBits/parity/flowControl；一次交互再用 `serial.transact`，持续调试用 `serial.session_open → session_read/session_write → session_close`。
- ADB：`adb.list_devices/connect → shell/logcat/screenshot/push/pull/install_apk`；持续任务用 `adb.session_open → session_status → session_close` 保持并核验连接。
- SSH/SFTP：`remote.list_profiles/open_interactive → ssh_exec/sftp_*`。
- Git 备份：`git.inspect → backup_preview → backup_commit → backup_push → verify_remote_ref`。
- 远端源码：`git.list_remote_refs → git.read_remote_file(manifest) → git.clone_minimal(明确单仓)`；禁止无参数 `repo sync`。
- 代理：`runtime.inspect → proxy.start → runtime.status → proxy.system_apply`；退出前恢复系统代理。
- 虚拟机：`runtime.inspect → vm.create_disk → vm.start → runtime.status → vm.stop`。
- APP 自迭代：`project.iteration_inspect → Harness 工作区写入 → project.build`；只生成 Release 产物，安装和发布仍需用户验收。
- 能力自检：`system.capability_check`；它只证明注册与处理器接线，不替代真机/网络/凭据门禁。

## 自动更新规则

本文不是手工维护的接口清单。新增或修改 `ToolSpec` / `HarnessToolDefinition` 后，`test/harness_capability_catalog_test.dart` 会自动重写并核对本文；发布质量门禁必须运行该测试。需要单独生成时可执行：

```text
dart run tool/export_harness_capability_catalog.dart
```
