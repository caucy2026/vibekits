# VibeKits v1.9.0-dev.174 设置弹窗输入门禁验收记录

## 现场缺陷

macOS 的“设置 → 高级”弹窗覆盖在原生 Harness WKWebView 上时，底层原生鼠标监听器仍会接收滚轮与点击事件。结果是高级内容无法滚动，底部“取消/保存”虽可见但无法操作。

## 修复

- 新增进程级、引用计数的 `HarnessWebViewInputGate`。
- 打开应用级设置弹窗前立即暂停底层 WKWebView 输入，弹窗关闭或抛错后必定恢复。
- Harness 内部弹层与应用设置共用同一个门禁，嵌套弹层只在最后一层关闭后恢复输入，避免提前恢复造成事件穿透。
- 保留低高度窗口自适应尺寸和高级页面内部滚动，不改变 Harness 正常工作逻辑。

## 自动验收

- 输入门禁单测覆盖：嵌套获取/释放、异常恢复。
- Widget 回归覆盖：设置打开时门禁关闭、底部“取消”可点击、关闭后门禁恢复。
- 低高度 `1024×600`、文字缩放 200% 场景覆盖：高级页可滚动到集群配置与底部保存按钮，无布局异常。
- 共享 UI 契约覆盖：macOS/Windows 继续共用 Harness 工作区；原生指针路由与 Flutter 弹层门禁保持一致。
- `flutter test` 相关组合套件 35 项全部通过；`flutter analyze --no-pub` 为 0 问题。

## macOS 真窗口验收

以重新构建并重新启动的 `build/macos/Build/Products/Release/Vibekits.app` 验证：

1. 真实鼠标点击主窗口设置图标后弹窗打开：`/private/tmp/vibekits-dev174-settings-cgevent.png`。
2. 真实鼠标点击“高级”后立即切换成功：`/private/tmp/vibekits-dev174-advanced-clicked.png`。
3. 在高级内容区发送真实滚轮事件后，页面滚动到“允许作为局域网仿真机/集群任务中心”：`/private/tmp/vibekits-dev174-advanced-scrolled.png`。
4. 真实鼠标点击底部“取消”后弹窗关闭，主界面恢复：`/private/tmp/vibekits-dev174-cancel-closed.png`。

候选信息：`1.9.0.174 (2174)`；主程序架构 `x86_64 arm64`；`codesign --verify --deep --strict` 通过；当前 `TeamIdentifier=not set`，属于本地临时签名候选而非正式 Developer ID 发布包。

## 发布边界

dev.174 是针对现场点击/滚动事件穿透的候选。必须以重新构建、重新启动后的精确 Release App 进行真窗口复验，旧 dev.173 进程不包含本修复。

后续同轮需求把高级页首项调整为可复制的本机统一 ID，并要求 macOS 仿真机开关同时管理系统 Remote Login（SSH）。这项变化需要重新构建候选，以上 dev.174 首次构建截图仅证明输入门禁，不代表 SSH 功能已完成发布验收。
