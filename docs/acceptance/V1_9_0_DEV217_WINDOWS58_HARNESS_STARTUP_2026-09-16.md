# dev.217 Windows 58 Harness 启动验证（2026-09-16）

## 范围与版本

- 源码：`1.9.0-dev.217+2217`，本机工作树快照；测试源码置于 Windows 58 的 `D:\KEMI-Test\work\vibekits-dev217-input-test`，没有覆盖当前安装。
- 构建产物：`D:\KEMI-Test\work\vibekits-dev217-input-test\build\windows\x64\runner\Release\vibekits.exe`。
- 便于人工桌面验收的未签名测试包：`dist/Vibekits-1.9.0-dev.217+2217-windows-x64-TEST.zip`，SHA-256 `08ba8bf360f62ad75557a9eaa95efd55416b15ce7578e05a2a31850d4944cb1e`；Mac 端校验哈希相同且 ZIP 解压检查无错误。
- 官方 Harness 运行时：`@deepseek-ai/dsh@0.1.5-rc.2`。

## 真实结果

1. Windows x64 Release 编译成功。`tool\verify_windows_bundle.ps1 -Configuration Release -ExpectedVersion '1.9.0-dev.217+2217'` 通过，确认包内 45 项必需运行时。
2. 独立 Node 启动检查通过：Harness `web --no-open` 成功绑定回环端口。
3. 应用接线检查通过：`test/manual_windows_harness_startup_test.dart` 调用 `DeepSeekHarnessService.startWebAgent`，从构建包内定位运行时，等待浏览器令牌与回环端口就绪，再关闭进程。Windows 58 实跑通过。
4. 同机执行 `deepseek_harness_test.dart`、`harness_agent_integration_test.dart`、`harness_webview_input_gate_test.dart`、`harness_conversation_ux_contract_test.dart`、`harness_simulator_controller_test.dart` 加启动测试，共 44 项通过。集成测试含本地模型端点上的真实任务和长任务停止/进程清理。
5. 2026-09-17 从新包 `vibekits.exe` 在 SSH 会话 0 短暂启动进程 PID 7464；15 秒后仍在运行，内存约 83 MB。只停止此测试 PID；原有桌面会话 1 的 VibeKits PID 12252 未被停止或覆盖。此检查仅证明可执行程序在非交互会话能保持运行，不等于用户桌面可见启动。

## 构建时发现的输入缺口

初次构建的源码快照没有 Git 忽略的 WinDivert、7-Zip、RustDesk relay 等 Windows 运行时，分别造成 C++ 编译或 CMake 安装失败。这不是 Harness 运行时崩溃。测试构建只在隔离目录复用 Windows 58 上此前成功构建的固定运行时；relay 复制前核对了清单 SHA-256，没有改动当前安装。正式发布应重新执行各运行时的项目准备脚本并验证来源，不得直接把此测试候选当成正式包。

## 未通过的验收

- Windows 58 当前交互桌面未发现可用的受控桌面测试代理；SSH 会话不能代表用户桌面。因此实际点击 Harness、输入中文、并行会话和关闭/重启应用的可见 UI 尚未验收，不能宣称当前安装的启动问题已彻底修复。
- Windows 58 的仿真 ID `8296293831` 当前查询为 `connected=false`。经该 ID 执行 PowerShell 脚本、传文件以及 KEMI Send 签名尚未通过；不能以直连 SSH 或直接运行 PowerShell 代替按 ID 仿真验收。
- 本测试候选未签名、未安装覆盖当前版本、未发布。
