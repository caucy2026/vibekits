# macOS 最近 Windows 功能对齐与实机验收

状态：Apple Silicon Release 和 Rosetta Intel 运行已验证；App 外壳支持 Intel macOS 10.15+，当前官方 DSH/Harness 因 Node 22.19 限制需要 macOS 11.0+。dev.145 已完成 Developer ID 签名、Apple 公证、ticket 装订、Gatekeeper 验证和签名后真实 Harness MCP 冒烟，可作为正式 macOS Universal 候选。

## 1. 本次进入 macOS 的能力

- Harness 右侧 60px 纵向工具轨；去掉“工具”总按钮，MCP 开关、能力和设置入口统一为小图标，悬浮显示全名。
- Harness 左侧项目/会话栏：标准 800px 窗口可见，支持新建、切换、收起和重新打开；不再沿用导致 App 壳内永久隐藏的 1020px 门槛。
- 多工作区目录：支持文件夹 `+` 添加、搜索、管理、切换，以及每个项目内单独新建会话。
- 项目显示名称可独立编辑并持久化，名称不替代绝对路径、不重命名磁盘目录，也不改变 Harness 权限根目录。项目省略号与鼠标右键打开同一套白色圆角菜单，包含编辑名称、Finder 定位、在此新建会话、切换和安全移除。
- 会话归属与移动：一个会话同一时刻只属于一个工作区；桌面鼠标按住会话即可立即拖到目标项目，不要求长按等待；拖动手柄使用抓取光标，键盘/辅助功能用户可从会话菜单选择目标。会话操作层是依附当前行右侧展开的宽信息卡，明确显示来源名称、真实路径、状态、时间和所有目标，而不是狭窄级联菜单。
- 会话永久删除：选中会话的操作菜单提供独立删除入口，二次确认必须明确“不可恢复”。确认后删除该会话的聊天、推理、规划、工具时间线、结果和草稿，但不删除项目文件与其他会话；运行中的会话必须先停止。
- VibeKits 设备名称、10 位硬件识别码和 MCP 开关持久化。
- 本 APP、本机进程、局域网三个实时 MCP 目录。
- `SO_REUSEADDR + SO_REUSEPORT` 多 APP 同端口 LMCP 发现。
- 本机/局域网设备数量角标和接口详情。
- 飞书快捷任务写入 Harness 输入框。
- Harness 工具调用记录。
- RustDesk/Harness 当前连接状态入口。
- 标准 `initialize/tools/list/tools/call` 接口描述规范。

dev.145 的现状仍是 macOS 使用 Flutter `DeepSeekAgentWorkspace`、Windows 使用 `OfficialHarnessWorkspace + DSH WebView`。这两条入口虽然共用工具桥，却不是同一套交互、会话和状态机，不能作为长期完成状态。自下一次 Harness 交互改版起，Windows 与 macOS 必须收敛到同一套 Flutter 工作区；官方 DSH 只作为可替换执行内核，不允许再分别维护两套用户行为。

### 官方 Harness 可升级与跨平台单 UI 架构门禁

目标分层固定如下：

1. `HarnessExperience`：唯一的跨平台 Flutter 交互层，负责项目、会话、独立草稿、执行时间线、停止、删除、权限提示和 MCP 可见状态；Windows/macOS 使用完全相同的 Widget、状态机和持久化合同。
2. `HarnessEngineAdapter`：官方 DSH 版本适配层，只负责启动、能力协商、事件归一化、发送、取消、恢复和错误映射。上层不得读取官方 Web DOM，也不得依赖某个 DSH 页面结构或 CSS 类名。
3. `HarnessPlatformRuntime`：薄平台层，只处理 Node/DSH 路径、进程组终止、Keychain/Credential Manager、Unix socket/Named Pipe 和签名规则；不得包含会话或 UI 行为。
4. `VibekitsHarnessToolBridge`：稳定 MCP/工具边界，工具 ID、输入输出 Schema、风险、取消和证据语义不随皮肤变化；官方升级不能绕过此桥直接调用物理工具。

官方 DSH 升级必须是显式版本波次，不允许运行时自动漂移：固定 package/version、Node ABI 和 runtime manifest；把对上游的兼容修改保存为可审计、可重复应用的版本化 patchset，禁止手工修改打包后的 `node_modules`。升级流程为“构建新 runtime → 运行旧/新协议 fixture → 能力协商 → Windows/macOS 同一交互合同测试 → 两端 Release 冒烟 → 再切换默认版本”，任何一步失败都回退上一 runtime，而不是临时分叉 UI。

适配器必须容忍上游增加未知事件和字段，未知字段保留或忽略但不能崩溃；缺少必需能力时显示明确的“不兼容/需升级”，不得把失败解释为任务空闲。会话、工具步骤和终态使用 VibeKits 自有稳定模型，上游事件只通过映射表进入该模型。每次升级要保存事件 fixture、能力清单、迁移结果和回滚证据。

