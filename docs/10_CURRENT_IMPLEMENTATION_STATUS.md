# Vibekits 当前实现状态与未完成清单

更新日期：2026-08-16

当前版本：`1.5.0+6`

目标平台：Windows x64；macOS arm64/x64 工程基线

## 1. 当前结论

Windows 已形成可构建、可启动、可自动路由的开发者工具融合器。`flutter analyze` 无问题，234/234 自动测试通过，Windows Release 构建与 5 秒真实启动通过。macOS 工程、Open With 文件事件和共享逻辑已接入，但当前机器不是 macOS，不能把未执行的 Xcode/arm64 实机验证写成完成。

## 2. 五个主工作区

| 工作区 | 当前能力 | 状态 |
|---|---|---|
| 解压缩 | 官方 7-Zip 26.02 + Dart 后端；RAR/RAR5、ZIP/ZIPX、7z、TAR、GZ/BZ2/XZ/ZST、CAB、ISO/WIM/DMG 等列表/解压；路径、链接、空间、大小、压缩比、冲突、暂存、取消保护 | Windows 主路径完成 |
| 系统清理 | 浏览器/应用/系统/开发/IDE/插件下载/调试/日志缓存；后台 Isolate、低 I/O 占用、扫描/清理取消；本次/累计/系统盘容量总结；白名单、竞态身份、回收站优先、报告 | Windows 完成主路径；macOS 待实机 |
| 文档阅读 | Markdown 默认预览；最近打开跨重启保存并可清空；源码识别、查找、编辑、原子保存；结构化数据、Web/EPUB/SVG；大文本与大 BIN 窗口化 | Windows 主路径完成 |
| 开发工具 | Windows 风格程序员计算器；SQLite + PostgreSQL 只读管理和安全连接历史；DeepSeek Harness 可选入口；API、SSH/SFTP/转发、Git、网络诊断、文件工具 | 本批主路径完成；MySQL/远程融合增强待做 |
| 本地模型 | 固定清单、应用内置资源、逐文件 SHA-256 与事务安装、Silero VAD；官方 PP-OCRv6 tiny 真推理、图片预览、自动 OCR、复制/保存 | Windows 完成主路径；macOS ONNX 待适配 |

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

### 4.2 SQLite 与 PostgreSQL 数据库管理器

按 SQLite Magic 和常见扩展路由；默认只读，`query_only`、`trusted_schema=OFF`、DQS 关闭；表/视图、100 行分页、最多 500 行查询结果、BLOB/NULL 显示。每个请求使用短生命周期 Isolate，8 秒超时可终止；预编译语句确认只读后才执行。

PostgreSQL 已接入 TLS/非 TLS 连接、对象列表、100 行分页和最多 500 行只读查询；连接资料自动进入最近记录，密码直接写入 Windows Credential Manager/macOS Keychain，普通设置不含密码。Windows 已执行临时凭据写入、读取和删除真实闭环。MySQL/MariaDB 尚未接入，不显示伪入口。

### 4.3 源码、远程、API 与 Git

- 常用源码、Shell、配置、特殊文件名和 shebang 自动识别；保留 BOM/编码，保存前复核外部修改并原子替换。
- SSH/SFTP 使用系统 OpenSSH，参数数组直传且不经过 Shell；严格主机密钥询问、密钥/Agent 认证、不保存密码；端口转发只绑定 `127.0.0.1`。
- API 支持常见 HTTP 方法、头、正文、超时、重定向、取消和响应体上限；拒绝 URL 凭据和请求头注入，不提供关闭 TLS 校验的入口。
- Git 工作区只读展示根目录、分支、状态、暂存/未暂存 Diff 和日志；GitHub 诊断检查 DNS/TLS/HTTPS/代理/hosts/SSH 22 与官方 443 备用方向，不自动改 hosts、证书或代理。

### 4.4 DeepSeek Harness

开发工具页新增一个“智能开发”入口：保存用户选择的项目目录，检查 Node.js/npx，使用固定官方 `@deepseek-ai/dsh@0.1.0-rc.5` 启动本机 Web 控制台，识别就绪地址后打开浏览器，显示有界日志并支持停止进程树。API 密钥只在 Harness 控制台中配置。

