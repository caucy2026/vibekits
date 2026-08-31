# macOS 最近 Windows 功能对齐与实机验收

状态：Apple Silicon macOS Release、内置 Harness 和本机 MCP 已实机验收；局域网双机、Intel 实机、Developer ID 签名与公证仍待完成。

## 1. 本次进入 macOS 的能力

- Harness 右侧 60px 纵向工具轨；去掉“工具”总按钮，MCP 开关、能力和设置入口统一为小图标，悬浮显示全名。
- Harness 左侧项目/会话栏：标准 800px 窗口可见，支持新建、切换、收起和重新打开；不再沿用导致 App 壳内永久隐藏的 1020px 门槛。
- 多工作区目录：支持文件夹 `+` 添加、搜索、管理、切换，以及每个项目内单独新建会话。
- 项目显示名称可独立编辑并持久化，名称不替代绝对路径、不重命名磁盘目录，也不改变 Harness 权限根目录。项目省略号与鼠标右键打开同一套白色圆角菜单，包含编辑名称、Finder 定位、在此新建会话、切换和安全移除。
- 会话归属与移动：一个会话同一时刻只属于一个工作区；桌面鼠标按住会话即可立即拖到目标项目，不要求长按等待；拖动手柄使用抓取光标，键盘/辅助功能用户可从会话菜单选择目标。会话操作层是依附当前行右侧展开的宽信息卡，明确显示来源名称、真实路径、状态、时间和所有目标，而不是狭窄级联菜单。
- VibeKits 设备名称、10 位硬件识别码和 MCP 开关持久化。
- 本 APP、本机进程、局域网三个实时 MCP 目录。
- `SO_REUSEADDR + SO_REUSEPORT` 多 APP 同端口 LMCP 发现。
- 本机/局域网设备数量角标和接口详情。
- 飞书快捷任务写入 Harness 输入框。
- Harness 工具调用记录。
- RustDesk/Harness 当前连接状态入口。
- 标准 `initialize/tools/list/tools/call` 接口描述规范。

macOS 继续使用原生 Flutter `DeepSeekAgentWorkspace`，不会加载 Windows 专用 `webview_windows`。上述能力已移植到该工作区，而不是强行复用 Windows WebView 页面。

### 项目、会话和权限关系

工作区目录只保存已添加项目的绝对路径和显示顺序；每个项目的会话仍保存在该工作区哈希对应的独立 conversation 文件中。移出工作区目录只隐藏入口，不删除会话记录，也不删除项目文件。

项目显示名称保存在工作区目录的 `names` 映射中，键始终是规范化绝对路径。搜索同时匹配显示名称、绝对路径和会话标题。项目文字使用 12.5px 加粗层级，会话使用 11px，拖动柄和命中区域不因字体缩小而缩小。

会话移动不是复制项目目录。移动前必须显示源路径、目标路径和权限变化并由用户确认；确认后该会话后续任务的 `HarnessAgentRequest.workspace` 固定为目标路径，原 `workspace-write` 权限不随会话继承。运行中的会话禁止移动。持久化顺序为先写目标、再从源移除：中断最多留下可恢复的重复记录，不能丢失唯一会话副本。

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
./tool/prepare_harness_runtime_macos.sh
flutter build macos --release
./tool/sign_macos_release.sh build/macos/Build/Products/Release/Vibekits.app
```

Release Xcode 阶段会调用 `tool/package_harness_runtime_macos.sh`，将运行时复制到 `Contents/Resources/tools/harness`；源运行时缺失或不完整时必须构建失败。`sign_macos_release.sh` 是本机联调使用的 ad-hoc 签名门禁，不替代 Developer ID 签名和公证。

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
12. Harness 页面必须显示“Harness 就绪”；执行一个只读工具后检查日志有真实工具 ID 和 `exitCode=0`，且不得依赖系统 `node/npm/npx`。
13. 添加第二个工作区，确认两个项目及各自会话同时可见；把一个已停止会话拖到目标项目，核对权限确认中的源/目标路径，确认后会话只出现在目标项目且后续任务工作目录为目标路径。
14. 用项目省略号和鼠标右键分别打开操作菜单；修改显示名称后重启 App，确认别名保留而目录名不变；选择 Finder 定位确认打开真实目录；移除必须二次确认且不得删除目录和会话文件。
15. 打开会话右侧信息卡，确认其显示来源项目、完整路径、更新时间及所有可移动目标；选择目标后仍必须进入 workspace-write 权限重绑定确认。

## 5. 当前验证边界

2026-08-31 已在 Apple Silicon Mac 上完成 Universal Release、ad-hoc 完整签名、Harness UI 与一次真实工具调用。系统本地网络权限、组播多实例和双机发现仍需保留独立证据；Intel 必须在 x86_64 Mac 或 Rosetta 下复核，不能只由 `file` 显示 Universal 就宣称 Intel 完成。失败时记录 macOS 版本、芯片、签名类型、网卡、socket 错误码和 `flutter doctor -v`。
