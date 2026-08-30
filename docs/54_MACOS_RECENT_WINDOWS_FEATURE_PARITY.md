# macOS 最近 Windows 功能对齐与实机验收

状态：代码已对齐，等待 macOS 实机 Release 验收。

## 1. 本次进入 macOS 的能力

- Harness 右侧 60px 纵向工具轨；去掉“工具”总按钮，MCP 开关、能力和设置入口统一为小图标，悬浮显示全名。
- VibeKits 设备名称、10 位硬件识别码和 MCP 开关持久化。
- 本 APP、本机进程、局域网三个实时 MCP 目录。
- `SO_REUSEADDR + SO_REUSEPORT` 多 APP 同端口 LMCP 发现。
- 本机/局域网设备数量角标和接口详情。
- 飞书快捷任务写入 Harness 输入框。
- Harness 工具调用记录。
- RustDesk/Harness 当前连接状态入口。
- 标准 `initialize/tools/list/tools/call` 接口描述规范。

macOS 继续使用原生 Flutter `DeepSeekAgentWorkspace`，不会加载 Windows 专用 `webview_windows`。上述能力已移植到该工作区，而不是强行复用 Windows WebView 页面。

## 2. macOS 权限

Debug 和 Release 都必须包含：

```xml
<key>com.apple.security.network.client</key><true/>
<key>com.apple.security.network.server</key><true/>
```

`network.server` 用于 UDP 47831 发现监听和本机 MCP 服务；缺失时 MCP 开关不能显示正常在线。串口能力继续使用 `com.apple.security.device.serial`。正式签名、Notarization 或企业 MDM 仍可能限制局域网；首次运行出现本地网络提示时必须允许。

## 3. Mac 编译

在项目根目录执行，工程、Flutter 和缓存均使用 Mac 的非系统数据卷目录：

```bash
flutter pub get
flutter analyze
flutter test test/mcp_device_identity_test.dart \
  test/mcp_capability_directory_test.dart \
  test/lan_peer_discovery_service_test.dart
flutter build macos --release
```

产物：`build/macos/Build/Products/Release/Vibekits.app`。

## 4. 实机验收

1. 打开智能体页面，确认右侧出现 60px 工具轨。
2. 悬浮六个图标，确认显示完整名称和状态。
3. MCP 关闭时点击图标：应先显示权限和风险说明；取消后不发布，点击“确认开启”后才广播和允许普通 MCP 调用。
4. 再点击 MCP 图标关闭：另一台 VibeKits 应立即收到 `goodbye` 并移除 Mac。
5. 再次打开：4 秒内出现 `VibeKits@<Mac名称>-<硬件码>`。
6. 同一台 Mac 同时运行两个测试 APP，确认都能绑定 UDP 47831，没有 `Address already in use`。
7. 点击本机/局域网图标，确认设备数量、硬件码和工具接口可见。
8. 修改对方 `catalogRevision`，确认列表自动更新。
9. 选择飞书快捷任务，确认文本进入输入框但不会未经任务执行自动发送消息。
10. 打开调用记录和远程状态，确认没有 Windows 路径或 PowerShell 依赖。
11. 在 Release 签名包重复 3-7；只验证 Debug 不算完成。

## 5. 当前验证边界

Windows 可以完成 Dart 静态检查和跨平台领域测试，但不能生成或签名 `.app`。macOS Release 构建、系统本地网络权限、组播多实例和真实 UI 必须在 Mac 上执行并保留日志/截图。失败时记录 macOS 版本、芯片、签名类型、网卡、socket 错误码和 `flutter doctor -v`，不能只报告“Mac 不可用”。
