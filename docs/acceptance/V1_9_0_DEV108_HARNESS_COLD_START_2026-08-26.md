# v1.9.0-dev.108 Harness 冷启动修复验收

日期：2026-08-26  
平台：Windows x64  
版本：`1.9.0-dev.108+118`

## 现场问题

用户在真实 Release `v1.9.0-dev.107+117` 首次进入智能体页面时，界面在“本地 DSH 首次装载较慢”停留 50 秒以上。

对应真实日志记录：

- DSH 进程启动：`2026-08-26T02:52:15.641364Z`
- DSH Web 输出监听地址：`2026-08-26T02:53:40.499034Z`
- 后端启动耗时约：`84.858 秒`

因此问题位于官方 DSH Web 在端口监听前的依赖装载，不是 Flutter 动画、WebView 页面渲染或旧版本误判。

## 原因与修改

打包运行时共有 32,761 个文件。官方 DSH Web Profile 默认组合了当前 VibeKits 不使用的可选依赖：

- `llm-pi-ai`：多模型提供商适配器；VibeKits 当前只公开 DeepSeek。
- `session-telemetry-otel`：会话遥测；VibeKits 已明确关闭遥测。
- `client-hmr`：前端热更新；Release WebView 不进行开发态热更新。

这些插件即使处于空配置或关闭模式，也会让 Node/Windows Defender 在冷启动期间解析和检查大量依赖文件。本轮使用 DSH 官方 Cordis Patch 机制把三个插件标记为 `disabled: true`，没有修改会话、工作区、DeepSeek 模型、MCP、授权或 VibeKits 工具链。

## 真实启动结果

使用 Windows Release 启停脚本执行两次完整 APP 生命周期；计时包含 APP 进程启动、主窗口出现、进入 Harness、HTTP 轮询和 DSH 就绪：

| 轮次 | Harness 就绪 | HTTP | APP 正常退出 | DSH 子进程回收 |
|---:|---:|---:|---|---|
| 1 | 5,622 ms | 200 | 通过（3,919 ms） | 通过 |
| 2 | 5,099 ms | 200 | 通过（3,359 ms） | 通过 |

- 平均就绪：`5,360.5 ms`
- 最慢就绪：`5,622 ms`
- 相比现场 84.858 秒，后端可用等待下降约 93.7%。
- 两轮均未残留 DSH 子进程。

原始计时记录：`.tmp/harness-dev108-startup.csv`。

## 结论

现场出现的 50～85 秒异常首次装载已经消除，当前完整 APP 到 Harness 可用稳定约 5～6 秒。此前提出的“稳定 3 秒”属于下一档性能目标，本报告不把 5～6 秒冒充 3 秒达成；后续需采用官方单文件构建、Node Snapshot 或等价的预编译运行时，不能以后台残留 DSH 进程换取假启动速度。
