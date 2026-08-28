# Vibekits

> 智能体理解工具、调用工具、验证结果的本地开发工作台。

Vibekits 面向程序员、设备调试工程师和技术团队，把 Harness 智能体与本机确定性工具放进同一个任务上下文。用户不需要先判断该打开哪个小工具：描述目标、拖入文件或选择设备后，智能体会发现可用能力、读取精确参数、调用工具取得真实结果，再组合下一步操作。

它不是“小工具集合 + 聊天框”。Vibekits 的目标是让智能体成为工具的使用者和协调者，同时保留专业工具应有的可见界面、手工控制、权限边界、实时日志和可复核证据。

## 为什么做 Vibekits

传统开发工具通常彼此孤立：SSH 登录后还要重新配置 SFTP；下载 APK 后还要寻找 ADB；串口、Logcat、截图、OCR 和源码分析之间没有上下文；大模型知道应该做什么，却无法安全、准确地操作本地工具。

Vibekits 把这条链连接起来：

```text
用户目标 / 拖入对象
        ↓
Harness 理解意图并发现工具
        ↓
读取 Schema、自动发现参数、确认权限
        ↓
后台执行本地工具并记录真实日志
        ↓
结构化结果进入下一个工具或交给模型解释
        ↓
设备 / 文件 / 系统侧验证，形成闭环报告
```

## 智能体如何理解和使用工具

每项正式能力不是一句提示词，而是一份机器可读合同：

- **稳定工具 ID**：例如 `vibekits.network.download`、`vibekits.adb.install_apk`。
- **用途说明**：告诉智能体适用场景、不适用场景和本地优先规则。
- **JSON Schema**：定义必填参数、默认值、枚举、范围和返回结构，避免模型猜字段。
- **风险等级**：区分只读、写数据、控制设备和破坏性操作，并应用真实权限策略。
- **目标摘要**：授权时展示具体设备、文件、URL、仓库或远程主机。
- **执行证据**：返回状态、耗时、哈希、设备输出和证据来源，不把“接口存在”当成“任务成功”。
- **模块日志**：默认记录 Harness 的真实工具调用，可查看、定位失败和删除；密码、API Key、Token 与文件正文不会进入普通日志。

Harness 可以先调用：

- `vibekits.system.capability_check`：检查当前版本实际定义和可执行的工具。
- `vibekits.system.describe_tool`：读取某个工具的精确参数，不凭记忆回答。
- `vibekits.harness.diagnostics`：发生启动超时或工具失败时读取脱敏诊断证据。

新增工具会从同一注册表自动进入界面、Harness、外部 MCP、能力文档和合同测试，不需要在多处手工维护另一份“模型工具列表”。当前 `v1.9.0-dev.135` 快照包含 **168 个定义接口**，本次 Windows 实机运行时有 **148 个可执行接口**；依赖硬件、平台或签名 Helper 的能力会明确标为不可用，不向智能体宣传假能力。不同平台的可执行数可能不同，始终以运行时 `capability_check` 为准。

## 当前工具集合

### 智能体与视觉

- 官方 DeepSeek Harness 工作区：项目、会话、权限、工具轨迹和推理中间态。
- DeepSeek 模型配置与安全凭据存储。
- PP-OCRv6：截图识别、文字框、像素坐标、归一化坐标、阅读顺序和区域语义。
- Harness 调试目录、工作日志、诊断日志与可清理建议。

### Android 与硬件调试

- 内置 ADB：USB/无线发现、连接、Shell、Logcat、文件推送/拉取、截图、APK 安装和长连接心跳。
- 串口：端口枚举、USB 描述、自动探测波特率/数据位/停止位/奇偶校验/流控、文本或 HEX 收发、长连接实时读取。
- Android 资源诊断：CPU、内存、GPU、存储、Top 进程和连续采样。
- Android 单屏、双屏与 1920×2560 连续异显画布适配。

### 远程开发与数据库

- SSH 终端、保存会话、主机指纹校验和多设备并存。
- SFTP 双栏文件管理，与 SSH 复用同一认证，不重复输入密码。
- 本地/远程/SOCKS5 端口转发与远程桌面入口。
- SQLite 本地数据库与远程数据库连接、结构检查和有界查询。

### 网络开发

- HTTP/API 调试与通用网络文件下载。
- 网络下载返回绝对路径、HTTP 状态、字节数和 SHA-256；APK 会额外校验容器签名。
- Clash Verge 风格代理工作区：订阅、节点、测速、规则/全局/直连、连接、流量和系统代理恢复。
- GitHub 网络诊断与可回滚的 GitHub 专用代理。
- PCAP 网络抓包、保存、读取、过滤和端点/协议分析。

### 文件、代码与版本控制

- 文件 Diff、哈希、搜索、重复文件、批量重命名和代码统计。
- JSON/YAML/TOML/XML/CSV、编码、加密、时间文本等高频确定性微工具。
- 内置 MinGit：仓库检查、版本差异、本地分支、安全提交、已有远端备份与 SHA 验证。
- Gerrit/远端 Git：列出远端 refs、读取指定 ref 的单个 manifest 文件、按明确仓库浅克隆；禁止隐式整包同步。
- 网络下载结果可直接传递给 ADB、文件哈希或其他能力，不要求用户重新选择文件。

### 压缩、文档与媒体