跨平台验收采用一份参数化测试清单，同一用例同时约束 Windows 与 macOS：创建/切换/并行会话、独立草稿、默认折叠时间线、选中态 `…`、运行态转圈、停止与外部资源清理、永久删除、MCP 发现/调用/结果/取消、重启恢复和 RustDesk 状态。平台只能对“不可用的系统能力”做显式跳过，不能另写一套期望。

迁移门禁：在 Windows 正式 Release 完成上述共享入口回归前，`OfficialHarnessWorkspace` 只能视为待移除兼容入口；不得继续只向 macOS 的 `DeepSeekAgentWorkspace` 增加交互功能，也不得宣称 Windows 已同步。最终应删除 `local_models_tab.dart` 中按 `Platform.isWindows` 选择两套 Harness 页面这一分支。

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
./tool/verify_macos_release_compat.sh build/macos/Build/Products/Release/Vibekits.app
./tool/sign_macos_release.sh build/macos/Build/Products/Release/Vibekits.app
./tool/verify_macos_harness_signed_runtime.sh build/macos/Build/Products/Release/Vibekits.app
```

Release Xcode 阶段会调用 `tool/package_harness_runtime_macos.sh`，将运行时复制到 `Contents/Resources/tools/harness`；源运行时缺失或不完整时必须构建失败。`sign_macos_release.sh` 是本机联调使用的 ad-hoc 签名门禁，不替代 Developer ID 签名和公证。两条签名链都必须用 `HarnessNode.entitlements` 单独签署内置 Node，保留 Hardened Runtime 与 `allow-jit`，否则 V8 会在启动阶段崩溃。对外发布必须设置 `VIBEKITS_DEVELOPER_ID_APPLICATION` 和 `VIBEKITS_NOTARY_PROFILE`，再执行 `tool/sign_and_notarize_macos_release.sh`；脚本会在上传前启动精确候选 App 并由 Harness 真实调用只读 MCP 目录，再验证 Developer ID、notarytool Accepted、staple 和 Gatekeeper，任一失败都禁止外发。

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
16. 选中一个已停止的测试会话，执行“删除会话”；确认页必须列出聊天、推理、规划、工具时间线和草稿。取消后内容不变；再次确认后目标会话永久消失，项目文件和其他会话仍在。运行中会话必须拒绝删除并提示先停止。
17. 正式签名 App 必须运行 `verify_macos_harness_signed_runtime.sh`，再由 `verify_macos_harness_live_smoke.sh` 通过精确 App 工具桥调用 `vibekits.mcp.catalog_list`；只检查 Node 能启动或只检查签名均不算 Harness 可用。
18. Windows 与 macOS 必须运行同一组 Harness 交互合同测试；截图差异只能来自字体和系统控件，不得出现某平台缺少项目、会话、时间线、停止、删除、权限或 MCP 操作。官方 DSH 升级后要在两个平台重复这一门禁。

## 5. 当前验证边界

2026-09-01 已用 Flutter 3.41.9/Dart 3.11.5 生成 Universal Release；主程序 Intel slice 的 deployment target 为 10.15，并在 Rosetta 下实际启动为 `X86-64 (translated)`。ADB、Node、ripgrep、node-pty 和 sharp 均核对双架构/对应原生包。

必须区分两个边界：VibeKits 主程序可在 Intel macOS 10.15 启动；官方 DSH 0.1.1-rc.2 的依赖使用 Node 22 API，因此内置 Harness 使用最低可行 Node 22.19.0，其官方 Intel/ARM 二进制均以 macOS 11.0 为下限。禁止换成 Node 18 伪造 10.15 全功能：真实 CLI 会因缺失 `node:util.parseEnv` 立即失败。

当前机器已恢复 `Developer ID Application: zhen ji (26T5WV4GLP)` 和可连接 Apple 的 `KEMI_NOTARY` profile。`bin/Vibekits.app` 的主程序、ADB、Harness 及全部 frameworks 已用该身份逐项签名，内置 Node 额外保留 JIT entitlement；hardened runtime、时间戳、深度严格验签和真实 Harness MCP 调用均通过。用户授权后，dev.145 Apple 公证于 2026-09-01 返回 `Accepted`（Submission ID `9a0cddb1-41ce-4fe5-a231-7feb209fc128`），ticket 已 staple/validate，Gatekeeper 返回 `source=Notarized Developer ID`。

正式归档为 `bin/Vibekits-1.9.0-dev.145+2145-macos-universal-notarized.zip`，SHA-256 为 `60dff7aec1ec2a4887d2f9d2819c5b3b043cc90c89570697389945918352392b`。该归档是唯一允许标记为 dev.145 已公证候选的包；dev.144 归档仅保留用于历史回退，不得标记为当前正式版本。最终 `bin/Vibekits.app` 的真实 Harness MCP 目录读取发现先启动的 `192.168.3.62` KEMI-BM，状态为 verified、callable 且有 1 个空闲槽。
