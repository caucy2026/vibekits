# Windows dev228 Harness 验收记录（2026-09-23）

候选：`1.9.0-dev.228+2228`，在 58（`4567540178`，`LAPTOP-LUOPP1CH`）的独立工作区 `D:\KEMI-Test\source\vibekits-9a6ed30-dev228-win-20260923` 构建。共享源码基线为 `9a6ed3045c144c93c406d8fdc00963510a6cf80d`，叠加本次改动，未覆盖已安装程序。

- 侧栏数字 1–7 已移除；内置 Harness 默认端口为 13080；会话删除与派生会话采用与 macOS 相同的共享实现。远程 Harness 接口已在工具目录公开。
- Windows Release 构建成功。项目 `tool/verify_windows_bundle.ps1 -SkipLiveRelayProbe` 验证通过：`pubspec.yaml`、Dart `AppVersion`、EXE 资源和 `data/app.so` 均为 dev228/2228，39 项必需运行时存在。这一门禁专门阻止上次 EXE 为 2227 而 `app.so` 仍为 2225 的错误。
- 58 的登录桌面 Session 1 启动了该 Release EXE：第二轮 PID 6428、窗口句柄 5835426、进程路径指向上述工作区，20 秒及 45 秒时均未退出。验收任务 `exit.txt=0`、`done.txt=2026-09-23T17:42:55+08:00`，已自动恢复原版 dev226。
- 远程调用 `vibekits.harness.session_prompt` 和 `session_status` 均返回 `HARNESS_WORKSPACE_UNAVAILABLE`。现有证据说明未注册当前官方 Harness 会话，尚不能证明远程接口可用。已修正适配器暂未就绪时远程消息可排队的问题，但这不解决未选中会话本身。
- 58 重新打开原版并选中 Harness 后，`session_status` 仍返回 `HARNESS_WORKSPACE_UNAVAILABLE`。登录用户的 `app-crash.log` 在旧版每次 Harness 启动时记录 `MissingPluginException(setHarnessShortcutsEnabled, vibekits/harness_input)`；该原生通道只在 macOS 实现。已在共享源码中将启停调用限制为 macOS，且纳入第三轮 dev228 构建。第三轮在 Session 1 启动，PID 37336、窗口句柄 34867350；源码清单、EXE 资源和新生成的 `app.so` 都核对为 dev228/2228。第三轮没有新增该 `MissingPluginException`，但 `session_status` 仍返回 `HARNESS_WORKSPACE_UNAVAILABLE`，因此它不是唯一原因。
- 当前会话注册依赖 WebView 发送一次 `vibekits.sessionSelection`。第三轮已核实 `exit.txt=0`、`done.txt=2026-09-23T18:29:35+08:00`，dev226 已恢复。曾尝试在页面脚本注入后直接读取官方持久化会话选择；第四轮在 58 重新构建，源文件 SHA256 `eeed790259cec32bc4a02a2496277018bccbe3bc07f322c85a0038eb079f1884`，新 `app.so` 修改于 19:13:10，EXE 与 AOT 版本同为 dev228/2228；Session 1 启动 PID 7372、窗口句柄 6097658，但 `session_status` 仍为 `HARNESS_WORKSPACE_UNAVAILABLE`。远端工具桥 PID 7372 和 relay 都指向 dev228 构建路径，故不是旧版进程接管。该未奏效的补偿已从共享源码撤回；**58 上第四轮构建仍包含它，不可作为发布包**。第四轮最终回滚文件尚未读取，随后 SSH 仿真通道返回连接重置。
- `test/harness_message_queue_test.dart` 与 `test/harness_tool_bridge_test.dart` 共 45 项通过，涵盖远程消息在 Harness 就绪后自动派发。会话删除和派生会话的相关 Mac 桌面回归此前已通过；Windows 真机交互仍待验证。

结论：**BLOCK，不签名、不发布。** 需仿真通道恢复后核实第四轮回滚状态，并在候选版界面实际选中会话时检查远程接口；如仍失败，记录 WebView 注入及会话选择的精确运行状态后修复。Windows 删除/派生会话交互及第二台机器兼容性尚未验收。
