# Vibekits 当前实现状态与未完成清单

> 当前研发顺序与逐项关闭状态以 [发布完成清单](17_RELEASE_COMPLETION_CHECKLIST.md) 为唯一执行入口；早期 Windows/UI 矩阵保留为用例库。

更新日期：2026-08-18

当前版本：`1.9.0-dev.7+17`（Harness UI/官方运行时开发检查点，非正式发布）

目标平台：Windows x64；macOS arm64/x64 工程基线

## 1. 当前结论

Windows 已形成可构建、可启动、可自动路由的开发者工具融合器。R9 的远程会话、SSH、SFTP、后台转发和系统桌面软件主路径已完成；ADB 工作区已进入代码并完成官方路径/版本识别和设备状态基础层。本机真实 ADB server 已启动但没有设备，因此 USB/无线操作仍不能写成完成。SSH/SFTP/转发和桌面真实目标证据仍待补。macOS 工程已接入，但当前机器不是 macOS，不能把未执行的 Xcode/arm64 与真实设备验证写成完成。

## 2. 五个主工作区

| 工作区 | 当前能力 | 状态 |
|---|---|---|
| 解压缩 | 官方 7-Zip 26.02 + Dart 后端；RAR/RAR5、ZIP/ZIPX、7z、TAR、GZ/BZ2/XZ/ZST、CAB、ISO/WIM/DMG 等列表/解压；路径、链接、空间、大小、压缩比、冲突、暂存、取消保护 | Windows 主路径完成 |
| 系统清理 | 浏览器/应用/系统/开发/IDE/插件下载/调试/日志缓存；后台 Isolate、低 I/O 占用、扫描/清理取消；本次/累计/系统盘容量总结；白名单、竞态身份、回收站优先、报告 | Windows 完成主路径；macOS 待实机 |
| 文档阅读 | Markdown 默认预览；最近打开跨重启保存并可清空；源码识别、查找、编辑、原子保存；结构化数据、Web/EPUB/SVG；大文本与大 BIN 窗口化 | Windows 主路径完成 |
| 开发工具 | 左侧只保留计算器、数据库、串口、远程、ADB、API、Git、文件搜索/哈希/重命名/重复文件等独立工作区；编码、格式、时间、正则、网络微工具合并到“转换与检查”的右侧分类 Tab | 数据库、串口、SSH/SFTP/转发/系统桌面主路径完成；ADB 路径/设备层完成，操作层待继续 |
| Harness（智能体） | 一级导航第 1 项；Codex 中性色自有界面；项目/会话侧栏、工作区、模型配置、持续追问、Markdown、复制、新会话、进度和停止；OCR 为同页辅助入口；一级页和 Harness/OCR 子页跨重启恢复 | UI 与普通模型流式通道已完成；官方 Harness 文件/命令/工具/计划/审批事件仍在接入，完成前不得宣称智能体闭环；OCR/macOS ONNX 待验证 |

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
- SSH 使用 `dartssh2` 认证和远程 PTY、`xterm.dart` 渲染，密码/口令只进入系统凭据；首次主机指纹人工确认并绑定，支持多标签、搜索、清屏、安全粘贴和取消。SFTP 提供双栏、拖放、冲突确认、进度、取消、失败重试与临时文件清理。端口转发支持本地、远程、SOCKS5、多条列表、逐条停止和全部断开；连接与数据泵完整运行在后台 Isolate。
- 桌面模式复用会话记录，只保存主机、端口、模式和名称。Windows 调用 `mstsc.exe`，macOS 调用系统 VNC/屏幕共享；不显示或传递远程桌面密码，不经过 shell，系统客户端缺失时显示可行动错误。
- ADB 独立工作区调用用户已安装的官方 Platform-Tools：显示解析后的绝对路径和版本，后台运行 `devices -l` 并区分可用、未授权、离线和未知设备。Shell、文件、Logcat、截图、APK、无线配对及智能体逐项审批仍在 ADB-106 后续步骤。
- API 支持常见 HTTP 方法、头、正文、超时、重定向、取消和响应体上限；拒绝 URL 凭据和请求头注入，不提供关闭 TLS 校验的入口。
- Git 工作区只读展示根目录、分支、状态、暂存/未暂存 Diff 和日志；GitHub 诊断检查 DNS/TLS/HTTPS/代理/hosts/SSH 22 与官方 443 备用方向，不自动改 hosts、证书或代理。

### 4.5 微工具融合与 DeepSeek 智能体

Base64、URL、JSON/YAML/XML、时间、正则、哈希、网络查询等同构小工具不再各占左侧条目。左侧统一为“转换与检查”，右侧第一层按类别 Tab、第二层用紧凑选项切换，并共享输入/输出、复制、清空和“结果作为输入”。左侧搜索仍能用具体工具名直接命中并自动定位。

