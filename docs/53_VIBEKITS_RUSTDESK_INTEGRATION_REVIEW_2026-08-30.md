# Vibekits × RustDesk 联调验收报告（2026-08-30）

状态：macOS 源码、构建、本机 IPC 和错误路径已通过；真实远端 peer/ADB 与双端 UI 仍需外部设备验收。

## 1. 交付能力

### 远端 ADB

- Vibekits 可用当前 RustDesk App executable 调用 `open/status/heartbeat/close`。
- RustDesk 只复用已认证的 `DEFAULT_CONN`，远端目标固定为 `127.0.0.1:5037`，本地返回动态 `127.0.0.1:<port>`。
- Vibekits 所有 ADB 调用统一在命令最前添加 `-H 127.0.0.1 -P <port>`；交互工作区与 Harness ADB 工具共享当前 endpoint。
- lease 每 10 秒 heartbeat，RustDesk TTL 45 秒；切换来源、dispose、远控断线或 connection round 改变时清理。
- CLI 成功 envelope 固定 `schemaVersion=1` 且 `operation` 精确；错误消息 Unicode 安全、有界并对凭据标记整条脱敏。

### Harness 状态

- Vibekits 维护多任务 registry、全局 stream sequence、单任务 revision 和合法阶段转换。
- 公开快照不包含提示词、思维链、正文、完整路径/命令/URL、凭据、日志或堆栈；单任务和整机快照均有限长。
- macOS/Linux 本机 IPC 固定 `${Directory.systemTemp.path}/vkh/v1.sock`，父目录 `0700`、socket `0600`、同 UID；不降级 TCP。
- 协议为 4-byte big-endian 长度 + UTF-8 JSON，最大 32 KiB，支持 hello/nonce/version、snapshot、subscribe、heartbeat、resync、unsubscribe 和 latest-wins。
- RustDesk 仅在已认证 Remote、独立 `view_harness_status` 权限和明确远端订阅同时满足时转发；P2P 顶层字段固定 33/34/35/36。

## 2. Vibekits 关键代码

- `lib/features/dev_tools/domain/adb_server_endpoint.dart`
- `lib/features/dev_tools/domain/rustdesk_adb_tunnel_client.dart`
- `lib/features/dev_tools/domain/adb_service.dart`
- `lib/features/dev_tools/domain/harness_tool_bridge.dart`
- `lib/features/dev_tools/presentation/adb_workspace.dart`
- `lib/features/dev_tools/domain/harness_work_status.dart`
- `lib/features/dev_tools/domain/harness_status_ipc_protocol.dart`
- `lib/features/dev_tools/domain/harness_status_ipc_transport.dart`
- `lib/features/dev_tools/domain/harness_status_ipc_publisher.dart`
- `lib/app/app.dart`

`macos/Runner/AppDelegate.swift` 还修正了 FlutterAppDelegate 上不存在的 super selector 调用；修正前 App 在 Dart 初始化前因 `unrecognized selector applicationDidFinishLaunching:` 退出。

## 3. 当前构建与真实本机验证

- 已同步到 Vibekits 云端基线 `23b6da4`，保留该基线新增的 LMCP/飞书能力并完成重放合并。
- Flutter：`3.47.0`；Dart：`3.13`。
- `flutter analyze --no-pub`：0 issue。
- Harness/ADB 核心定向测试：42/42；新增的两条 Harness 远端 ADB endpoint 用例分别通过。
- macOS Release 构建成功：`build/macos/Build/Products/Release/Vibekits.app`，约 135.5 MB。
- Release App 已实际启动，界面显示 `v1.9.0-dev.137+2137`、系统就绪。
- 正式 socket 实际解析为 `/var/folders/rz/9rnd37v141l9hbwmd4j4l_1h0000gn/T/vkh/v1.sock`；实际权限为目录 `0700`、socket `0600`。
- 独立本机客户端已对 Release App 完成 `helloAck → subscribe → snapshot → unsubscribe`，nonce/protocol/version/schema 均匹配。
- RustDesk 独立复跑：Harness 11/11、ADB 8/8；完整 `cargo check --locked --features flutter --bin rustdesk` 通过。
- RustDesk 最终评估已同步回本机；最终 App executable SHA-256 为 `619a74833d972520dfecc2eb134570fcb6568b652da682f830bd0a8136504bc0`，内嵌 Rust dylib SHA-256 为 `7feaaaa2a5dc3f7f17dcbca3a825f0262972fa7aa962e35d342b1707bba48450`。

此前全仓串行测试用于识别基线问题，结果包含大量与本集成无关的既有平台/资产/旧 UI fixture 失败。最终定向门禁全部通过；例如 `harness_tool_bridge_test.dart` 的既有磁盘容量断言在当前 macOS 沙箱仍返回 0，该测试代码不在本轮改动范围，不能伪装成集成回归。

## 4. 不能伪称已完成的外部验收

1. 当前没有第二台运行兼容候选版本、且远端 `127.0.0.1:5037` 可用的已连接 RustDesk peer；因此尚不能真实执行 `devices/getprop/logcat/push/pull/install` 和断线清理验收。
2. 尚未在两端兼容版本上取得 RustDesk 远端 Harness 只读面板截图并验证 busy/idle/stale/disconnected。
3. 当前 macOS 包没有自包含 DSH/Node Harness 运行时。仓库文档已明确 macOS 自包含运行时尚未生成；Release UI 因而显示“内置 Harness 运行时缺失或损坏”。状态 publisher 本身可用，但 macOS 上真正启动 Harness 仍需单独完成运行时资产打包。
4. Windows 安全 Named Pipe Harness transport 尚未交付，当前明确 fail-closed；不得以 TCP 临时替代。

以上四项都是发布范围/外部环境门槛，不应由模拟测试替代。当前没有安装覆盖 `/Applications` 中正在使用的正式 App，也没有提交或推送代码。

## 5. 相关契约

- `docs/51_RUSTDESK_REMOTE_ADB_TUNNEL_REQUIREMENTS.md`
- `docs/52_HARNESS_RUNTIME_STATUS_IPC_AND_RUSTDESK_DELIVERY.md`
- RustDesk：`client/kemi-docs/VIBEKITS-RUSTDESK-INTEGRATION-REVIEW-2026-08-30.md`
