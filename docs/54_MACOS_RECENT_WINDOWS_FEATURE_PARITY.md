# macOS 最近 Windows 功能对齐与实机验收

状态：dev.147 在 dev.146 Universal/macOS 12+ 门禁之上恢复官方 Harness Web 交互面，并保留 VibeKits MCP、OCR、飞书、日志和 RustDesk 等外围能力。dev.145 仍是上一个已公证回退基线；dev.147 必须重新通过签名、公证、精确候选 App Harness 和 LAN MCP 门禁后才能替换 `bin/Vibekits.app`。

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

dev.147 修正了 dev.146 过度替换官方交互层的问题：Windows 和 macOS 正式桌面端统一进入 `OfficialHarnessWorkspace`，由固定版本的官方 DSH Web 自己管理项目、会话、对话、模型、权限、Skills 和 Settings → Plugins。macOS 使用 WKWebView，Windows 使用 WebView2，但两者只通过同一个 `HarnessWebViewBridge` 适配；Flutter `DeepSeekAgentWorkspace` 只用于自动测试和不支持官方 WebView 的平台降级，不能成为另一套桌面产品界面。

### 官方 Harness 可升级与跨平台单 UI 架构门禁

目标分层固定如下：

1. `OfficialHarnessWorkspace`：唯一桌面 Harness 交互入口。官方 DSH Web 是项目、会话、对话、模型、权限、Skills 与插件设置的唯一事实源，不在 Flutter 中复制这些状态和操作。
2. `HarnessWebViewBridge`：只适配 WKWebView/WebView2 的加载、脚本和消息通道。平台分支不得包含产品功能、菜单或持久化逻辑。
3. `DeepSeekHarnessService`：固定版本运行时适配层，只负责启动、停止、凭据迁移、端口和错误映射；不得改写官方页面的插件/项目数据模型。
4. `VibekitsHarnessToolBridge`：稳定 MCP/工具边界。VibeKits 的本机和局域网工具通过官方 Harness 工具调用面进入，工具 ID、Schema、风险、取消和证据语义不随官方 UI 升级变化。
5. `VibeKits extension rail`：MCP 开关与目录、OCR、飞书、调用日志和 RustDesk 状态仍位于官方 WebView 外侧的 Flutter 工具轨；它不遮挡或替换官方 Settings、Plugins、项目栏和输入框。

官方 DSH 升级必须是显式版本波次，不允许运行时自动漂移：固定 package/version、Node ABI 和 runtime manifest；把对上游的兼容修改保存为可审计、可重复应用的版本化 patchset，禁止手工修改打包后的 `node_modules`。升级流程为“构建新 runtime → 运行旧/新协议 fixture → 能力协商 → Windows/macOS 同一交互合同测试 → 两端 Release 冒烟 → 再切换默认版本”，任何一步失败都回退上一 runtime，而不是临时分叉 UI。

适配器必须容忍上游增加未知事件和字段，未知字段保留或忽略但不能崩溃；缺少必需能力时显示明确的“不兼容/需升级”，不得把失败解释为任务空闲。VibeKits 只从官方 Web 的稳定消息/会话接口投影运行状态和工具审计，不接管官方会话内容。每次升级要保存消息 fixture、官方插件清单、能力清单、迁移结果和回滚证据。

跨平台验收采用一份参数化测试清单，同一用例同时约束 Windows 与 macOS：创建/切换/并行会话、独立草稿、默认折叠时间线、选中态 `…`、运行态转圈、停止与外部资源清理、永久删除、MCP 发现/调用/结果/取消、重启恢复和 RustDesk 状态。平台只能对“不可用的系统能力”做显式跳过，不能另写一套期望。

