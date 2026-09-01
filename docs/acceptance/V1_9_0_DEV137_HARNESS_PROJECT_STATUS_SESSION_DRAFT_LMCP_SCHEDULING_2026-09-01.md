# VibeKits Harness 项目状态、会话草稿与 LMCP 调度验收报告

日期：2026-09-01  
版本：`v1.9.0-dev.137+2137`  
正式 App：`bin/Vibekits.app`

## 1. 本轮验收范围

1. Harness 每个会话拥有独立的未发送输入草稿；切换会话后恢复各自内容。
2. `vibekits.harness.status/v1` 发布真实 VibeKits 项目列表与项目状态，不混入 Codex、VS Code。
3. LMCP 单一标准补齐“指挥官—作战单位”架构、实时负载、容量租约、评分调度、故障转移、幂等与物理结果验真。
4. LAN 发现并发启动必须只绑定一个 UDP socket，避免主线程空转和公告丢失。

## 2. 自动化验证

- 定向测试：`flutter test test/deepseek_harness_test.dart test/harness_work_status_test.dart test/lan_peer_discovery_service_test.dart`
- 结果：`39/39` 通过。
- 会话草稿用例：会话一输入 `111`，切换会话二确认空草稿；输入 `222` 后切回会话一得到 `111`，再切回会话二得到 `222`。
- LAN 回归用例：同一服务两个并发 `start()` 只执行一次 UDP bind；提供方先启动、观察方后启动仍能在周期公告窗口内发现。
- 静态分析：`flutter analyze`，结果 `No issues found`。
- 差异检查：`git diff --check` 通过。

## 3. Release 与真实运行验证

- 构建：`flutter build macos --release` 成功，产物约 `593.0 MB`。
- 签名：ad-hoc 深度签名；`codesign --verify --deep --strict` 通过。
- 正式运行 PID：`89501`（验收时）。
- App AOT SHA-256：`4574ba241a39fdc33bd5693ea050398bbecbcc662c446154bec302e31d71ff4f`。
- UDP 47831：VibeKits 进程仅保留一个监听 socket；KEMI 传书共享端口不影响本进程单实例约束。
- 旧 App 可恢复备份：`/private/tmp/Vibekits-before-project-status-drafts-20260901.app`。

## 4. 真实 Harness IPC 快照

通过正式 `${systemTemp}/vkh/v1.sock` 完成 `hello -> getSnapshot`：

```text
publisherVersion = 1.9.0-dev.137
streamSequence = 3
aggregate = taskCount:3, busyCount:0, waitingApprovalCount:0, failedCount:0

测试1   idle   workspace-inventory/workspace-status
测试2   idle   workspace-inventory/workspace-status
harness ready  workspace-inventory/workspace-status
```

`workspaceRef` 为路径哈希后的稳定公开引用；快照不包含原始绝对路径、Codex 或 VS Code 任务。RustDesk 无需新增协议字段，可直接按既有 `workspaceLabel/phase/taskId` 渲染。

## 5. 实现结论

- macOS 正式 `DeepSeekAgentWorkspace` 已接入真实项目目录，不再只有 Windows Official Harness 页面发布项目状态。
- 当前项目使用 `ready`，其他已登记项目使用 `idle`；任务执行时同一项目行进入 `reasoning/toolRunning/completed/failed/stopped` 生命周期。
- 草稿按 `workspace + sessionId` 隔离；发送只清空当前会话草稿，切换项目和会话前先保存当前草稿。
- LMCP 调度标准见 `docs/50_LMCP_APP_DEVICE_IDENTITY_AND_SWITCH_STANDARD.md` 6.9：作战单位必须公开实时容量，并通过原子租约参与多指挥官调度；不能只靠“在线”或历史评分决定调用。

## 6. 验收边界

本机自动化界面动作管道在尝试正式 App 鼠标输入时发生 `native pipe closed before response`，因此 111/222 的交互以 Flutter 真实 Widget 测试完成，不伪造人工点击截图。正式 App 的启动、项目 UI、IPC 快照、UDP socket、签名和 AOT 均已在生产进程上独立核验。