DeepSeek 从开发工具左侧迁入模型页，界面采用 Codex 风格的工作区、持续对话和底部任务输入。首轮直接发送任务，后续自动携带有界会话上下文；回复支持 Markdown 与复制。运行进度固定在输入框上方，任务期间仍可编辑下一条要求，可随时停止或开始新任务；切换 OCR 后返回不会丢失当前会话。`Enter` 发送、`Shift+Enter` 换行。当前固定官方 `@deepseek-ai/dsh@0.1.0-rc.7 --profile headless`。已移除任务阶段 `npx --yes` 路径，程序只启动安装包内 Node、CLI 和 profile；运行时缺件会直接提示安装包损坏。编译期运行时准备和工具目录桥接已进入开发，官方包实启及 Key 连通仍待 Release 资产准备后验收。

参数合同、流式输出、完成恢复和取消适配的模拟进程自动测试已通过；本机官方 npm 包首次探测下载超过 2 分钟无输出后取消，因此当前不能写成官方 Harness 已真实启动。该项目仍为开发者预览，后续在 ACP JSON-RPC 稳定后增加可续接会话和结构化审批。

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

- 精确扫描 npm、pnpm store、Yarn、pip、Pub、Gradle、NuGet、Maven、Cargo、Go、Android、Xcode DerivedData、SwiftPM、Homebrew、CocoaPods 等已知缓存位置。
- Visual Studio 只扫描 `ComponentModelCache`/`ImageLibrary`；JetBrains/Android Studio 只扫描 caches/index/tmp/log，不触碰设置、插件、项目或源码。
- pnpm 从宽泛根目录收紧到 `pnpm/store`；不自动扫描项目中的 `node_modules`、`.venv`、`build` 或任意源码目录。
- 下载目录只列出超过 1 小时的未完成下载、超过 30 天的安装包/压缩包，全部默认不勾选。
- 旧插件只有同一 ID 同时存在更高语义版本时才进入高风险建议，当前最高版本永不进入候选。
- Windows 使用 Shell 回收站；macOS 基线移动到 `~/.Trash` 并处理重名；永久删除只允许用户在确认页对可再生成缓存显式开启。

## 7. 2026-08-17 验证证据

- `dart format lib test`：已执行。
- `flutter analyze`：`No issues found`。
- R9 SFTP 定向 Analyze：6 个相关文件无问题；Widget 专项 3/3 通过。
- R9 端口转发：参数与后台 Isolate 单元测试 3/3、三类型/端口占用/停止 Widget 专项通过；4 个相关文件定向 Analyze 无问题。
- R9 系统桌面：服务与记录 9/9、桌面模式 Widget 1/1 通过；7 个相关文件定向 Analyze 无问题；Windows 实查 `mstsc.exe 10.0.19041.5965` 存在。
- R9 ADB 基础：版本/设备解析、Widget 和独立入口 4/4 通过，6 个相关文件定向 Analyze 无问题；本机 ADB `1.0.41`、Platform-Tools `31.0.3-7562133`、server 启动成功，设备与 mDNS 列表为空。
- `flutter test --reporter expanded`：271/271 通过。
- `flutter build windows --release`：成功（78.8 秒）。
- 已发布 EXE 文件/产品版本仍为 `1.8.0+10`；当前源码为 `1.9.0-dev.5+15`，待 R9 退出条件完成后生成新 Release。
- Release 真实启动：携带 `README.md` 启动 5 秒未提前退出。
- Release 产物：`libserialport_plus.dll`、`vibekits_onnx.dll`、`onnxruntime.dll`、`sqlite3.dll`、`tools/7zip/7z.exe`、`tools/7zip/7z.dll` 与内置模型资源均存在。
- Windows Credential Manager：临时数据库密码写入、Unicode 读取、删除后不存在闭环通过。
- 注册表实查：文档/压缩/图片/SQLite ProgID、任意文件右键、`.rar`、`.sqlite` 专用命令均指向本次 Release EXE。

## 8. 明确未完成

1. macOS 需要在 Apple Silicon/Intel 机器运行 `flutter build macos --release`，验证 Swift 编译、Open With、废纸篓、系统菜单、图片、压缩和 SQLite。
2. macOS PP-OCRv6 的 ONNX Runtime 动态桥接和 arm64/x64 原生库尚未完成。
3. HEIF/AVIF/JXL/RAW 的一致内置解码、ICC 色彩管理和动画播放仍需专门后端。
4. MySQL/MariaDB 成功连接尚缺本机真实服务证据；数据库写会话、API 历史脱敏持久化、Git 写操作辅助尚未进入本版。
5. 串口原生资产与失败路径已验证，但当前机器没有物理 COM 设备；Windows/macOS 真实 USB 串口回环仍未完成。
6. Windows 已打包官方 `@deepseek-ai/dsh@0.1.0-rc.7` 并通过本地兼容模型端点实启；模型发起 MCP SHA-256、APP 执行、结果回传和最终回复全链路通过。真实 DeepSeek Key、macOS 实启与 ACP 原生会话仍待验证。
7. Windows 安装器/卸载清理、代码签名、自动升级；macOS 签名、公证和 DMG 发布仍未完成。
8. macOS 实机未完成前，项目不能标记为“双平台正式发布完成”。
9. SSH/SFTP/转发仍需真实服务端证据；系统远程桌面仍需 Windows 真实目标与 macOS 实机证据；ADB 通用命令与智能体一次审批已接入，Shell、文件、Logcat、截图、APK 和无线调试仍需真机逐项验收。
