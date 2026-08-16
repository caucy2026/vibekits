# Vibekits macOS 平台实现附件

版本：0.1

状态：Flutter 工程/Open With/废纸篓/快捷键基线已实现，尚未在 macOS 构建验收

## 1. 平台目标

- 首选架构：Apple Silicon arm64；同时保持 Intel x64 可构建路径。
- 最低系统版本在首次依赖审计后冻结，不先写无法验证的承诺。
- UI 使用与 Windows 相同的信息架构和任务状态，同时遵守 macOS 菜单、快捷键、废纸篓、文件选择和窗口习惯。

## 2. 共享与平台边界

共享：格式探测、文本/Hex、图片预处理、压缩安全计划、工具算法、模型清单、ONNX 推理协议和测试向量。

平台实现：

| 接口 | macOS 实现 |
|---|---|
| 文件打开/多文件 | `public.data` Document Type；Swift `application:openURLs:` 在 Dart 就绪前排队，随后批量进入统一路由 |
| Finder 入口 | Open With；高频动作评估 Services/Quick Action |
| 单实例转发 | NSApplication 文件 URL 事件聚合；同进程排队/去重 |
| 回收站 | 当前基线移动到 `~/.Trash` 并处理重名；跨卷/权限失败逐项报告，实机后评估 `NSWorkspace.recycle` |
| 应用目录 | `~/Library/Application Support/Vibekits` |
| 缓存 | `~/Library/Caches/Vibekits`，遵循系统清理语义 |
| Web | WKWebView，网络/脚本/文件访问与 Windows 同级隔离 |
| 压缩 | libarchive/bsdtar/ditto；DMG 使用 `hdiutil` 只读检查/提取 |
| 文件类型 | UTI/MIME 与 Magic 内容识别，不依赖后缀 |
| 模型 | 模型仓库使用 `~/Library/Application Support/Vibekits/Models`；ONNX Runtime arm64/x64 桥接待实现 |

## 3. 操作习惯

- `Command+O/S/F`、`Command+,`、`Command+1`～`Command+5` 已由共享快捷键层按平台切换；`Command+W` 和系统菜单仍待实机补齐。
- 系统菜单栏提供 File/Edit/View/Window/Help 的标准入口；主界面仍只保留当前任务的一个主操作。
- 删除默认进入废纸篓；永久删除不作为普通主操作。
- 文件选择、保存、目录授权使用系统面板；若启用沙箱，持久访问通过安全作用域书签实现。
- Finder 拖入和 Dock 打开多个文件必须逐项进入统一批次路由，不只处理第一个。

## 4. 发布与验收

- Debug/Release 构建、arm64 真机启动、拖入/打开方式、废纸篓、WKWebView、压缩与 ONNX 推理分别留证。
- 生成 `.app` 后再进入签名、公证、DMG/PKG 和自动升级阶段。
- Windows 已通过不等于 macOS 已通过；共享测试之外必须有平台集成测试。
- macOS 未具备可用构建环境前，状态只能是“规格完成/待实现”，不能标记支持。

## 5. 当前已知构建风险

- Windows 专用 WebView 插件需要在 macOS Xcode 环境确认条件编译和 WKWebView 替代路径。
- PP-OCRv6 当前 `OnnxBridge` 只加载 Windows DLL；macOS 必须提供 dylib/Framework、UTF-8 模型路径 ABI 和 arm64/x64 构建产物。
- 官方 7-Zip 当前随 Windows Release 提供 `.exe/.dll`；macOS 需要固定 `7zz` 或系统 `bsdtar/ditto/hdiutil` 的能力表和安全合同。
- 未在 macOS 运行过的代码不得因共享测试通过而修改为“已通过”。
