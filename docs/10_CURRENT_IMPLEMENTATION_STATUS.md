# Vibekits 当前实现状态与未完成清单

> 当前研发顺序与逐项关闭状态以 [发布完成清单](17_RELEASE_COMPLETION_CHECKLIST.md) 为唯一执行入口；早期 Windows/UI 矩阵保留为用例库。

更新日期：2026-08-26

当前版本：`1.9.0-dev.118+128`（Android 63 Harness 全目录与 Pad 触控检查点，非正式发布）

## 2026-08-26 当前增量状态

- Android ARM64 Release 已在 `192.168.3.63:5555` 安装：五个一级入口、1920×2560 连续双屏、局域网扫码 Key、触控工具列表和一键 Harness 任务均有真机证据。
- 移动 Harness 现可发现全部 130 个公开接口；文件、HTTP、SSH/SFTP 和远程数据库等跨平台能力直接执行，依赖 Windows 进程/驱动的能力返回结构化 `requiresDesktopNode`，不再因移动过滤而让模型误判“没有该工具”。
- 自动化 118/118 通过，最终 APK SHA-256 为 `3B78EA49EFD31790B6A409D50C33CD0ECAAB14354AB485FAC37074819F6F94B9`。
- 尚未完成 Android→桌面节点远程执行传输；真实模型联调还需通过 Pad 扫码写入 DeepSeek Key。两项均在 dev.118 验收报告中明确标为门禁。

## 2026-08-24 当前增量状态

- dev.93 已纠正此前“双 Activity 异显”的方向：默认跨屏现在是唯一 `MainActivity`、唯一 Flutter Engine/View 和唯一状态树运行一张 `1920×2560` 连续画布；D2 显示 `Y=0..1279`，D0 显示 `Y=1280..2559`。
- D2 使用 Presentation 复用源 FlutterView 绘制并转发触摸；在 D2 点击 OCR 后，两屏同步显示同一 OCR 页面上下区段。D2 退出会同时关闭 Activity 与 Presentation，但不强杀独立后台服务。
- `192.168.3.62:5555` 已完成连续显示、跨屏触摸、单 Activity、双屏退出与重启恢复真机验收；合同测试 5/5、Analyze 0 问题、ARM64 Release 构建通过。
- 一级工作区、开发工具独立入口和远程功能页统一采用“中文用途（标准英文缩写/产品名）”，例如“安卓调试（ADB）”“远程连接（SSH/SFTP）”“网络代理（Clash Verge）”，避免同一列表中纯中文、纯英文混排。
- 智能体与 OCR 入口统一为“智能体（Harness）”“截图识别（OCR）”；JSON、Base64 等微工具继续保留“标准名 + 中文动作”，兼顾中文可读性与工程师搜索习惯。
- 新增工具命名契约测试，后续新增独立工具若缺少中文用途或英文标识会直接测试失败。

## 2026-08-22 当前增量状态

