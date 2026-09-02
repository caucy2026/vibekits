# VibeKits 1.9.0-dev.147 官方 Harness 插件界面验收

日期：2026-09-02
状态：**已拒收，禁止发布。** 该候选虽通过代码、构建和页面加载测试，但真实 App 点击复测发现 macOS 左侧官方按钮被全局手势接管阻断。修复与新验收转入 dev.148。

## 目标与边界

- 恢复官方 DSH Web 的项目、会话、输入、模型、权限、Skills 与 Settings → Plugins，不再由 VibeKits 自研页面替代这些官方能力。
- VibeKits 的 MCP 开关/目录、OCR、飞书、调用日志与 RustDesk 状态保留在 WebView 外的右侧工具轨，不遮挡、不复制、不修改官方插件状态。
- Windows/macOS 使用同一个 `OfficialHarnessWorkspace`。平台差异只在 `HarnessWebViewBridge`：Windows WebView2，macOS WKWebView。
- 官方 `@deepseek-ai/dsh@0.1.1-rc.2` 提供“插件配置”和“已加载插件列表”，并不提供第三方下载商店。社区市场插件未经过供应链与权限审查，不能伪装成官方功能或静默安装。

## 缺陷与修复

dev.146 的桌面产品入口被改为 Flutter `DeepSeekAgentWorkspace`，官方 Settings → Plugins 因而不可达。dev.147 把正式桌面入口恢复为官方 Web，同时保留自研页面作为 Flutter 自动测试/不支持 WebView 平台的降级入口。

macOS 首次“内测声明”现场出现按钮看似无法继续。进程采样确认 VibeKits 主线程、WebKit WebContent 与 DSH Node 均未死锁；同一 DSH URL 在独立浏览器可正常继续。dev.147 错误地为整个 WKWebView 配置全局 eager recognizer，随后真实用户复测证明它使 AppKit 无法把完整 click/up 送入官方页面，左侧按钮整列失效。此方案已在 dev.148 撤销。

退出路径自测还发现，直接终止桌面进程可能早于 Flutter widget `dispose`，从而留下官方 DSH 与插件 MCP Node。dev.147 为所有 Harness Node 进程注入只读父 PID 看门狗；子进程每 750 ms 检查 App 是否仍存在，App 消失即自行退出。Windows 继续保留 Job Object 的进程树兜底，正常“停止 Harness”仍先走既有显式清理。

## 本机证据

- `flutter analyze --no-pub`：0 issue。
- 全量 `flutter test --no-pub`：657 passed、15 gated skips、0 failed。
- 官方入口/插件/桥接/进程生命周期/项目会话/剪贴板/主界面定向回归：50/50。
- `flutter build macos --release --no-pub`：成功，668.6 MB。
- `verify_macos_release_compat.sh`：Universal x86_64+arm64、macOS 12+、Harness、ADB、7-Zip、Git 全部通过。
- Developer ID：34 个 Mach-O 全部完成时间戳签名与严格验签；Team ID `26T5WV4GLP`，内置 Node 原生/x86_64 启动验证通过。
- 精确候选实际启动：`Vibekits` 与包内 Node/DSH 同时运行，DSH 仅监听动态 `127.0.0.1` 端口；界面版本 `v1.9.0-dev.147+2147`。
- 生命周期实测：终止精确 App 后，DSH 主进程和两个 MCP 子进程在第一次 200 ms 轮询内全部退出；独立看门狗父进程消失测试同样在第一次轮询退出。
- Intel 实测：同一候选经 Rosetta 启动，`vmmap` 返回 `Code Type: X86-64 (translated)`；签名门禁同时真实启动包内 x86_64 Node 与官方 DSH。App、Node 与所有本机原生载荷保持 Universal/macOS 12+。
- 签名后 SHA-256：App executable `af3f6e90bbfb7de2d3c8b50cb945144a9a3aad9eb8a414efee62b7bfbb52346f`；App.framework `032f7563663ab329ce98f9d1113f57a5faeb205864cb522e1c47c6cee570d0ea`。
- 同一 DSH 实例的浏览器级交互：首次声明可继续；设置导航包含“通用设置/模型/插件/Agent 预设”；插件页包含“插件配置/插件列表”，插件配置真实列出“终端/Agent 循环/网页搜索”。
- 候选截图：`/private/tmp/vibekits-dev147-official-harness.png`；同一 DSH 实例插件页截图：`/private/tmp/vibekits-dev147-official-plugins.png`。

## 未完成发布门禁

1. 不允许复用 dev.146 公证票据；dev.147 必须生成新归档并取得新的 notarytool Accepted、staple 与 Gatekeeper 证据。
2. Codex Computer Use 外部服务仍会在任何 click/set_value 时退出，因此无法用该服务代替人工完成 App 内鼠标点击录像。不得修改或绕过其签名。代码合同、真实页面、独立浏览器交互均通过，但最终精确 App 的插件页人工点击仍需补证。
3. Windows 必须在 Windows 构建机验证 WebView2 的同一官方 Settings → Plugins、VibeKits 外侧工具轨及项目/会话操作；macOS 成功不能代替 Windows 真机。
4. 本轮没有授权把实时 LAN MCP 元数据发送给 DeepSeek，模型驱动 `vibekits.mcp.catalog_list` 未运行；不能据此声明 192.168.3.62 调用门禁已复验。
