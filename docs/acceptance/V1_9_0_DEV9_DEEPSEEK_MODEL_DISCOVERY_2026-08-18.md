# v1.9.0-dev.9 DeepSeek 模型发现验收

日期：2026-08-18  
平台：Windows x64  
源码版本：`1.9.0-dev.9+19`

- 设置页可使用当前 API Key 请求当前兼容端点的 `/models`。
- Authorization Key 不进入 URL、命令行、普通设置、日志或项目文件。
- 模型列表来自端点响应，支持 `deepseek-chat`、`deepseek-reasoner` 和任意兼容端点自定义模型，不再依赖写死的 V4 名称。
- 本地真实 HTTP 端点的路径、Bearer Header、模型解析/排序 1/1 通过。
- 设置页异步加载并选择端点返回模型、任务启动传递选择结果通过。
- 官方 dsh + MCP + APP 工具全栈回归通过；`flutter analyze` 0 问题。
- Windows Release 构建成功；Harness 3.2 万文件增量复制改为 robocopy 后耗时 12.2 秒，发布目录仍包含 Node、dsh、MCP、ADB 与 OCR 模型。

真实 DeepSeek 官方 Key 联调仍需在不关闭用户现有 Debug 实例的情况下，由新 Release 设置页点击“验证 Key 并加载模型”完成。