适配层和模拟进程自动测试已通过；本机官方 npm 包首次探测下载超过 2 分钟无输出后取消，因此当前不能写成官方 Harness 已真实启动。该项目仍为开发者预览，后续在 ACP JSON-RPC 稳定后复用同一入口深化集成。

## 5. 图片、OCR 与二进制

- 内置图片解码矩阵已真实测试 PNG、JPEG、WebP、GIF、BMP、TIFF、ICO、TGA；同一后端还路由 PSD、EXR、PNM 和 PVR。
- 图片在 Isolate 中转换为统一 PNG 预览；限制 256MiB 编码文件和 1 亿像素，动画/多页格式只解码首帧，EXIF 方向在输出前固化。
- PP-OCRv6 tiny 使用固定官方检测/识别/字典资产，完整 SHA-256 通过后一次安装；官方登机牌样图得到包含坐标和置信度的真实文本。
- 大于 256MiB 的 BIN 不再拒绝或整体读入内存：固定 1MiB 窗口、64 位偏移、十进制/Hex 跳转、文本/字节搜索并保留跨块重叠。2GB+ 稀疏文件已验证。

HEIF/HEIC、AVIF、JPEG XL 和相机 RAW 尚无统一内置解码器；不能把扩展名路由写成真解码支持。平台可解码时可继续使用系统预览，失败时界面明确说明并保留 Hex/哈希方向。

## 6. 智能清理边界

- 精确扫描 npm、pnpm store、Yarn、pip、Pub、Gradle、NuGet、Maven、Cargo、Go、Android、Xcode DerivedData、SwiftPM、Homebrew、CocoaPods 等已知缓存位置。
- Visual Studio 只扫描 `ComponentModelCache`/`ImageLibrary`；JetBrains/Android Studio 只扫描 caches/index/tmp/log，不触碰设置、插件、项目或源码。
- pnpm 从宽泛根目录收紧到 `pnpm/store`；不自动扫描项目中的 `node_modules`、`.venv`、`build` 或任意源码目录。
- 下载目录只列出超过 1 小时的未完成下载、超过 30 天的安装包/压缩包，全部默认不勾选。
- 旧插件只有同一 ID 同时存在更高语义版本时才进入高风险建议，当前最高版本永不进入候选。
- Windows 使用 Shell 回收站；macOS 基线移动到 `~/.Trash` 并处理重名；永久删除只允许用户在确认页对可再生成缓存显式开启。

## 7. 2026-08-16 验证证据

- `dart format lib test`：已执行。
- `flutter analyze`：`No issues found`。
- `flutter test --reporter expanded`：234/234 通过。
- `flutter build windows --release`：成功。
- EXE 文件/产品版本：`1.5.0+6`。
- Release 真实启动：携带 `README.md` 启动 5 秒未提前退出。
- Release 产物：`vibekits_onnx.dll`、`onnxruntime.dll`、`sqlite3.dll`、`tools/7zip/7z.exe`、`tools/7zip/7z.dll` 和 5 项内置模型资源均存在。
- Windows Credential Manager：临时数据库密码写入、Unicode 读取、删除后不存在闭环通过。
- 注册表实查：文档/压缩/图片/SQLite ProgID、任意文件右键、`.rar`、`.sqlite` 专用命令均指向本次 Release EXE。

## 8. 明确未完成

1. macOS 需要在 Apple Silicon/Intel 机器运行 `flutter build macos --release`，验证 Swift 编译、Open With、废纸篓、系统菜单、图片、压缩和 SQLite。
2. macOS PP-OCRv6 的 ONNX Runtime 动态桥接和 arm64/x64 原生库尚未完成。
3. HEIF/AVIF/JXL/RAW 的一致内置解码、ICC 色彩管理和动画播放仍需专门后端。
4. MySQL/MariaDB、数据库写会话、API 历史脱敏持久化、Git 写操作辅助尚未进入本版。
5. DeepSeek Harness 官方 npm 包在当前网络未完成真实下载和启动；macOS 实启、ACP 原生会话均待验证。
6. Windows 安装器/卸载清理、代码签名、自动升级；macOS 签名、公证和 DMG 发布仍未完成。
7. macOS 实机未完成前，项目不能标记为“双平台正式发布完成”。
