# VibeKits 1.9.0-dev.148 Harness 点击恢复验收

日期：2026-09-02

## 缺陷

dev.147 为修首次声明页，把 macOS 整个 `WKWebView` 配置为全局抢占手势。页面可加载、DOM 与无障碍树均正常，但 AppKit 收不到官方控件完整的 click/up，表现为打开侧边栏、新建会话、添加工作区、搜索和设置等左侧按钮点击无效。dev.147 已明确拒收，不能进入 `bin`。

## 修复

- macOS 恢复 `AppKitView/WKWebView` 的平台默认事件分发，不再注册全局 eager recognizer。
- Windows 继续使用 WebView2，未改变事件模型。
- 首次声明不再用破坏全页面的手势补丁；以真实嵌入 App 点击为发布门禁。
- 保留 dev.147 已验证的官方 DSH、VibeKits 外侧工具栏和父进程看门狗。

## 已完成的交互验证

同一个正式 DSH 实例已逐项验证：

- 侧边栏收起后出现“打开侧边栏”，重新打开后恢复完整工作区树。
- 新建会话可点击并选中新会话。
- 搜索按钮展开输入框；输入 `harness` 后只返回匹配项，清除操作可恢复。
- 工作区选择菜单列出 `tmp`、`harness`、`2` 和“添加工作区…”。
- Agent 模式菜单列出标准、PTC、极简、创造四种模式。
- 权限菜单列出只读、工作区读写、完全访问。
- 模型菜单显示当前模型与推理等级。
- 输入框可编辑，输入后发送按钮启用；自测文本已清空且没有发送给模型。
- 设置弹窗可打开；插件页可切换“插件配置/插件列表”，实际读取 167 个插件条目。

## 尚未放行

- 必须在新 dev.148 签名 App 内由真实鼠标再次点击左侧、工作区选择及添加工作区；外部 Computer Use 服务当前会在 click 时退出，不能用页面加载测试替代这一步。
- Apple 公证、Windows WebView2 和模型驱动 LAN MCP 仍需按 dev.148 精确产物重跑。
- 上述门禁全部完成前禁止复制到 `bin` 或宣称正式发布。

## 自动与构建证据

- `flutter analyze --no-pub`：0 issue。
- `flutter test --no-pub`：657 passed、15 gated skips、0 failed。
- `flutter build macos --release --no-pub`：成功，668.6 MB。
- Universal/macOS 12+ 完整兼容门禁通过；Harness、ADB、7-Zip、Git 均在包内。
- Developer ID：34 个 Mach-O 严格验签通过；包内 ARM64/x86_64 Node 与 DSH 均可启动。
- 当前精确签名候选已启动，界面版本为 `v1.9.0-dev.148+2148`，左侧官方控件重新进入 macOS 无障碍树。
- SHA-256：App executable `e4c89f31ab02b97f4779d7e35124ac4cbb48ceedd99c9880b0af01585e13029d`；App.framework `e8fb85af9b92ca83688748bd4de23daa212478927b27e6f7ec8c76103e7e9d0a`。
