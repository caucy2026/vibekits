# v1.9.0-dev.23 官方 Harness Web 移植验收

日期：2026-08-19

## 验收范围

- Windows Harness 入口直接启动并嵌入官方 `dsh web`。
- 项目、会话、对话、模型、权限和任务状态不再由 Flutter 自制存储/界面接管。
- 官方 Web profile 继续加载 Vibekits MCP，工具的风险验证和审计保留在 App 边界。
- 无 API Key 时仍可进入官方界面，再按 Settings → Models 配置。

## 行为证据

| 项目 | 结果 |
|---|---|
| 官方仓库/README | `dsh web` 是 Web UI 入口，默认本机 `127.0.0.1:3080` |
| 官方 Web 指南 | Settings → Models 配 Key；Choose workspace 后才可使用 composer |
| Release 包 | 含 `@deepseek-ai/dsh-web-app@0.1.0-rc.7` 及 workspace/sidebar/conversation/permission/tool/plan/goal/jobs/subagent UI 包 |
| 官方 server 独立实启 | `dsh web --port 31999` 返回 HTTP 200，首页 12076 字节，停止正常 |
| 密钥 | Web request 允许空 Key；有旧凭据时只注入子进程环境 |
| 安装依赖 | 启动使用 Release 内置 Node/CLI/Web 包，不运行 npm/npx |

## 自动验收

| 验证 | 结果 |
|---|---|
| `dart format lib test` | 通过，202 个 Dart 文件已格式化 |
| `flutter analyze --no-pub` | `No issues found` |
| Harness/Web/工具桥 + 主界面定向回归 | 46/46 通过 |
| 进程生命周期修复后 Harness/工具桥回归 | 25/25 通过 |
| `flutter build windows --release --no-pub` | 最终构建通过（85.2 秒） |
| EXE FileVersion / ProductVersion | `1.9.0-dev.23+33` |
| EXE SHA-256 | `0777A62800B46E81B190FCCB8670C5B67A32EB85A6BD35250741590CAF1515E1` |
| Dart `data/app.so` SHA-256 | `EABE37D3680D8C20083FEEE39420B2279F5249666DF5F9CD7F794BAE35A14D2B` |
| Release 实启 | App `Responding=True`，WebView2=1，官方 Harness node=1；动态回环端口 HTTP 200，官方 HTML 12076 字节 |
| 强制结束 App 后进程树 | App 已退出，残留 Harness node=0 |

## 未完成边界

- macOS 官方 WebView 容器、内置 Harness/Node 产物与实机验收未完成。
- 真实 DeepSeek Key 的官方 UI 任务与 ADB MCP 真机回归仍需用户环境实证。
