# v1.4.0 文件融合与程序员工作区验收记录

日期：2026-08-16

版本：`1.4.0+5`

平台：Windows x64 / Flutter 3.47.0 / Dart 3.13.0

## 本轮闭环

- PP-OCRv6 tiny 官方检测+识别 ONNX 包、事务安装、图片自动预览/OCR、复制和保存。
- 7-Zip 26.02 完整 Windows 后端，真实 RAR5/ISO/ZSTD 等夹具和统一安全暂存。
- 程序员计算器、SQLite 只读管理、源码编辑、SSH/SFTP/端口转发、API、Git 和 GitHub 安全诊断工作区。
- Markdown 默认预览；图片格式矩阵与像素预算；2GB+ BIN 固定窗口、64 位偏移和跨块搜索。
- 智能清理补齐 Visual Studio、JetBrains/Android Studio、Cursor/Windsurf、macOS 开发缓存，并把 pnpm 范围收紧到 store。
- macOS Flutter 工程、Open With 文件事件排队/就绪握手、应用目录和废纸篓基线。

## 自动证据

- `dart format lib test`：完成。
- `flutter analyze`：`No issues found`。
- `flutter test --reporter expanded`：226/226 通过。
- 测试包含真实 localhost HTTP、真实临时 Git 仓库、真实 SQLite/BLOB/损坏库、SSH 参数安全、2GB+ 稀疏 BIN、跨块搜索、八种 P0 图片编码、官方 PP-OCRv6 样图和 Silero VAD 官方 WAV。

## Windows Release 证据

- `flutter build windows --release`：成功。
- `vibekits.exe` 文件/产品版本：`1.4.0+5`。
- 携带 `README.md` 启动 5 秒保持运行，随后只终止测试进程。
- 发布目录存在 `vibekits_onnx.dll`、`onnxruntime.dll`、`sqlite3.dll`、`tools/7zip/7z.exe` 和 `tools/7zip/7z.dll`。
- `vibekits.exe` SHA-256：`688B2D4277CE6B5F5293689046C1CA14770F2818ACA595B45980C545670781ED`。
- `data/app.so`（Dart AOT 业务代码）SHA-256：`F34B944C3D6A9DF639F14373FABD130977CA5AB4B0C3AC483AB8D675F047818E`。
- `vibekits_onnx.dll` SHA-256：`D806EEC5CCC383B177FF1A0A05F746866EB793F4070D28964ACFA6135024D0A6`。
- `sqlite3.dll` SHA-256：`E6EBC2642223BB419A666E278AE4D2CEF586CD528633E1A595270490B51C278A`。
- 注册表实查文档/压缩/图片/SQLite ProgID、任意文件右键、`.rar` 和 `.sqlite` 命令均指向同一 Release EXE。

## 平台边界

macOS 工程代码已存在，但当前 Windows 主机不能执行 Xcode 构建或 Apple Silicon/Intel 实机测试。macOS ONNX 桥接也尚未实现。因此本记录只证明 Windows Release 和共享领域逻辑，不能作为 macOS 正式完成证据。
