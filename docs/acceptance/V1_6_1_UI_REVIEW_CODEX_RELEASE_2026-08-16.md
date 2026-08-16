# Vibekits v1.6.1 界面复核与正式发布验收

日期：2026-08-16
版本：`1.6.1+8`

## 范围

- 复核解压缩、系统清理、文档阅读、开发工具、本地模型五个主工作区。
- 将 DeepSeek 智能体收敛为 Codex 风格的持续会话工作区。
- 生成可独立运行的 Windows x64 正式发布目录和 ZIP。

## 交互验收

- 1024×700 下逐项切换五个主工作区，无 Flutter 异常和布局溢出。
- DeepSeek 支持工作区选择、环境刷新、空状态建议、持续追问、Markdown、复制、新任务、进度和停止。
- `Enter` 发送，`Shift+Enter` 换行；运行中输入框保留，可提前编辑下一条要求。
- 后续请求携带长度受控的对话上下文；切换到截图 OCR 再返回时保留当前会话。
- 移除无实际内容的后台任务入口；不再以“本地模式”误导联网工具状态。

## 自动验证

- `flutter analyze`：通过，`No issues found`。
- DeepSeek 与主界面定向测试：22/22 通过。
- `flutter test --reporter expanded`：238/238 通过。
- Windows Release 构建：通过。
- Release 隐藏启动 5 秒：未提前退出。
- EXE 文件版本与产品版本：`1.6.1+8`。

## 发布产物

- 目录：`release/Vibekits-1.6.1-windows-x64/`
- 压缩包：`release/Vibekits-1.6.1-windows-x64.zip`
- 校验：`release/SHA256SUMS.txt`

发布目录必须包含 Flutter 运行时、应用数据、ONNX Runtime、Vibekits ONNX 桥、SQLite、7-Zip 可执行文件与动态库，不能只交付单个 EXE。

## 真实边界

- 当前 Windows 机器完成构建和启动验收；macOS Xcode/arm64 实机发布仍待 macOS 主机。
- DeepSeek Harness 官方 npm 包在当前网络环境尚未完成真实下载和登录启动，Vibekits 的进程合同、流式会话、追问、停止和 UI 已用可控进程完成自动回归。
- 在 Harness 提供稳定结构化 ACP 协议前，审批事件和运行中消息注入无法与 Codex 原生协议完全等价；当前版本提供停止和下一轮持续追问，不伪造结构化审批。
