# v1.9.0-dev.8 Harness MCP 工具闭环验收

日期：2026-08-18  
平台：Windows x64  
源码版本：`1.9.0-dev.8+18`

## 验收范围

- 官方 `@deepseek-ai/dsh@0.1.0-rc.7` 使用随包 Node 启动，运行阶段不调用 npm/npx。
- Harness 通过随包 MCP stdio 服务发现 APP 的版本化工具目录。
- APP 工具服务只监听 IPv4 loopback，并要求每次启动生成的随机令牌。
- 只读能力直接执行；设备、网络副作用和写操作要求 APP 内一次性审批。
- Harness/工具子进程退出或用户停止后，APP 工具服务随即关闭。

## 自动验收证据

| 链路 | 结果 |
|---|---|
| Dart 工具目录、风险、ADB、SQLite、文件搜索、HTTP、程序员计算器 | 9/9 通过 |
| HTTP 回环鉴权、默认拒绝风险操作、Node MCP list/call | 3/3 通过 |
| 官方 dsh → 模型工具调用 → MCP → APP SHA-256 → 模型最终回复 | 1/1 通过，exit 0 |
| Harness UI 启动、停止、宽屏会话 | 4/4 通过 |
| `flutter analyze` | 0 问题 |
| Windows Release | 构建成功，110.8 秒 |

Release 目录核对存在 `tools/harness/node.exe`、固定 dsh manifest、MCP 服务、内置 ADB 三件套以及 PP-OCRv6 tiny 检测/识别模型。启动冒烟时已有 Debug 实例占用全局单实例锁；Release 将请求转交后 exit 0，未强制关闭用户正在运行的实例。

全栈测试使用本机临时 HTTP 兼容端点，不读取或输出用户 DeepSeek Key。真实 DeepSeek 官方端点、物理串口、ADB 真机、远程数据库、SSH/SFTP 与 macOS 仍分别保留实机验收项。