- Windows 固定 Release 入口已更新为 `dev.70+80`，不再把源码版本或被旧进程锁住的历史 EXE 当成交付完成。Harness 启动日志取消逐块强制刷盘，诊断 UI 合并刷新，运行时发现缓存且不重复写相同补丁。实机热启动 DSH 本体为 3.886～4.192 秒，端到端约 5.650 秒；稳定 3 秒目标仍未通过，详见 dev.70 验收报告。
- Android 12 arm64 Release 已在 `192.168.3.63:5555` 构建、安装和启动；三次冷启动平均 716 ms，稳定 PSS 约 102 MB，强制退出后无残留。移动端不再启动桌面 MCP/拖放/文件关联，并只挂载当前重型工作区。
- Android dev.79 已将桌面顶部工作区条替换为 Material 3 底部导航，系统返回优先返回上一个工作区；Harness Key 新增一次性局域网二维码网页输入并接入 Android Keystore AES-GCM 安全存储。模型、下载和 Harness 调试目录改用应用 files/cache 沙箱。
- Android 全功能复核仍有未完成项：桌面专属系统清理、ADB host、串口、Git/SSH 原生进程、Mihomo 和 QEMU 需要逐项改为手机本地实现或“连接桌面节点”，不能把当前可编译状态等同于全部移动能力已验收。
- macOS 14 Runner 已完成真实 Release 构建、压缩、SHA-256 和 Artifact 上传（Run `32542306872`，53,000,834 字节）。未签名构建通过不等于 Developer ID 签名及公证完成。
- Clash Verge / 虚拟机固定显示在开发工具左侧第二项。Windows Release 内置 Mihomo/QEMU；系统代理具备保存、确认应用、失败回滚和恢复原值，QEMU 可创建 qcow2 并启动已有磁盘/ISO。Harness 真实调用闭环已通过。
- ADB 已从三个通用入口扩展为可被 Harness 自动选择的 Shell、Logcat、APK 安装、推送、拉取和截图语义接口；界面、工具清单、审批与真实活动日志使用同一注册源。
- `192.168.3.63:5555` 已通过 APP 的 Harness bridge 实测连接、枚举、APK 安装、Shell、Logcat、文件往返校验和截图，不是直接终端绕过。大 APK 安装使用 5 分钟有界超时，完成或失败都会释放进程。
- Windows 安装器/签名、真实串口硬件、真实远程数据库与多服务矩阵、macOS 签名公证、清理实际安全释放 10 GiB 仍未闭环；这些依赖证书、设备、服务或可确认清理对象，不能用模拟结果替代。

Windows 已真实验证 RustDesk 官方客户端 `--get-id` 和当前自建 `/web` HTTP 200。最终仍需从另一台设备的浏览器完成一次真实远程控制会话，本机代码不将该外部证据伪装成已通过。

目标平台：Windows x64；Android arm64；macOS arm64/x64 工程基线

## 1. 当前结论

Windows 已形成可构建、可启动、可自动路由的开发者工具融合器。R9 的远程会话、SSH、SFTP、后台转发和系统桌面软件主路径已完成；ADB 工作区已进入代码并完成官方路径/版本识别、设备状态和命令操作层。项目随包 ADB 已通过无线目标 `192.168.3.63:5555` 完成真实连接、安装和命令验证；USB 连接、SSH/SFTP/转发和桌面真实目标证据仍待补。macOS 工程已接入，但当前机器不是 macOS，不能把未执行的 Xcode/arm64 与真实设备验证写成完成。

Android arm64 Release 已在 `192.168.3.63:5555`（Android 12）完成安装、冷/热启动和程序员计算器真实操作。Android 首次启动进入开发工具，避免依赖 Windows 专属 DSH Web/Node 运行时。该结论不代表桌面 Harness、ADB、Git、Mihomo、QEMU 已移植到 Android；移动端能力矩阵仍需逐项实现和验收。

网络与虚拟化工作区已接入 Mihomo/QEMU 私有运行时解析、独立进程启停、PID/日志状态和 Harness 九项接口。Windows 系统代理旧值恢复、虚拟磁盘创建已完成；TUN、虚拟机快照及 macOS 双架构签名仍未完成，不写成已验收。

## 2. 五个主工作区

