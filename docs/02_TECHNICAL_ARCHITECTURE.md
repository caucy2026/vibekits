# Vibekits Windows/macOS 技术架构

> 统一产品边界见 [00_PRODUCT_REQUIREMENTS.md](00_PRODUCT_REQUIREMENTS.md)。现有 Windows 原生实现保留，但新增领域逻辑不得继续写死 Windows 路径、注册表或系统 API。

## 1. 技术栈

| 层 | 选择 | 用途 |
|---|---|---|
| UI | Flutter stable / Dart | Windows 与后续 Android 共用界面和业务状态 |
| 状态管理 | Riverpod | 模块状态、依赖注入、可测试异步任务 |
| 路由 | Flutter Navigator + Shell | 五个稳定 Tab 和设置/对话框 |
| Windows API | `win32` + Dart FFI | 文件、回收站、进程、内存和系统目录 |
| 原生通用层 | C/C++ + C ABI | libarchive、ONNX Runtime、音频和高性能索引 |
| 本地数据库 | SQLite | 最近记录、扫描报告、模型清单和任务元数据 |
| Web 渲染 | Windows WebView2 | 已清洗 HTML/Markdown/EPUB，严格离线策略 |
| 构建 | Flutter Windows + CMake + MSVC | x64 Debug/Release |
| 测试 | flutter_test、integration_test、CTest | 单元、组件、集成和原生测试 |

技术路线固定为 Flutter + 原生库。某个库集成困难不构成改回 Electron、Python 桌面壳或仅 Web 实现的理由；变更技术路线必须先更新决策记录并取得确认。

## 2. 分层

```text
┌──────────────── Presentation ────────────────┐
│ Flutter 页面、组件、快捷键、可访问性、状态  │
├──────────────── Application ─────────────────┤
│ 用例、任务编排、取消、进度、错误映射         │
├────────────────── Domain ────────────────────┤
│ ArchiveEntry、CleanupCandidate、Document 等  │
├────────────── Infrastructure ─────────────────┤
│ SQLite、文件系统、HTTP、配置、日志、缓存      │
├──────────── Native / Platform ────────────────┤
│ libarchive、Windows API、ONNX、音频、WebView2 │
└───────────────────────────────────────────────┘
```

Presentation 不直接调用 FFI、文件系统或 HTTP。Application 只依赖抽象接口；平台实现通过 Provider 注入。

## 3. 工程目录

```text
vibekits/
├─ docs/
├─ lib/
│  ├─ app/
│  │  ├─ app.dart
│  │  ├─ app_theme.dart
│  │  ├─ app_shortcuts.dart
│  │  └─ main_shell.dart
│  ├─ core/
│  │  ├─ errors/
│  │  ├─ tasks/
│  │  ├─ logging/
│  │  ├─ storage/
│  │  └─ widgets/
│  └─ features/
│     ├─ archive/
│     ├─ cleaner/
│     ├─ documents/
│     ├─ dev_tools/
│     └─ local_models/
├─ native/
│  ├─ include/vibekits_native.h
│  ├─ archive/
│  ├─ document_index/
│  └─ inference/
├─ test/
├─ integration_test/
├─ test_data/
│  ├─ archives/
│  ├─ cleanup_sandbox/
│  ├─ documents/
│  └─ models/
└─ windows/
```

每个 `features/<name>` 内部按 `domain/`、`application/`、`infrastructure/`、`presentation/` 分层；仅在模块确实使用时创建目录，避免空抽象。

## 4. 通用任务协议

所有超过 200ms 的操作必须实现统一任务协议：

```text
TaskState = idle | preparing | running | cancelling | succeeded | failed
TaskProgress = completedUnits / totalUnits + currentItem + bytes + speed
TaskError = code + userMessage + technicalDetail + retryable
```

任务必须具备：唯一 ID、开始/结束时间、取消令牌、进度流和资源清理。取消是协作式取消；原生循环至少每 64KiB 或每个条目检查一次。

## 5. 原生 ABI

原生层只暴露稳定 C ABI，不把 C++ 类型跨边界：

```c
typedef void* VkTaskHandle;
typedef void (*VkProgressCallback)(const char* json_utf8, void* user_data);

int32_t vk_archive_list(const char* request_json, VkProgressCallback callback,
                        void* user_data, VkTaskHandle* task);
int32_t vk_archive_extract(const char* request_json, VkProgressCallback callback,
                           void* user_data, VkTaskHandle* task);
int32_t vk_task_cancel(VkTaskHandle task);
void vk_task_release(VkTaskHandle task);
void vk_string_free(char* value);
```

跨边界字符串统一 UTF-8；请求和结构化结果使用版本化 JSON；大块文件内容通过路径、映射文件或回调分片传递，不通过 JSON/Base64 复制。

## 6. 模块实现

### 6.1 解压缩

