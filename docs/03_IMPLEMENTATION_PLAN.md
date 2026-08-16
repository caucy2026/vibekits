# Vibekits Windows/macOS 统一实施计划

> 2026-08-16 起以 [统一产品需求](00_PRODUCT_REQUIREMENTS.md) 为最高基线。M0～M8 保留为 Windows 历史进度，不重写已完成证据；后续按下面的 R 系列推进。

## 0. 当前统一路线

| 阶段 | 交付物 | 退出条件 |
|---|---|---|
| R1 极简融合入口 | 单/多文件统一路由、结果动作、BIN/未知文件兜底 | 任意拖入项都有结果；非破坏性流程符合操作预算 |
| R2 图片与 OCR | 全图片模式预览、PP-OCRv6_tiny、本地结果复制/保存/转交 | 官方样图真推理；常见图片模式与超限失败闭环 |
| R3 压缩全格式 | P0 压缩格式的识别/列表/解压能力表与后端组合 | ZIP/RAR/7z/TAR/单流/ISO 均有真实夹具和错误证据 |
| R4 程序员工具扩展 | 高价值开源算法分批移植并接入搜索/拖放 | 每批固定上游、许可证、测试向量和融合入口 |
| R5 macOS 基线 | macOS 工程、平台接口、Finder/废纸篓/WKWebView/ONNX | arm64 Release 构建和五模块主路径实机证据 |
| R6 双平台发布 | 安装、签名、公证/代码签名、升级、许可证清单 | Windows/macOS 分别达到发布门槛 |

## 1. 里程碑顺序

方案一经进入实施，按以下顺序推进。遇到集成困难先解决，不回退到另一套桌面技术栈。

| 里程碑 | 交付物 | 退出条件 |
|---|---|---|
| M0 环境与骨架 | Flutter Windows 工程、主题、五 Tab、CI 基础 | Analyze/Test/Debug/Release 构建通过 |
| M1 开发工具 | 离线转换、哈希、UUID、时间戳、正则、JSON | `DEV-001`～`DEV-003` 首批闭环 |
| M2 文档基础 | 文本、日志、Markdown、配置、Diff、Bin | `DOC-001`～`DOC-104`、`DOC-301`～`DOC-305` |
| M3 结构化阅读 | CSV/TSV、JSON/XML、HTML/EPUB/SVG | `DOC-105`～`DOC-204` |
| M4 解压缩 | 列表、解压、创建、冲突、安全限制 | `ARC-001`～`ARC-008` |
| M5 Windows 清理 | 扫描、选择、白名单、回收站、报告 | `CLN-001`～`CLN-009` |
| M6 网络/文件工具 | HTTP、DNS、端口、重命名、重复文件 | `DEV-004`～`DEV-007` |
| M7 本地模型 | 模型管理、OCR、ASR、TTS | `AI-001`～`AI-009` |
| M8 发布 | 安装包、升级、完整验收、文档 | 62 项功能验收和 35 项 UI 验收通过 |

## 2. M0 详细任务

1. 安装 Flutter stable、Visual Studio 2022 C++ 桌面工作负载、Windows 10/11 SDK。
2. 运行 `flutter doctor -v`，保存环境基线。
3. 创建包名 `vibekits`、组织名 `com.vibekits` 的 Windows 工程。
4. 建立主题、主窗口、五 Tab、状态栏和快捷键。
5. 为五个 Tab 实现空状态和占位操作，不伪装成功功能。
6. 添加 Riverpod、窗口管理和基础测试。
7. 执行格式化、Analyze、单元测试、Windows Debug/Release 构建。
8. 在当前电脑启动应用，检查 1024×700 和 1280×800。

## 3. 每个功能的开发循环

每个验收编号遵循同一闭环：

1. 创建失败测试或可复现夹具。
2. 实现最小完整行为。
3. 运行最窄测试。
4. 验证失败、取消和资源释放。
5. 运行模块测试和 Analyze。
6. Windows 实机执行验收步骤。
7. 在验收矩阵记录日期、构建号和结果。

## 4. 首批测试数据

| 目录 | 夹具 |
|---|---|
| `test_data/archives` | 正常、多层、加密、损坏、路径穿越、高压缩比样本 |
| `test_data/cleanup_sandbox` | 临时、缓存、下载建议、白名单、占用和无权限模拟 |
| `test_data/documents/text` | UTF-8/16、GB18030、Big5、超长行、1GB 生成日志 |
| `test_data/documents/structured` | RFC CSV、深层/损坏 JSON XML、离线 HTML |
| `test_data/documents/web` | EPUB、SVG、SVGZ、脚本和外链攻击样本 |
| `test_data/documents/binary` | Magic Number、稀疏 2GB 文件、搜索边界样本 |
| `test_data/models` | 小型测试 ONNX、错误哈希和截断模型 |

大文件夹具由脚本生成，不提交大二进制到 Git。

## 5. 提交前命令

```powershell
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
flutter build windows --debug
flutter build windows --release
```

原生层启用后追加：

```powershell
ctest --test-dir build\windows\x64 --output-on-failure
```

## 6. 当前电脑验收记录格式

每次里程碑创建 `docs/acceptance/M<n>_<yyyy-mm-dd>.md`，记录：

- Git commit 或工作树摘要
- `flutter doctor -v`
- Debug/Release 构建命令和结果
- 自动测试数量
- 人工验收编号与结果
- UI 验收编号与结果
- 截图路径
- 已知限制和后续动作
