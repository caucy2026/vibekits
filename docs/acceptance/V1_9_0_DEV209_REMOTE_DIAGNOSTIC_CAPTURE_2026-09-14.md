# VibeKits 1.9.0-dev.209 远程故障取证与配对载体修复验收

日期：2026-09-14

## 目标

当另一台 macOS/Windows 电脑上的应用出现异常时，控制端只输入已经获准的统一 VibeKits ID，就能像调试本机一样读取进程、应用清单、日志、崩溃报告和文件，执行受控 SSH/SFTP/ADB、安装、启动、停止与卸载，并在需要时取得一张当前屏幕截图。截图只是远程仿真诊断工具，不建立远程桌面，也不接管输入设备。

远程协助继续承担 Harness 项目、会话、历史、结构化时间线、任务发送、增量反馈和独立停止。远程协助与远程仿真共用 ID 和 RustDesk P2P/HBBR 网络引擎，但固定端点、授权、状态和关闭生命周期彼此独立。

## 已修复问题

1. RustDesk 配套引擎此前把授权的 VibeKits 固定端口转发误当成远程桌面连接，进入约 30 秒的 `TestDelay`，而首次配对允许等待两分钟，造成“确认并记住”后载体提前关闭。
2. Flutter 配对服务读取首行后取消输入流；载体关闭时待批准请求仍留在队列，页面因此显示已经失效的确认框。
3. macOS Harness live-smoke 与 LAN MCP 脚本仍读取旧 `~/Library/Application Support/Vibekits/Mcp`，会把历史连接文件中的旧 PID 当成当前签名候选。

对应修复为：

- 只有已经由原生握手授权且目标为 VibeKits 固定端点的 `VibekitsHarness` 连接可直接进入原始字节转发；普通 RustDesk 桌面连接和任意端口转发保持原行为。
- 配对通道在 `onDone/onError` 时立即撤销对应待批准请求；确认窗口订阅队列，载体撤销后自动关闭，不把它记录成用户拒绝。
- 验收脚本从候选 `Info.plist` 读取真实 bundle ID，并统一使用 `~/Library/Application Support/<bundle-id>/Vibekits/Mcp/tool-bridge.json`。

## 一次性截图与文件回传设计

- 被控端工具：`vibekits.device.screenshot`。macOS 在 VibeKits 自身进程内通过系统屏幕读取 API 抓取单帧 PNG；Windows 通过系统图形 API 抓取虚拟屏幕单帧。
- 控制端工具：`vibekits.simulator.screenshot`。先调用被控端截图，再通过严格校验主机指纹的 SCP 下载；目标与本机 SHA-256 不一致时失败关闭。
- 通用文件回传：`vibekits.simulator.download_file`。只允许绝对文件路径、受控临时目录、2 GiB 上限和 SHA-256 校验。
- macOS 屏幕权限集中显示在“设置 → 高级 → 远程仿真机 → 仿真授权”；不在 Harness 工作区弹窗。用户可在第一次需要截图时授权，既有仿真配对调用方之后不重复请求应用内批准。
- 屏幕读取和 SSH/MCP 权限独立。未授予屏幕读取时，日志、进程、SSH、文件和 ADB 仿真仍保持可用。

## 自动与本机 Release 证据

- RustDesk ARM64 与 x86_64 Release 分别构建成功，组合后的 Universal Relay 为 `x86_64 + arm64`、最低 macOS 12.0；SHA-256：`38ad421411966a422a0db83dd782a8253b0feea89b57222624ce18b000a07731`。
- RustDesk 定向回归 `only_authorized_managed_harness_connections_skip_desktop_delay_handshake`：1/1 通过。
- VibeKits 远程协助、远程仿真、PAD 控制角色、Windows/macOS 共用桥、SSH/SFTP 与远程工作区组合：119/119 通过。
- 首次配对专项包含：密码先验拒绝、证书与 nonce 绑定、授权范围固定、载体断开立即撤销和弹窗自动关闭。
- 远程会话专项包含：mTLS hello、项目/会话/历史同步、命令幂等、增量反馈、独立停止、撤权、断线 stale 及统一资源回收。
- 精确 macOS Release：`1.9.0-dev.209+2209`；Developer ID `zhen ji (26T5WV4GLP)` 深度严格验签通过，Universal macOS 12+、Harness、ADB、7-Zip 与 Git 兼容门禁通过。
- 签名候选 ZIP：`dist/candidates/Vibekits-1.9.0-dev.209+2209-macos-universal-developer-id-signed.zip`，SHA-256 `ffaecbe49ccee605287e35442d54842acce5c83b07e25475302ef3f2e234e06e`。
- 本机签名 App 工具桥真实调用通过：连接文件 PID 与当前候选 PID `28325` 一致，`verify_harness_local_bridge.mjs` 完成目录和本机调用验证。
- 真实 UI：dev.209 Harness 正常显示；设置页可打开并滚动；高级页显示统一 ID、连接设备、历史、远程仿真、集群和协同区域，底部保存/取消可见，未出现白屏或遮挡。