| 工作区 | 当前能力 | 状态 |
|---|---|---|
| 解压缩 | 官方 7-Zip 26.02 + Dart 后端；RAR/RAR5、ZIP/ZIPX、7z、TAR、GZ/BZ2/XZ/ZST、CAB、ISO/WIM/DMG 等列表/解压；路径、链接、空间、大小、压缩比、冲突、暂存、取消保护 | Windows 主路径完成 |
| 系统清理 | 五个用户任务入口；Windows 内置规则库 v10（31+ 条）+ 随包外部规则库 v6（23 条）与 macOS v1（26 条）；显式风险/影响；`C:\ESTLOG`、跨用户瞬态发现；全部磁盘容量和逐盘后台分析 | APP 双 Isolate 实机只读扫描发现 11.284 GiB，本机安全验收计划约 11.28 GiB；批量回收与最终清空已分两阶段；真实永久释放仍等待用户对具体范围及不可恢复清空的明确授权 |
| 文档阅读 | 全部注册格式按类别可查看；Markdown 默认预览；打开后可关闭；最近打开跨重启保存并可清空；源码识别、查找、编辑、原子保存；结构化数据、Web/EPUB/SVG；大文本与大 BIN 窗口化 | Windows 主路径完成 |
| 开发工具 | 左侧只保留计算器、数据库、串口、远程、ADB、API、Git、文件搜索/哈希/重命名/重复文件等独立工作区；编码、格式、时间、正则、网络微工具合并到“转换与检查”的右侧分类 Tab | 数据库、串口、SSH/SFTP/转发/系统桌面主路径完成；ADB 路径/设备层完成，操作层待继续 |
| Harness（智能体） | 一级导航第 1 项；Windows 直接嵌入官方 DeepSeek Harness Web；官方工作区/多会话/模型/权限/任务/工具轨迹为唯一数据源；OCR 为同页辅助入口 | 开发工具左侧每个入口均有可执行适配器；新增 Harness→SSH→一次认证→自动 SFTP，以及 Harness→框选截图→离线 OCR→结构化结果回传；真实外部服务与 macOS 仍待验证 |

## 3. 文件融合与系统入口

- 窗口拖入、文件选择、启动参数、Windows 打开方式/右键和 macOS Open With 共用内容路由。
- 文件头优先识别压缩、图片和 SQLite；扩展名命中专用工具；其他内容自动选择文本或 Hex，不静默忽略普通文件。
- 多文件保留完整批次并逐项显示识别结果；单个文件直接进入最佳工作区。
- Markdown 进入渲染预览；图片进入预览/OCR；SQLite 以只读模式打开；模型先校验再导入；`.bin` 和未知二进制进入 Hex。
- Windows 注册文档、压缩、图片、数据库和模型 ProgID；任意文件右键提供“用 Vibekits 自动处理”，已知类型提供专用动作，不抢占默认应用。
- macOS 工程声明 `public.data` Viewer，原生层在 Dart 就绪前排队文件 URL，随后通过同一通道成批转交。

## 4. 程序员工具细节

### 4.1 程序员计算器

支持十/十六/八/二进制字面量，括号、算术、按位、移位，8/16/32/64/128 位和有符号/无符号解释；输入后直接得到多进制结果。

### 4.2 SQLite 与远程数据库管理器

按 SQLite Magic 和常见扩展路由；默认只读，`query_only`、`trusted_schema=OFF`、DQS 关闭；表/视图、100 行分页、最多 500 行查询结果、BLOB/NULL 显示。每个请求使用短生命周期 Isolate，8 秒超时可终止；预编译语句确认只读后才执行。

PostgreSQL、MySQL 和 MariaDB 已接入 TLS/非 TLS 连接、对象列表、100 行分页和最多 500 行只读查询；数据库类型切换会给出主流默认端口/用户/数据库。连接资料自动进入最近记录，密码直接写入 Windows Credential Manager/macOS Keychain，普通设置不含密码；记录可一键删除并同时删除系统凭据。每次远程操作在短生命周期 Isolate 中运行，15 秒超时，可停止并立即杀掉工作 Isolate/网络连接。Windows 已执行临时凭据写入、读取和删除真实闭环；本机没有可用 MySQL/MariaDB 服务，因此成功连接仍待真实服务器补证，当前以驱动参数、真实 TCP 握手阻塞/取消和 Widget 会话覆盖。

### 4.3 串口调试

串口工作区按“端口、波特率、打开”三项完成首屏主操作，数据位、校验位、停止位和流控折叠在高级设置。支持可编辑波特率、文本/HEX 收发、CR/LF/CRLF、发送历史、带方向时间戳的 RX/TX 日志、清空和后台保存；参数跨重启保留但不会静默打开设备。

端口枚举和完整会话由独立 Isolate 持有 `libserialport` 原生句柄，UI 以 100ms 批次接收数据，日志限制为 2MiB/2000 条。关闭先立即恢复界面，再在后台释放句柄；原生枚举、无效端口失败、UI 计时器响应、收发/关闭和工作区销毁均有自动测试。本机没有枚举到物理 COM 设备，因此真实 USB 串口回环仍待硬件补证。

