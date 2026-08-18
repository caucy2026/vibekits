# v1.9.0-dev.10 Harness 会话与输入体验验收

日期：2026-08-18

平台：Windows x64
源码版本：`1.9.0-dev.10+20`

- 模型设置默认候选来自 DeepSeek 官方 API 文档：`deepseek-v4-flash` 与 `deepseek-v4-pro`；输入 Key 后以当前端点 `/models` 返回为准，并继续支持自定义兼容端点模型 ID。
- 工作区选择后立即写入应用设置；应用设置异步加载完成时，已打开的 Harness 页面会采用恢复路径，不再停留在“选择工作区”。
- 每个工作区最近 80 条 Harness 消息保存到用户应用数据目录，重新打开应用或切换回该工作区后恢复；API Key 仍只进入 Windows Credential Manager/macOS Keychain，不写入会话、项目或普通设置文件。
- 输入区改为 Codex 式一体化 Composer：透明正文输入、底部模型入口、状态提示和圆形发送按钮，限制最大宽度并减少无效空白。
- `flutter analyze` 通过，0 问题。Harness 定向 Widget 测试在本机测试宿主启动阶段无输出超时，未将其记录为通过。