- 7-Zip 内核运行时：ZIP、7z、RAR、TAR、GZIP、BZIP2、XZ、ZSTD、CAB、ISO、WIM、DMG 等格式的列表、预览和解压。
- Markdown、代码、文本、图片、PDF 和常用办公文档阅读入口；拖入文件自动选择最合适的处理方式。
- PCM/WAV 波形、播放、格式识别、峰值、RMS、频谱、谐波、THD、THD+N、SNR、噪声底、削波、静音和直流偏置分析。

### 系统与工程环境

- Windows/macOS/Android 的 CPU、内存、GPU、磁盘和进程资源诊断。
- Windows/macOS/Android 独立清理策略；扫描、空间归属、软件缓存、日志、清理建议、取消、真实释放量和历史报告。
- 程序员计算器：HEX/DEC/OCT/BIN、位运算、字宽和有符号/无符号解释。
- 轻量虚拟机（QEMU）与系统代理运行时。
- Windows 测试节点、项目构建、自迭代检查和受控发布辅助能力。

## 跨工具工作流

Vibekits 的价值来自组合，而不只是工具数量。

### 从 URL 到 Android 真机

```text
network.download
  → adb.connect / list_devices
  → adb.install_apk
  → adb.shell / logcat 验证
```

在 `v1.9.0-dev.134` 的真实验收中，Harness 下载了 24,729,270 字节的 KEMI-PAD APK，校验 SHA-256，连接 `192.168.3.53:5555`，识别 `huanglong` 设备，并通过内置 ADB 完成 `install -r -d`，设备返回 `Success`。

### SSH 与 SFTP 联动

```text
保存的 SSH 会话
  → 主机指纹确认与登录
  → SFTP 自动复用认证
  → 上传 / 执行 / 下载
  → 哈希或 Diff 验证
```

### 硬件问题定位

```text
serial.list_ports / auto_detect
  + adb.logcat / system.resources
  + screenshot / OCR
  → Harness 关联时间线
  → 解释重启、异常日志或界面状态
```

### 音频质量分析

```text
拖入 PCM/WAV
  → 格式与波形
  → 频谱、谐波、THD+N、SNR
  → 定位异常时间段
  → Harness 结合设备和代码上下文解释原因
```

## 安全与体验原则

- **本地优先**：能由本机确定性工具完成的任务，不上传到模型猜测。
- **最少操作**：可枚举、可读取、可安全试探的参数由智能体自动配置；只询问账号身份、秘密、业务目标和破坏性确认。
- **界面先响应**：页面先出现，模型、扫描、下载和设备任务在后台执行；其他功能不因单个模块离线而失效。
- **权限真实生效**：请求批准、会话批准和完全访问对应真实执行策略，不只是界面文字。
- **结果可审计**：每次工具调用有目标、参数摘要、状态、耗时和有界结果；用户可以关闭或删除日志。
- **平台隔离**：Windows、macOS、Android 的路径、凭据、清理和设备能力分别实现，禁止拿桌面规则直接删除移动端文件。
- **生命周期完整**：APP 退出时回收自身启动的进程、端口和设备会话；明确需要后台持续工作的服务采用独立生命周期。

## 外部智能体接入

Vibekits 同一套能力也可以通过本地 stdio MCP 提供给 Codex、Claude Desktop、Cursor、VS Code 智能体等客户端：

```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -File <VIBEKITS_ROOT>\tool\start_vibekits_mcp.ps1
```

工具服务器只监听本机环回地址，使用临时 Bearer Token；外部智能体不接触 Harness API Key。完整配置、工具映射和参数目录见 [Harness/MCP 能力目录](docs/37_HARNESS_CAPABILITY_CATALOG.md)。

## 平台状态

| 平台 | 当前状态 |
| --- | --- |
| Windows | 主要研发与真实联调平台；Release、内置运行时、ADB/串口/SSH/代理/虚拟机/清理等持续验收 |
| Android | ARM64 真机、Pad 触控、单/双屏异显、ADB 设备工作流和 Android 安全存储/清理持续验收 |
| macOS | 独立路径与安全边界已实现；通过 macOS CI/仿真构建门禁，正式分发仍需 Developer ID 签名和公证 |

## 构建与文档

项目基于 Flutter。开发环境准备完成后：

```powershell
flutter pub get
flutter test
flutter build windows --release
```

Windows Release 还需运行项目提供的运行时准备与打包校验脚本。请从以下文档开始：

- [统一产品需求](docs/00_PRODUCT_REQUIREMENTS.md)
- [统一开发文档索引](docs/README.md)
- [能力融合与智能体自动发现最高准则](docs/22_CAPABILITY_INTEGRATION_STANDARD.md)
- [智能体原生产品与持续演进规范](docs/33_AGENT_NATIVE_PRODUCT_AND_EVOLUTION.md)
- [全部工具的智能体闭环验收准则](docs/35_HARNESS_ALL_CAPABILITY_ACCEPTANCE.md)
- [外部智能体 MCP 与 Harness 工具接口目录](docs/37_HARNESS_CAPABILITY_CATALOG.md)
- [第三方组件与供应链记录](docs/16_THIRD_PARTY_COMPONENTS.md)

## 当前阶段

Vibekits 仍处于快速开发阶段。工具“已注册”不等于目标环境“已验收”；硬件、远程服务、系统权限和跨平台能力必须保留真实证据。当前实现、已知边界和发布门禁以 [发布完成清单](docs/17_RELEASE_COMPLETION_CHECKLIST.md) 与 `docs/acceptance/` 中的验收记录为准。