### 4.4 源码、远程、API 与 Git

- 常用源码、Shell、配置、特殊文件名和 shebang 自动识别；保留 BOM/编码，保存前复核外部修改并原子替换。
- SSH 使用 `dartssh2` 认证和远程 PTY、`xterm.dart` 渲染，密码/口令只进入系统凭据；首次主机指纹人工确认并绑定，支持多标签、搜索、清屏、安全粘贴和取消。登录成功后绿色“SFTP 文件”按钮在同一条已认证 SSH 连接上新开 SFTP channel，无需再次输入密码，关闭文件区仍保留终端。SFTP 提供双栏、拖放、冲突确认、进度、取消、失败重试与临时文件清理。端口转发支持本地、远程、SOCKS5、多条列表、逐条停止和全部断开；连接与数据泵完整运行在后台 Isolate。
- 桌面模式复用会话记录，只保存主机、端口、模式和名称。Windows 调用 `mstsc.exe`，macOS 调用系统 VNC/屏幕共享；不显示或传递远程桌面密码，不经过 shell，系统客户端缺失时显示可行动错误。
- ADB 独立工作区优先调用随 APP 发布的 Platform-Tools：显示解析后的绝对路径和版本，后台运行 `devices -l` 并区分可用、未授权、离线和未知设备。选中设备后可在右侧终端直接输入命令，普通命令自动补 `shell`，也支持 `install`、`push`、`pull`、`logcat` 等顶层操作；设备序列号由界面锁定，禁止命令覆盖目标。执行过程不占用 UI 线程，终端显示真实退出码、耗时、stdout/stderr，可复制和清空。Harness 与手工入口共用 `AdbService`，由真实 `adb.exe` 进程写入证据日志。
- API 支持常见 HTTP 方法、头、正文、超时、重定向、取消和响应体上限；拒绝 URL 凭据和请求头注入，不提供关闭 TLS 校验的入口。
- Git 工作区使用随包分发并经哈希校验的 MinGit，不依赖用户 PATH；展示根目录、分支、状态、暂存/未暂存 Diff 和日志。Harness 可只读对比任意两个版本，也可经权限审批创建不切换当前工作区的本地安全分支。GitHub 诊断同样复用内置 Git。
- 新增独立“文件 Diff”，可选择或输入任意两个文本/源码文件，自动识别编码，按行显示左右行号、新增/删除/未变统计，支持忽略空白、忽略大小写、只看差异、复制统一 Diff 和保存 `.diff/.patch`。比较在独立 Isolate 中执行；单文件限制 8 MiB/50000 行，超大差异使用有界块算法避免二次方内存。
- Harness 三档权限已传入官方原生沙箱：请求批准逐次询问；帮我批准由 App 对普通原生请求自动决定；完全访问使用官方 `danger-full-access` 模式。官方 PowerShell/文件工具的授权请求通过随机令牌回环桥回到 App，不再只控制 Vibekits MCP 外壳。
- Harness 可从保存记录列出并调用 SSH/SFTP 和 PostgreSQL/MySQL/MariaDB；凭据只从 Credential Manager/Keychain 读取，主机严格匹配已确认指纹。文件哈希、任意文件 Diff、重复文件扫描和磁盘占用分析均运行在独立 Isolate，工具返回与失败进入同一可删除审计记录。每个工具模块的调用日志默认开启，可在该模块记录面板单独关闭或重新开启；Diff 审计只保存路径和统计，不保存文件正文。
- SSH、SFTP 与本地端口转发均由随 App 编译的 `dartssh2` 实现；端口转发不再调用系统 `ssh`。远程桌面、文件定位、系统凭据和截图仍调用 Windows/macOS 自带系统能力，这些不是用户另装依赖。

### 4.5 微工具融合与 DeepSeek 智能体

