# Vibekits v1.5.0 体验与开发工具验收记录

日期：2026-08-16

版本：`1.5.0+6`

平台：Windows x64（本机）；macOS 待实机

## 本批范围

- 清理后台 Isolate、取消、低 I/O 占用、完成摘要与累计数据。
- 文档最近打开记录持久化和清空。
- Windows 风格程序员计算器。
- PostgreSQL 远程只读管理、最近连接和系统安全凭据。
- PP-OCRv6/Silero 内置离线安装资源。
- DeepSeek Harness 官方 CLI 进程适配入口。

## 自动与发布证据

| 检查 | 结果 |
|---|---|
| `flutter analyze --no-pub` | 通过，No issues found |
| `flutter test --no-pub --reporter expanded` | 234/234 通过 |
| Windows Credential Manager 临时凭据 | Unicode 密码写入、读取、删除、删除后不存在均通过 |
| `flutter build windows --release --no-pub` | 通过 |
| EXE FileVersion/ProductVersion | `1.5.0+6` |
| Release 启动 | 携带 `README.md` 隐藏启动 5 秒，未提前退出 |
| 模型资源 | PP-OCRv6 det/rec/yml、Silero v4/v6 均存在且字节数与清单一致 |
| 原生运行库 | `vibekits_onnx.dll`、`onnxruntime.dll`、`sqlite3.dll`、7-Zip EXE/DLL 均存在 |

## 构建中发现并闭环的问题

1. `flutter_secure_storage_windows` 依赖 Visual Studio ATL，标准环境缺 `atlstr.h`，Release 构建失败。
2. 改为 Windows Credential Manager FFI 与 macOS Keychain 系统适配，移除插件和 21 项不再需要的传递依赖。
3. 真实凭据测试发现删除后 `CredReadW` 的 `GetLastError` 跨 Dart FFI 边界不稳定；按 API 失败且空结果处理为“不存在”，再次真实往返通过。
4. 第二次链接被旧 Vibekits Release 实例占用；确认进程后结束测试实例，第三次 Release 成功。

## 明确未完成/未伪装完成

- DeepSeek Harness 官方仓库、MIT 许可证、Web/headless/ACP 能力和官方 CLI 版本已核验；本机 Node 24.18/npx 11.16 满足要求。
- `npx` 官方包帮助探测在下载阶段超过 2 分钟无输出后人工取消。因此只确认适配器自动测试通过，不能写成 Harness 官方包已真实启动。
- macOS Keychain、PostgreSQL 真实远程服务器、Harness macOS 启停和 macOS Release 尚无当前机器实证。
- MySQL/MariaDB、数据库写会话、ACP 原生会话、远程工作台重构、文件搜索和截图仍按需求总账继续开发。