迁移门禁：`local_models_tab.dart` 的正式桌面入口必须是 `OfficialHarnessWorkspace`；禁止再把 macOS/Windows 分成官方 Web 与自研会话页两套产品。官方 composition 必须持续包含 `dsh-host-plugin-inventory`、`dsh-client-ui-settings-plugin-inventory` 和 `dsh-client-ui-settings-plugins`。升级或裁剪依赖后，缺任一项即测试失败。官方当前提供插件配置和已加载插件只读清单，不把未经审核的社区“市场”冒充官方功能；第三方插件引入必须另做固定版本、许可证、权限和供应链审查。

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
./tool/prepare_7zip_runtime_macos.sh
flutter build macos --release
./tool/verify_macos_release_compat.sh build/macos/Build/Products/Release/Vibekits.app
./tool/sign_macos_release.sh build/macos/Build/Products/Release/Vibekits.app
./tool/verify_macos_harness_signed_runtime.sh build/macos/Build/Products/Release/Vibekits.app
```

Release Xcode 阶段会调用 `tool/package_harness_runtime_macos.sh`，将 Harness、ADB、7-Zip 和 Git 运行时复制到 App 私有目录；任一源运行时缺失、单架构或最低系统版本超过 macOS 12 时必须构建/验收失败。`sign_macos_release.sh` 是本机联调使用的 ad-hoc 签名门禁，不替代 Developer ID 签名和公证。Developer ID 与 ad-hoc 链分别使用 `HarnessNode.entitlements` 和 `HarnessNodeAdHoc.entitlements` 单独签署 Node，均保留 Hardened Runtime 与 `allow-jit`；ad-hoc 仅因没有 Team ID 才对 Node 增加 library-validation 例外。Rosetta/x86_64 运行 Node 时必须加 `--jitless`，并真实启动 DSH JS 入口；禁止用 `node --version` 冒充全功能，也禁止为方便而授予 `allow-unsigned-executable-memory`。对外发布必须设置 `VIBEKITS_DEVELOPER_ID_APPLICATION` 和 `VIBEKITS_NOTARY_PROFILE`，再执行 `tool/sign_and_notarize_macos_release.sh`；脚本会在上传前启动精确候选 App并由 Harness 真实调用只读 MCP 目录，再验证 Developer ID、notarytool Accepted、staple 和 Gatekeeper，任一失败都禁止外发。

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

dev.145 曾用 Flutter 3.41.9/Dart 3.11.5 验证 Universal/Rosetta。dev.146 不再声明“外壳 10.15、部分工具 11/12”的分裂边界：Xcode、CocoaPods 和 Info.plist 最低版本统一为 macOS 12.0，Release 脚本扫描 App 内所有 Mach-O，任一切片的 `minos` 高于 12.0 即失败。

官方 DSH 0.1.1-rc.2 的依赖使用 Node 22 API，内置 Harness 继续使用最低可行 Node 22.19.0；不为了降低数字而换成会缺失 `node:util.parseEnv` 的 Node 18。因为用户要求的是 macOS 12+全功能，而不是更旧系统上仅能打开空外壳。

当前机器已恢复 `Developer ID Application: zhen ji (26T5WV4GLP)` 和可连接 Apple 的 `KEMI_NOTARY` profile。dev.146 精确候选的主程序、ADB、Harness、Git、7-Zip 及全部 frameworks 已用该身份逐项签名，内置 Node 额外保留 JIT entitlement；Hardened Runtime、时间戳、深度严格验签、ARM64 App、Rosetta App 和 Intel DSH/ADB/7-Zip/Git 实际执行均通过。生产 LMCP 客户端已对先启动的目标节点完成 `last_result` 只读调用并取得 verified 报告；真实模型驱动 Harness 仍会把局域网 MCP 实例/目录发给已配置的 DeepSeek 服务，因此该步必须在用户明确同意数据出站后执行。Apple 公证必须在此门禁通过后提交，不能提前复用旧票据。

历史回退基线 dev.145 Apple 公证于 2026-09-01 返回 `Accepted`（Submission ID `9a0cddb1-41ce-4fe5-a231-7feb209fc128`），ticket 已 staple/validate，Gatekeeper 返回 `source=Notarized Developer ID`。

正式归档为 `bin/Vibekits-1.9.0-dev.145+2145-macos-universal-notarized.zip`，SHA-256 为 `60dff7aec1ec2a4887d2f9d2819c5b3b043cc90c89570697389945918352392b`。该归档是唯一允许标记为 dev.145 已公证候选的包；dev.144 归档仅保留用于历史回退，不得标记为当前正式版本。最终 `bin/Vibekits.app` 的真实 Harness MCP 目录读取发现先启动的 `192.168.3.62` KEMI-BM，状态为 verified、callable 且有 1 个空闲槽。
