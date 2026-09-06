# VibeKits 1.9.0-dev.158 网络测速与关于页能力清单验收

## 交付范围

- 新增跨平台网络带宽测速工作区：延迟、抖动、下载、上传、阶段进度、实时速率、停止和重测。
- “关于我们”完整展示支持格式、自有数据说明、全部开发工具及本地/联网属性。
- 所有数量和条目从运行时格式路由表与工具注册表生成，避免 UI 文案与真实能力漂移。

## 测速合同

- 默认节点：`https://speed.cloudflare.com`。
- 延迟：5 次零字节请求，结果取中位数。
- 抖动：各延迟与中位数的绝对偏差，再取中位数。
- 下载：100 KB、1 MB、5 MB 渐进采样，报告有效速率 P90。
- 上传：100 KB、500 KB、2 MB 渐进采样，报告有效速率 P90。
- 数据边界：只发送内存生成的空白字节；不读取文件、剪贴板、项目、设备信息或凭据。
- 用户控制：测试中始终显示“停止测试”，停止会强制关闭当前 HTTP 客户端并回到可重试状态。

## 自动化结果

- `flutter analyze --no-pub`：0 issue。
- `network_speed_service_test.dart`：成功测量、阶段进度、精确字节数、P90 结果和取消路径通过。
- `about_capability_manifest_test.dart`：格式/工具单一数据源同步、自有开放格式说明通过。
- `widget_test.dart`：主导航、主题、窗口尺寸、文件路由、Harness/OCR 基础回归通过。
- Harness 调用：风险等级为 `controlsDevice`，未经批准不会产生测速流量。
- 联合回归：70 项通过，1 项仅因环境门禁跳过，0 项失败。

## GitHub 双平台云端构建

- 最终源码提交：`370bb5ed23affc0c6c52e7c403030b7e8a0fc961`，包含同事提交的 Harness 0.1.2-rc.1、共享 Skills、GitHub CLI 与统一智能体 CLI MCP，以及本次网络测速和关于页清单。
- macOS Release run `34028402765`：成功；完成 Universal x86_64+arm64、macOS 12+、Harness/ADB/7-Zip/Git/GitHub CLI 和 ad-hoc 云端验证。artifact `9987938014`，名称 `Vibekits-macOS-101`，大小 265,954,640 bytes，GitHub artifact SHA-256 `2a3cf6630f613df423ab26e010b2d4c62224089806e66574c6ae1f08492c9861`。
- Windows Compatibility run `34028402857`：成功；完成 Analyze、Harness UI/Agent/MCP、自更新、共享 UI、Release EXE、自包含运行时和打包验证。artifact `9987941419`，名称 `Vibekits-1.9.0-dev.158-2158-windows-x64`，大小 292,107,517 bytes，GitHub artifact SHA-256 `d9f683ce2f2db1e07ef15b5b9bf79704de755d0e11d4a765f7e0225b2a45365e`。
- 两项 artifact 创建于 2026-09-06，GitHub 当前保留至 2026-09-20。仓库此前没有 GitHub Releases/tag 附件发布约定，因此本轮沿用现有 Actions artifact 云端交付，不另建冲突渠道。

## 发布边界

GitHub macOS 流水线提供的是经过 Universal、最低系统和 ad-hoc 签名验证的云端候选，不是 Apple Developer ID 公证包。若要向 KEMI 商场或终端用户正式分发 macOS 包，仍须执行 Developer ID、notarytool、staple 和 Gatekeeper 门禁；本轮未把云端候选误称为 Apple 公证包，也未更新 KEMI 商场。
