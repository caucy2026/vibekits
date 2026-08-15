# Vibekits 开发日志

按时间记录开发过程、关键决策、问题与解决、里程碑状态。里程碑详细验收见 `docs/acceptance/`。

## 2026-08-15

### 决策记录

| 决策 | 结论 | 依据 |
|---|---|---|
| 技术路线 | Flutter UI + Windows 原生能力（libarchive/ONNX 等 C/C++） | 一套 UI 双端（Windows/Android），低内存 |
| 交互原则 | 每个界面对标一款主流应用，不自创操作习惯 | `08_WINDOWS_UX_CONVENTIONS.md` |
| 文档阅读格式 | 25 个轻量后缀 + 未知格式手动文本/Hex；排除 Office/PDF | 参考 kemi-office，`06` §5 |
| 开发顺序 | M0 骨架 → M1 工具 → M2 文档 → M3 结构化 → M4 解压 → M5 清理 → M6 网络/文件 → M7 模型 → M8 发布 | `03` 实施计划 |

### 环境

- Flutter 3.47.0 stable / Dart 3.13.0，位于 `D:\tools\flutter`（克隆自 GitHub，初始下载极慢，已完整检出 `4cf24164`）。
- Visual Studio Build Tools 2022 17.14.37 安装到 `D:\VSBuildTools`（MSVC 14.44.35207、CMake）。Windows SDK 按其固定位置装在 C 盘 `Windows Kits\10`。
- `flutter doctor`：VS/Chrome/Windows ✅，Android cmdline-tools 缺失（Windows 首版不受影响），Flutter 未入 PATH（以全路径调用）。

### 里程碑状态

| 里程碑 | 状态 | 备注 |
|---|---|---|
| M0 环境与骨架 | ✅ 完成 | 五 Tab、快捷键、主题、状态栏；Debug/Release 构建通过；实机启动验证 1280×800 |
| M1 开发工具 | ✅ 首批完成 | 22 个离线工具；46/46 测试通过；DEV-001~003、APP-001/003 自动通过 |
| M2 文档阅读 | ✅ 完成 | 文本/日志/Markdown/配置/Diff/Bin 查看器；GB18030/Big5 解码、大文件流式索引 |
| M3 结构化阅读 | ✅ 完成 | CSV/TSV 表格、JSON/XML 树、HTML/EPUB/SVG 安全渲染 |
| M4 解压缩 | ✅ 完成 | zip/tar/tgz/gz/bz2/xz/7z 列表/解压/创建、路径穿越防护、冲突策略 |
| M5 Windows 清理 | ✅ 完成 | 临时目录扫描、三态选择、白名单、回收站删除（FFI） |
| M6 网络/文件工具 | ✅ 完成 | HTTP/DNS/端口/CIDR、文件哈希/批量重命名 |
| M7 本地模型 | ✅ 管理完成 | 模型导入/校验/删除/目录；推理运行时待接入 |
| M8 发布 | 🔄 待人工验收 | 100/100 测试、Debug/Release 构建、实机启动 |

### 已解决问题

1. `flutter.bat.lock` 被残留进程占用 → 终止残留 dart/git 进程并删除锁。
2. flutter test 紧凑报告器在窄终端崩溃（RangeError）→ 用 `--reporter expanded`。
3. `ShortcutActivator/SingleActivator` 属于 `widgets`，`LogicalKeyboardKey` 属于 `services` → 分别导入。
4. `crypto` 顶层函数与静态方法重名 → 加 `crypto.` 前缀。
5. `Uint8List` 缺 `dart:typed_data` 导入。
6. Tab 项窄宽度溢出 → 文本 `Flexible + ellipsis`。
7. C++ 源码中文注释触发 MSVC C4819（代码页 936）→ 原生代码注释改 ASCII。
8. 窗口默认 1280×720/标题小写 → 改为 1280×800/`Vibekits`，新增 `WM_GETMINMAXINFO` 最小 1024×700。
9. `charset_converter` 走 MethodChannel（异步且依赖原生插件，无法单元测试）→ 移除；GBK 用纯 Dart `fast_gbk`，GB18030/Big5 留待原生层接入。
10. `flutter_markdown` 已停更 → 改用 `flutter_markdown_plus`。
11. `csv` 8.0 移除 `CsvToListConverter` → 改用 `CsvDecoder`；`xml` 7 的 `XmlText.text` 弃用 → 改用 `value`。
12. Dart RegExp 不支持 `(?i)`/`(?s)` 内联标志 → 改用构造函数 `caseSensitive/dotAll`。
13. `archive` 4.0.9 的 xz 解码器类名为 `XZDecoder`。
14. 回收站删除经 `SHFileOperationW` FFI 实现（结构字段用 `Pointer<Void>` 而非 `IntPtr`）。
15. 7z/rar/iso 与 GB18030/Big5 需原生层，纯 Dart 无法可靠实现，已明确标注为“待原生层接入”。
16. GB18030/Big5 解码 → 新增 `NativeCodec`（kernel32 `MultiByteToWideChar` FFI，cp 54936/950/936），补齐编码硬限制。
17. 大文件文本读取（>64MB 内存溢出）→ 新增 `FileLineIndex` 流式行索引（RandomAccessFile 64KB 块扫描）+ 按需读行解码，文档 Tab 走 `_loadStreaming` 分支。
18. 7z 列表/解压 → 下载 `7za.exe` 到 `native/7za/`，新增 `SevenZip`（`7za l -slt` 解析 / `7za x`），ArchiveTab 增加 7z 条目渲染与选择。

### 已知限制

- 复制/保存、缩放 150%/200% 可读性待人工复核。
- 网络工具、文件工具属 M6；本地模型属 M7。
- Android 端 cmdline-tools 未装，后续做平板时补。
- rar / iso 仍受限：7za 不内置 rar 解压与 iso 挂载，需引入 unrar 或 7z 完整版（含 7z.dll）后接入。
- OCR/ASR/TTS 推理仍待接入：需 ONNX Runtime DLL + 100MB 内模型文件（外部大文件，不随仓库提交）。

## 约定

- 每次里程碑结束更新本文档与 `docs/acceptance/M<n>_<date>.md`，并同步 `04/07` 验收矩阵状态。
- 遇到技术卡点记录到“已解决问题”，不静默绕过。