## 真实目标 ID 证据

控制端对目标 ID `4456560334` 使用当前 Universal Relay 强制 HBBR：

- 真实 MCP 初始化与目录：204 项工具；只读远程协助状态和 VibeKits 进程调用通过。
- 完整远程仿真：SSH 命令通过；28 字节临时文件上传、远端 SHA-256 回读通过；测试退出后动态监听端口已回收。
- 目标已安装精确 dev.209，并在系统授权屏幕读取后完成真实单帧回传：`1920×1080`、目标与控制端 SHA-256 一致，`manual_real_harness_simulator_screenshot_test.dart` 通过。
- 控制端通过同一 ID 上传严格单 App ZIP，目标端校验 SHA-256、bundle ID、Developer ID 签名和 Gatekeeper 后，覆盖安装并启动 `KEMI远程办公 1.4.125+241`；目标保留应用且 2 个 KEMI 相关进程持续运行。
- 安装后的目标 App 再次执行 `codesign --verify --deep --strict` 与 `spctl -a -t exec` 均通过；应用清单、最近 300 秒统一日志、崩溃报告索引和当前截图均能通过仿真通道读取。
- 完整覆盖安装闭环 `manual_real_harness_simulator_app_deploy_test.dart` 通过，截图 SHA-256 为 `bbb46e0f97574cd446e2c7f2f4a3c55aec551963e59ff908d46e40543cbab0a3`。
- macOS 部署 ZIP 必须只有一个 ASCII 名称的顶层 `.app`；不能使用会产生 `__MACOSX` 资源分叉目录的封装参数，否则安全安装器会按设计拒绝多顶层内容。该负例已真实触发并保留为回归断言。
- KEMI 进程探测使用稳定 ASCII 关键字 `KEMI`，不依赖中文可执行文件名在远程 `ps` 输出中的编码表现。

本轮新增的实机自动化为：

- `test/manual_real_harness_simulator_screenshot_test.dart`
- `test/manual_real_harness_simulator_app_deploy_test.dart`
- `test/manual_real_harness_simulator_app_probe_test.dart`
- `test/manual_real_harness_simulator_app_center_test.dart`

其中应用中心页面已在同一份 `1.4.125+241` 二进制上真实点击并加载 macOS 应用列表；目标机上的点击还受目标 macOS 辅助功能权限约束，`osascript` 明确返回 `-1719`。这不影响独立的 VibeKits MCP/SSH/文件/安装/日志/截图仿真能力，但目标 UI 输入自动化不能据此记为通过。

## 尚未完成的发布门禁

1. 远程协助首次证书批准后的真实项目、会话、历史、发送、增量反馈、停止和断开闭环；自动测试不能替代双机证据。
2. PAD 63 当前 `192.168.3.63:5555` 拒绝连接，尚未安装同协议候选；75 在线但现装 dev.188 使用 AOSP 平台证书 `C8:A2:E9:...:2A:B8`，dev.209 临时构建使用本机 debug 证书，Android 正确以 `INSTALL_FAILED_UPDATE_INCOMPATIBLE` 拒绝覆盖。不得以卸载清数据绕过，需取得同一平台签名或恢复 63 环境。
3. Windows 58 同步 dev.209、D 盘 Release 构建、真实启动及截图/下载的同形协议验收。
4. 目标 macOS UI 输入自动化需目标系统另行授予辅助功能；当前仅完成无输入接管的截图、日志、安装与进程闭环。
5. 本候选尚未执行 Apple 公证、staple 与 Gatekeeper 验收，也未上传 KEMI 商场。上述门禁未完成前不得称为正式发布版。