- libarchive 负责格式探测、条目枚举、解压和主要创建格式。
- 先枚举并规范化路径，再允许写磁盘。
- 目标路径以 `GetFullPathName` 规范化，必须保持在用户选择的根目录内。
- 展开大小未知时标记“不确定”，仍执行条目数、单文件大小和压缩比限制。
- 写入临时文件，单文件完成后原子改名；取消时删除临时文件。

### 6.2 Windows 清理

- 每个清理类别实现独立 `CleanupScanner`，返回候选项，不执行删除。
- 候选项包含路径、大小、类别、风险、依据、最后修改时间和建议动作。
- 删除器重新验证路径、白名单和文件身份，防止扫描后路径被替换。
- 普通删除优先调用 Windows 回收站 API；永久删除是独立命令。
- 测试只能操作 `test_data/cleanup_sandbox` 和测试期间创建的临时目录。

### 6.3 文档阅读

- 文本：按块扫描换行并建立 64 位偏移索引；页面按需读取。
- 编码：BOM → 严格 UTF-8 → GB18030/GBK → Big5 → 用户选择。
- CSV：使用符合 RFC 4180 的流式解析器，行索引记录逻辑记录而非物理行。
- JSON：64MB 内严格解析并格式化，最大深度 128；失败或超限进入源码模式。
- XML：禁用 DTD 和外部实体，使用流式解析，最大深度 128。
- HTML：使用 DOM 白名单清洗；WebView2 禁止脚本、网络、下载和新窗口。
- EPUB：校验 ZIP 路径、条目数量和展开大小，解析 container/OPF/spine，只提供虚拟本地域资源。
- SVG：使用安全 SVG 渲染器；SVGZ 解压后执行相同限制。
- Binary：64 位偏移随机读取；固定窗口缓存，不按文件大小分配内存。

### 6.4 开发工具

- 纯文本转换优先使用 Dart 标准库和维护活跃的 MIT/BSD/Apache 库。
- 密码学只调用成熟库，不自行实现算法。
- HTTP 客户端默认不跟随跨域重定向携带敏感请求头；超时可配置。
- 批量文件操作分为“生成计划”和“执行计划”两个用例。

### 6.5 本地模型

- ONNX Runtime C API 作为统一优先运行时，其他引擎通过相同 `ModelRunner` 接口适配。
- 模型清单是签名或随应用发布的版本化 JSON，包含下载地址、许可证、大小和 SHA-256。
- 下载到 `.part`，校验后原子改名。
- 模型会话在后台线程创建；释放时等待当前推理结束或取消后销毁。
- 输入文件和输出默认保留在用户选择位置，不写入遥测。

## 7. 数据和目录

| 数据 | 默认位置 |
|---|---|
| 设置 | `%APPDATA%\Vibekits\settings.json` |
| SQLite | `%LOCALAPPDATA%\Vibekits\vibekits.db` |
| 缓存 | `%LOCALAPPDATA%\Vibekits\Cache` |
| 日志 | `%LOCALAPPDATA%\Vibekits\Logs` |
| 模型 | `%LOCALAPPDATA%\Vibekits\Models`，可修改 |
| 临时任务 | `%LOCALAPPDATA%\Vibekits\Tasks\<task-id>` |

日志滚动保留 7 天、单文件上限 10MB。路径、URL 查询参数和请求头在写日志前脱敏。

## 8. 安全边界

1. 外部文件均视为不可信输入。
2. 压缩包、EPUB、SVG、HTML、XML 必须在限制内解析。
3. UI 不拼接 shell 命令；进程调用使用参数数组。
4. 应用默认普通用户运行，不要求管理员权限。
5. 需要管理员权限的系统目录只报告“无权限”，不静默提权。
6. 下载模型和工具必须校验来源、许可证和哈希。

## 9. 测试策略

共享领域测试在 Windows 与 macOS 使用同一夹具。平台层分别验证文件打开事件、拖放、回收站/废纸篓、Web 隔离、格式后端和 Release 打包。图片解码、压缩格式和模型运行时通过 capability provider 注入；UI 只依赖稳定的能力状态，不判断操作系统或底层二进制名称。

新增平台接口至少包括：`FileOpenBridge`、`TrashProvider`、`ArchiveBackend`、`ImageCodecProvider`、`RuntimeLibraryProvider`、`SystemIntegrationRegistrar`。Windows 现有 FFI/注册表实现逐步迁入这些接口，macOS 提供对应实现。

- Domain/Application：纯 Dart 单元测试。
- Widget：五个 Tab、空/加载/成功/失败状态和 1024×700 布局。
- Native：路径规范化、压缩炸弹、取消、错误码和资源释放。
- Integration：真实 Windows 文件选择、拖放、回收站、WebView2、模型加载。
- 性能：1GB 日志、2GB BIN、64MB JSON、10万行 CSV、10万条目压缩包。

测试夹具必须是生成数据或无隐私样本；禁止用用户真实下载目录做自动清理测试。
