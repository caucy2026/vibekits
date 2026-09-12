# VibeKits dev.188 Windows 58 编译与验收交接

## 输入与边界

- VibeKits 版本：`1.9.0-dev.188+2188`。
- VibeKits 源码必须在 58 的 `D:\KEMI-Test\work` 下。
- RustDesk transport 使用备份仓库 commit `6ce56ab0b`，必须包含 `vibekits-harness-relay` bin 和 `src\vibekits_harness_relay.rs`，同样放在 D 盘；不得依赖已安装 RustDesk/KEMI远程办公程序。
- 使用 58 现有 `D:\KEMI-Test\tools` 中的 Rust、Cargo、vcpkg、LLVM 与 VS Build Tools。构建、缓存、临时文件和候选包都留在 D 盘。

## 一次执行顺序

在 VibeKits 仓库根目录打开 PowerShell：

```powershell
$env:VIBEKITS_RUSTDESK_SOURCE = 'D:\KEMI-Test\work\RustDesk\client'
git -C $env:VIBEKITS_RUSTDESK_SOURCE checkout 6ce56ab0b
git -C "$env:VIBEKITS_RUSTDESK_SOURCE\libs\hbb_common" apply --check "$env:VIBEKITS_RUSTDESK_SOURCE\kemi-docs\patches\hbb-common-worktree-20260909.patch"
git -C "$env:VIBEKITS_RUSTDESK_SOURCE\libs\hbb_common" apply "$env:VIBEKITS_RUSTDESK_SOURCE\kemi-docs\patches\hbb-common-worktree-20260909.patch"
.\tool\prepare_rustdesk_harness_relay_windows.ps1
flutter pub get
flutter analyze --no-pub
flutter test --no-pub test\harness_message_queue_test.dart test\platform_storage_layout_test.dart test\harness_conversation_ux_contract_test.dart test\windows_relay_build_contract_test.dart
.\tool\prepare_harness_runtime.ps1 -NodeDirectory (Split-Path (Get-Command node).Source)
.\tool\prepare_git_runtime.ps1
.\tool\prepare_github_cli_runtime.ps1
.\tool\prepare_mihomo_runtime.ps1
.\tool\prepare_qemu_runtime.ps1
flutter build windows --release --no-pub
.\tool\verify_windows_bundle.ps1 -Configuration Release -ExpectedVersion '1.9.0-dev.188+2188'
```

任一步失败即停止，禁止复制历史 helper 或历史 Release 冒充本轮产物。

## 真机验收

1. 把 `build\windows\x64\runner\Release` 完整复制到新的 D 盘隔离目录，连续冷启动三次；不得依赖源码目录、PATH Node/Git/ADB/RustDesk。
2. 设置 `VIBEKITS_DATA_HOME=D:\VibekitsData`，确认 Harness、queue、Mcp 和 debug 均落到该根，C 盘不出现第二套大目录。
3. 启动一个至少 60 秒的 Harness 任务；运行中输入、选择“排队下一条”两次、编辑/上下移动/删除第二项。当前任务结束后第一项只发送一次。
4. 在 dispatching 阶段结束 APP 后重启，确认未接受项恢复，已接受项不重复。
5. 进入工具审批等待，确认队列不抢跑；分别验证完成、失败、取消、断网恢复。
6. 检查 `vibekits-harness-relay.exe --vibekits-harness-status` 返回 JSON；再按真实 routing ID 完成一轮 P2P/HBBR 连接和 Harness 状态传输。
7. 记录 Release 目录 SHA-256、运行截图、日志路径、Windows 版本和每项结论到新的验收文档。全绿后才能交付或发布。

## 2026-09-12 本机交接前复核

- VibeKits 源码提交：`17c8c2e14fdc6dc00d17fa7b7227a0b35544c592`；RustDesk relay 源码提交：`6ce56ab0b37c94f0e4cbfb983cff5d69d244b707`。
- 远程协助/仿真共用逻辑定向回归共 `89/89` 通过，覆盖默认密码、首次证书批准、错误密码拒绝、证书固定、P2P/强制中继选择、mTLS、项目/会话快照、命令回执、独立停止、断线恢复、撤权、PAD 仅控制端以及固定仿真端点生命周期。
- 远程协助相关 Dart 源码静态分析：`No issues found`。
- 本机补入临时 CMake 3.30 并指向仓库自带 `vcpkg` 后，Rust relay 二进制完成编译/链接；库模块内四个 relay 单测 `4/4` 通过。RustDesk 上游仍产生既有 warning，但没有 relay 错误。该结果只证明 macOS arm64 开发构建，58 仍必须使用本节既定 D 盘工具链重新执行 Windows Rust 测试和 Release 构建，不能沿用本机 helper 代替。
- 当前源码 helper 完成真实本机服务生命周期：启动后独立 ID `1554650784` 返回 `callable=true`、`rendezvousOnline=true`、`registrationKeyConfirmed=true`、`state=registered`；无会话时连接控制返回 `idle`；显式停止返回 `stopped` 且服务进程退出。随后已恢复原 Release helper，并再次确认相同独立 ID 为 `registered/callable`。这证明本机 HBBS 注册、状态 IPC 与停止生命周期，不代表远端 P2P/HBBR 业务会话已通过。
- 本机 ADB 预检只发现 `192.168.3.75:5555` 在线；`192.168.3.63:5555` 当前不可达。因此 63 真机远程闭环仍是未通过门禁，不得由上述 89 项自动测试替代。
- 对此前授权目标 ID `4456560334` 分别执行自动 P2P/回退和强制 HBBR 到固定仿真端点 `127.0.0.1:32147`，两轮都先正确报告 `listener_ready`，随后在 45 秒返回 `transport_connect_timeout`；失败后本机 relay 仍为 `registered/callable`。这说明失败没有污染本机服务，但当前目标未形成可用数据面，不能复用 2026-09-11 的历史成功证据替代本轮双机验收。

58 在完整构建前还应执行远程共用逻辑回归：

```powershell
flutter test --no-pub --concurrency=1 `
  test\harness_remote_access_settings_test.dart `
  test\harness_remote_adapter_test.dart `
  test\harness_remote_commands_test.dart `
  test\harness_remote_controller_session_test.dart `
  test\harness_remote_host_test.dart `
  test\harness_remote_ledger_test.dart `
  test\harness_remote_link_state_test.dart `
  test\harness_remote_pairing_service_test.dart `
  test\harness_remote_pairing_test.dart `
  test\harness_remote_peer_store_test.dart `
  test\harness_remote_read_only_panel_test.dart `
  test\harness_remote_routing_identity_test.dart `
  test\harness_remote_share_dialog_test.dart `
  test\harness_remote_sync_test.dart `
  test\harness_remote_view_model_test.dart `
  test\harness_simulator_access_settings_test.dart `
  test\harness_simulator_controller_test.dart `
  test\harness_simulator_target_runtime_test.dart `
  test\rustdesk_harness_link_status_test.dart `
  test\rustdesk_harness_share_service_test.dart
```

该命令通过只证明跨平台 Flutter 协议与状态逻辑一致；Windows helper 打包、真实 ID 直连、强制 HBBR、项目/会话/命令/反馈/停止及断线重连仍必须在真机分别验收。