Base64、URL、JSON/YAML/XML、时间、正则、哈希、网络查询等同构小工具不再各占左侧条目。左侧统一为“转换与检查”，右侧第一层按类别 Tab、第二层用紧凑选项切换，并共享输入/输出、复制、清空和“结果作为输入”。左侧搜索仍能用具体工具名直接命中并自动定位。

“转换与检查”新增安全只读 JSON 路径查询和后台代码统计：前者支持 `.users[0].name`、`.items[*].id` 等有界提取；后者统计语言、文件、代码、注释和空白行并跳过依赖/构建目录。两项均由 `ToolSpec` 自动进入 Harness 可执行目录、模型选择描述和当前模块审计，不增加独立左侧入口。

结构化查询已扩展为同一入口自动识别 JSON、YAML、TOML 和 XML，保留确定性的点路径、数组下标、通配和 XML 属性查询，不开放任意表达式或原地写入。新增只读“代码结构搜索”，后台定位常见语言的类、类型和函数声明；它是有界声明索引，不冒充完整编译器 AST/LSP。新增“安全性能基准”，只允许 SHA-256、JSON 解析和 Base64 三种内置操作，包含预热、5～200 次采样及 min/mean/p50/p95/max，不执行 shell 或外部程序。

文件搜索默认读取根目录 `.gitignore` 的常用模式并使用 smart case：全小写查询不区分大小写，包含大写字母时精确大小写；仍跳过隐藏项、系统元数据、链接和二进制内容。复杂 Git ignore 嵌套/否定语义超出当前轻量实现时不会伪称与 ripgrep 完全一致。

工具能力注册已收敛为单一清单：复杂工作区的 Harness IDs 写在 `ToolSpec.harnessToolIds`，界面日志和合同测试直接复用；带 `run/runAsync` 的微工具自动得到 `vibekits.<id>`、参数 Schema、“适合/不适合/本地优先”描述和 MCP 调用入口。最高准则见 `22_CAPABILITY_INTEGRATION_STANDARD.md`。

`v1.9.0-dev.83+93` 新增 `vibekits.system.capability_check` 智能体能力自检：运行时核对公开能力、实际执行器、当前平台可用性和风险级别，当前自动验收确认 `missingHandlers = 0`。30 个轻量工具已逐项经过 Harness 调用、真实结果和审计日志闭环；资源探针改为可取消子进程，页面退出和应用关闭不再遗留长时间运行的 PowerShell。当前串行全量门禁为 482 项通过、5 项环境门禁跳过、0 项失败，静态分析 0 问题。

`v1.9.0-dev.84+94` 将 Clash Verge 与轻量虚拟机拆为两个独立工具：Clash 内部使用标准 8 项导航和浅蓝选中态，QEMU 不再占用 Clash 栏目且无需代理运行。Windows 关闭窗口改为隐藏到系统托盘并保留显式后台服务；只有托盘“退出并停止后台服务”才结束进程树。

Windows 的 Harness 正式入口已改为内置 `@deepseek-ai/dsh@0.1.2-rc.1` 的 `dsh web`，由 WebView2 直接嵌入官方 `@deepseek-ai/dsh-web-app` 生产界面。旧 Flutter Codex 风格壳、“最后 12000 字符”续话、40 会话/80 消息限制和自制推理时间线不再是 Windows 用户路径。

Harness 原生 Skills 已启用：VibeKits 将官方 `DSH_AGENTS_HOME` 指向当前用户 `.codex`，因此 Harness 直接扫描与 Codex 共用的 `.codex/skills`，支持 `<name>/SKILL.md`、YAML `name/description`、相对 `references/scripts/assets`、按需加载和目录动态刷新。Codex 专用 `agents/openai.yaml` 由 Harness 忽略，不影响技能加载；不复制技能到 Harness profile，避免双份内容漂移。

DSH、Node 和全部 npm 依赖均从 Release 同级 `tools/harness` 本地启动，启动阶段不执行 npm 下载。Windows 首次扫描新 Release 目录时官方 DSH 组合 Web profile 可能超过 60 秒：dev.30 启用持久化 Node 编译缓存，将存活进程等待上限改为 3 分钟并每 5 秒显示真实已用时间；进程退出则立即失败，且 stdout/stderr 在退出前排空到调试日志，不再因旧的固定窗口误判后循环重启。

