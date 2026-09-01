# VibeKits 1.9.0-dev.139 Harness 可审计交互验收

## 目标

将 Harness 从“只显示少量概括步骤”改为可中止、可复核、可持久的工程执行时间线。本界面不展示模型私有思维链，但必须展示所有可审计交互事实。

## 交互门禁

1. 选中的运行会话显示完整实时时间线与停止按钮。
2. 未选中的运行会话显示转圈，不显示 `…`；选中会话才显示 `…`。
3. 每次工具调用显示名称、目标、脱敏参数、脱敏结果、状态和耗时；内容可选择复制，不用单行省略号隐藏。
4. 时间线在任务结束后保留，写入对应会话；切换项目或重启 APP 后可重新查看。
5. 停止必须同时终止模型与由该任务启动的 Android 应用，并显示清理与验证结果。
6. 任务运行、工具后继续分析期间统一上报 BUSY/reasoning/toolRunning；只有真正终止或完成后才上报 READY。

## 安全边界

- 时间线最多保存 32768 字符，单次参数/结果摘要最多 1024 字符。
- `password`/`secret`/`token`/`apiKey`/`authorization`/`cookie`/`pairingCode` 类字段始终显示为 `<已隐藏>`。
- 不伪造模型思维链；只展示任务阶段、工具交互、返回证据和资源生命周期。

## 自动化证据

- `flutter test --no-pub test/harness_tool_bridge_test.dart test/deepseek_harness_test.dart`：54 通过、1 项按环境跳过、0 失败。
- 新增迟到工具回调终态门禁回归。
- 新增 Android 任务所有资源 `force-stop → pidof` 清理验证回归。
- `flutter analyze --no-pub`：0 issue。

## Release 与生产证据

- Flutter 3.47.0 macOS Release 构建成功，产物 613.0 MB；正式 App 已释放到 `/Volumes/ORICO/newlink-new/vibekits/bin/Vibekits.app` 并启动。
- `codesign --verify --deep --strict`通过；App executable SHA-256 `e60882d46f1dcc69f8921977b0292ec19a66478cb89c24912f1f7f51c5c88540`，App.framework SHA-256 `f388e7552bc713c993ffc625ead8b5ff3eb4f454e65c98244bc29ca70226a8fb`，内置 ADB SHA-256 `8c2672e2a9aa6ab6efec787195a54451b66f3a3043c4f27d1ef67f7b339e6970`。
- 正式 `${systemTemp}/vkh/v1.sock` 真实 `hello → getSnapshot` 成功：`publisherVersion=1.9.0-dev.139`、`streamSequence=3`；项目为 `测试1/idle`、`测试2/idle`、`harness/ready`，`busyCount=0`，无 dev.138 的残留 BUSY。
- 生产界面已可见版本 `v1.9.0-dev.139+2139`。旧版本已完成会话不补造当时不存在的工具细节；只有 dev.139 起新执行会持久完整时间线。
- 安全只读 UI 真任务在启动前遭遇 Computer Use `native pipe closed before response`，本记录不伪造任务成功。RustDesk 63 的 READY→BUSY→继续 BUSY→READY 三阶段截图仍需在下一条真实 Harness 任务中补验。
