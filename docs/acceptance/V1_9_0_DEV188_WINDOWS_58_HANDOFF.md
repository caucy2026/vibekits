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