项目与会话由官方 Workspace/Session 模型统一持久化：工作区可添加、重命名、排序和移除；每个工作区有有序的多会话；会话可重命名、拖动、Fork 和 Archive。移除工作区不删项目或日志，会话进入 `Ungrouped`；取消归档恢复原工作区位置。侧边栏分组/平铺、折叠、搜索、状态点，以及模型、权限、plan、goal、jobs、subagent 和 tool trajectory 全部使用官方 Client/Host 投影。详细合同见 `19_OFFICIAL_HARNESS_WEB_PARITY.md`。

官方 Web 可在没有环境 Key 时正常启动，用户按 Settings → Models 录入 Key，保存后立即可用；旧版系统凭据中已有 Key 时仅作为子进程环境初值。Vibekits MCP 以官方 MCP client 插件接入，ADB/串口/Git/文件等仍共用 App 领域服务和真实审计日志；官方原生工具使用官方权限 UI。

Harness 设置页提供“调试文件目录”，默认解析为 `vibekits.exe` 同目录下的 `tmp`，可选择其他绝对路径并跨重启保存。保存时创建 `logs`、`screenshots`、`temp`：Harness stdout/stderr 同步写入按 UTC 时间命名的日志，OCR/截图写入 `screenshots`，子进程 `TEMP/TMP/TMPDIR` 指向 `temp`；DeepSeek Key 只在子进程环境变量中传递，不写日志文件名或正文。

全局设置同时提供“Harness 调试临时目录”和“工具与模型下载目录”。下载目录默认 `%LOCALAPPDATA%\Vibekits\downloads`，外部模型先写入 `.part`、校验 SHA-256 后原子改名并保留原包；内置 ADB、Git、7-Zip、Node 与 Harness 位于 Release 同级 `tools`，仍随包发布且不受下载目录设置影响。

内置官方 server 已以 `dsh web --port 31999` 真实启动并返回 HTTP 200，停止正常；本机不需要 npm/npx 下载。该项目仍为开发者预览，真实 DeepSeek Key + ADB MCP 任务和 macOS 实机仍待本轮后续验收。

### 4.6 文件搜索与线程隔离

文件搜索默认只显示目录、关键词、文件名/内容和一个搜索按钮；类型、最小大小、修改时间、隐藏项和递归选项收进“筛选”。内容搜索单文件最多读取 8 MiB，不跟随符号链接，最多返回 500 项。结果可直接在文件管理器定位、复制路径，或一键进入文件哈希并自动计算 SHA-256。

清理目标发现、清理扫描/删除、文件搜索、文件哈希、重复文件枚举/哈希/删除、批量重命名规划/执行、纯 Dart 压缩包读取/解码/创建均在独立 Isolate 或独立原生进程运行。UI 只接收约 100 ms 一次的进度快照；工作区销毁立即转发取消，不等待磁盘任务才能释放界面。SQLite/远程数据库、串口会话、图片解码、OCR/VAD 使用短生命周期 Isolate，7-Zip、Git、SSH、DeepSeek 使用独立进程。

## 5. 图片、OCR 与二进制

- 内置图片解码矩阵已真实测试 PNG、JPEG、WebP、GIF、BMP、TIFF、ICO、TGA；同一后端还路由 PSD、EXR、PNM 和 PVR。
- 图片在 Isolate 中转换为统一 PNG 预览；限制 256MiB 编码文件和 1 亿像素，动画/多页格式只解码首帧，EXIF 方向在输出前固化。
- PP-OCRv6 tiny 使用固定官方检测/识别/字典资产，完整 SHA-256 通过后一次安装；官方登机牌样图得到包含坐标和置信度的真实文本。
- Windows“截图识别”调用系统区域截图，macOS 调用 `screencapture -i`；完成后立即送入同一 OCR 管线，取消截图不产生旧剪贴板误识别。自动测试确认一次截图只触发一次推理。
- 大于 256MiB 的 BIN 不再拒绝或整体读入内存：固定 1MiB 窗口、64 位偏移、十进制/Hex 跳转、文本/字节搜索并保留跨块重叠。2GB+ 稀疏文件已验证。

HEIF/HEIC、AVIF、JPEG XL 和相机 RAW 尚无统一内置解码器；不能把扩展名路由写成真解码支持。平台可解码时可继续使用系统预览，失败时界面明确说明并保留 Hex/哈希方向。

## 6. 智能清理边界

- 清理结果以“推荐清理、软件缓存、大文件 / 下载、不常用软件、深度清理”呈现；推荐只包含非高风险候选。软件缓存按原类别保留可追溯明细，深度清理承接系统管理和未知项。
- 随包外部 JSON 规则库与扫描核心解耦；只允许 `recycle`、有界深度/条目/年龄和明确影响说明。数据库损坏或单条规则非法时回退内置规则，不影响离线启动。
- 当前“不常用软件”入口只加载已安装应用和正式卸载器，并明确缺少可靠使用证据；全盘极速大文件索引、卸载残留、占用进程解释和缓存增长趋势仍是下一阶段，不能写成已完成。

- 精确扫描 npm、pnpm store、Yarn、pip、Pub、Gradle、NuGet、Maven、Cargo、Go、Android、Xcode DerivedData、SwiftPM、Homebrew、CocoaPods 等已知缓存位置。
- Visual Studio 只扫描 `ComponentModelCache`/`ImageLibrary`；JetBrains/Android Studio 只扫描 caches/index/tmp/log，不触碰设置、插件、项目或源码。
- pnpm 从宽泛根目录收紧到 `pnpm/store`；不自动扫描项目中的 `node_modules`、`.venv`、`build` 或任意源码目录。
- 下载目录只列出超过 1 小时的未完成下载、超过 30 天的安装包/压缩包，全部默认不勾选。
- 旧插件只有同一 ID 同时存在更高语义版本时才进入高风险建议，当前最高版本永不进入候选。
- Windows 使用 Shell 回收站；macOS 基线移动到 `~/.Trash` 并处理重名；永久删除只允许用户在确认页对可再生成缓存显式开启。
- Windows 系统盘 `.log` 以独立清单方式后台遍历：超过 7 天均列出，未知用途为高风险且默认不选；已知缓存/调试目录继续按版本化规则安全自动选择。
- Harness `logs/screenshots/temp` 超过 24 小时的日志、调试截图和临时文件已接入清理；当前任务文件不进入候选。
- 系统盘分析改为独立 Isolate 内最多 3 个有界 I/O worker；根目录按日志/未知/软件/用户/Windows 的顺序调度，每完成一个根目录就把结果和软件拆分实时送回 UI，不再等整个 `C:` 扫完才显示。一次遍历同时汇总 Windows 组件、Program Files、ProgramData、用户目录及 AppData 软件数据，避免为软件清单重复扫盘。
- 空间列表显示系统/软件/用户/日志缓存各占多少；明确日志缓存与未知根项目提供“移到回收站”动作和二次确认，Windows、系统管理文件及程序安装目录保持保护。删除在独立 Isolate 执行，成功后自动重新分析。
- 无网络时只有 Harness 模型请求、API 调试、GitHub 诊断等网络动作显示自身错误；五个主工作区按需挂载，本地清理、文档、压缩、OCR、计算器、Git/ADB/串口等不等待全局联网检查。
- 每次清理保存可审计 v2 JSON（真实路径、来源、大小、修改时间、结果与原因）；清理页可查看每次及逐项明细、删除单条日志。

## 7. 2026-08-17 验证证据

- 2026-08-19 `v1.9.0-dev.23+33`：Windows 官方 `dsh web` + WebView2 整体移植；`flutter analyze` 0 问题；首轮定向 46/46、进程回收修复后 25/25 通过；Release 启动后 App 可响应且 WebView2/Harness node 存在，强制结束 App 后 Harness node 残留为 0。

- `dart format lib test`：已执行。
- `flutter analyze`：`No issues found`。
- R9 SFTP 定向 Analyze：6 个相关文件无问题；Widget 专项 3/3 通过。
- R9 端口转发：参数与后台 Isolate 单元测试 3/3、三类型/端口占用/停止 Widget 专项通过；4 个相关文件定向 Analyze 无问题。
- R9 系统桌面：服务与记录 9/9、桌面模式 Widget 1/1 通过；7 个相关文件定向 Analyze 无问题；Windows 实查 `mstsc.exe 10.0.19041.5965` 存在。
- R9 ADB 基础：版本/设备解析、Widget 和独立入口 4/4 通过，6 个相关文件定向 Analyze 无问题；本机 ADB `1.0.41`、Platform-Tools `31.0.3-7562133`、server 启动成功，设备与 mDNS 列表为空。
- `flutter test --reporter expanded`：271/271 通过。
- `flutter build windows --release`：成功（78.8 秒）。
- 当时发布 EXE 为 `1.8.0+10`、源码检查点为 `1.9.0-dev.5+15`；最新版本与构建证据以本文件顶部及对应验收文档为准。
- Release 真实启动：携带 `README.md` 启动 5 秒未提前退出。
- Release 产物：`libserialport_plus.dll`、`vibekits_onnx.dll`、`onnxruntime.dll`、`sqlite3.dll`、`tools/7zip/7z.exe`、`tools/7zip/7z.dll` 与内置模型资源均存在。
- Windows Credential Manager：临时数据库密码写入、Unicode 读取、删除后不存在闭环通过。
- 注册表实查：文档/压缩/图片/SQLite ProgID、任意文件右键、`.rar`、`.sqlite` 专用命令均指向本次 Release EXE。

## 8. 明确未完成

1. macOS 需要在 Apple Silicon/Intel 机器运行 `flutter build macos --release`，验证 Swift 编译、Open With、废纸篓、系统菜单、图片、压缩和 SQLite。
2. macOS PP-OCRv6 的 ONNX Runtime 动态桥接和 arm64/x64 原生库尚未完成。
3. HEIF/AVIF/JXL/RAW 的一致内置解码、ICC 色彩管理和动画播放仍需专门后端。
4. MySQL/MariaDB 成功连接尚缺本机真实服务证据；API 脱敏历史已经进入 dev.119，数据库写会话和 Git 写操作辅助仍需后续闭环。
5. 串口原生资产与失败路径已验证，但当前机器没有物理 COM 设备；Windows/macOS 真实 USB 串口回环仍未完成。
6. Windows 已打包官方 `@deepseek-ai/dsh@0.1.2-rc.1` 并通过隔离候选运行时的补丁、会话重绑定和 Web 预热门禁；模型端到端调用、100 次完整退出重启和 macOS Release 仍须按升级门禁重新验收。
7. Windows 安装器/卸载清理、代码签名、自动升级；macOS 签名、公证和 DMG 发布仍未完成。
8. macOS 实机未完成前，项目不能标记为“双平台正式发布完成”。
9. SSH/SFTP/转发仍需真实服务端证据；系统远程桌面仍需 Windows 真实目标与 macOS 实机证据；ADB 通用命令终端与智能体会话授权已接入，文件可视化、Logcat 流式视图、截图、APK 安装向导和无线配对仍需真机逐项验收。
- dev.97：Android ARM64 已内置 ONNX 原生桥，PP-OCRv6 在 `192.168.3.62` 上真实识别 15 行文字；Harness 已解除 Windows DSH 运行时依赖，清理页改为 App 私有沙箱安全策略。真机未配 DeepSeek Key，真实模型回答仍为外部配置门禁，不标记为已验收。
- dev.80 已将清理器拆为公共决策内核与 Windows/macOS/Android 平台边界：规则互斥加载、Android App 沙箱删除、macOS 独立风险映射及删除前二次校验已完成；macOS 全盘分类与 Android 其他 App 统计等待原生适配，当前安全禁用。
