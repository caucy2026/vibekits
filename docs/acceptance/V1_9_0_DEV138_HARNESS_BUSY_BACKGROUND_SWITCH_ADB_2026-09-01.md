# VibeKits v1.9.0-dev.138 Harness 稳定性验收报告

日期：2026-09-01  
版本：`v1.9.0-dev.138+2138`  
范围：macOS Release、Harness 项目状态、后台项目切换、内置 ADB

## 1. 本轮问题与结论

### 1.1 ADB 工具存在但正式 App 调用失败

根因不是 63 设备或 TCP 连接，而是上一版 macOS App 没有把 Android SDK Platform-Tools 的 `adb` 打进约定目录。能力检查此前只看 Dart handler，因此还会错误显示“工具存在”。

本轮基线继承并复验以下修复：

- Release 必须包含 `Contents/MacOS/tools/adb/adb`，找不到正式 runtime 时构建失败；
- 能力检查同时校验 handler 和实际 runtime，缺包写入 `missingRuntimes`；
- 多属性 `getprop` 自动拆成多次只读调用，并返回结构化 `properties`；
- 真实目标 `192.168.3.63:5555` 可读取 Android 12 / SDK 31 / arm64-v8a 与两块 1920×1280 Display。

### 1.2 Harness 正在推理却上报 READY

根因是每个工具调用结束时，工具桥都会把全局 phase 改回 `ready`，但智能体此时仍会继续分析下一步。RustDesk 因而收到蓝灯和 BUSY=0。

修复后的状态合同：

- 任务启动、规划、推理、工具执行和工具结果后的继续分析均保持 busy；
- 工具执行中为 `toolRunning`；
- 工具成功或失败后，只要外层 Harness agent 尚未退出，就回到 `reasoning`；
- 只有 agent 真正退出或用户停止后才回到 `ready`；真实失败才为 `failed`；
- 协议仍为 `vibekits.harness.status/v1`，没有新增 RustDesk 兼容负担。

### 1.3 任务运行时无法查看其他项目

根因是项目与会话点击处理器被全局 `_running` 锁禁用，且运行输出直接绑定当前页面的 `_messages`。

修复后：

- 一个项目运行任务时，可以点击并查看其他项目和会话；
- 原项目任务继续运行，不因页面切换停止；
- 流式输出写入原工作区、原 session 的独立后台缓冲和持久化记录；
- 切回原会话可看到完整输出，其他会话不会串入内容；
- 为避免并行状态冲突，同一 VibeKits 窗口仍只允许一个主动 Harness 任务，新建、移动和再次发送在任务结束前保持受控。

## 2. 回归门禁

必须通过以下自动化：

1. 编排工具从 `toolRunning` 返回 `reasoning`，且 `busy=true`；
2. 运行中切到第二项目，第二项目内容可见、停止按钮仍能控制后台任务；
3. 后台输出不出现在第二项目，完成后回到第一项目可见；
4. 完成后 phase 恢复 `ready`；
5. Harness、ADB、状态 IPC 相关完整测试与 Flutter analyze 通过；
6. macOS Release 构建、深度签名、正式 `bin/Vibekits.app` 运行通过；
7. App 内置 ADB 对 63 只读验收再次通过。

## 3. 安全边界

- 切换项目仅改变本地浏览上下文，不扩大后台任务原有工作区权限；
- 运行任务继续绑定启动时的 workspace/session，不能把结果写到后来查看的项目；
- 本地 ADB 验收不把局域网地址或设备诊断发送给外部模型；若要求 DeepSeek 自主重跑包含这些数据的任务，仍需用户明确同意该次外部传输。

## 4. 实际执行结果

- Harness/状态 IPC/ADB 定向回归：`81` 通过、`1` 个既有平台条件跳过、`0` 失败。
- LMCP 暴露与“提供方先启动、观察者后启动”局域网发现：`17/17` 通过。
- Flutter analyze：`No issues found`。
- macOS Release：构建成功，产物约 `613.0 MB`；深度严格签名验证通过。
- App 版本：`CFBundleShortVersionString=1.9.0.138`，`CFBundleVersion=2138`。
- 正式 App：`bin/Vibekits.app`，运行 PID `8450`，Harness IPC socket 正常监听。
- 正式 hello→getSnapshot：`publisherVersion=1.9.0-dev.138`，真实项目为“测试1/idle、测试2/idle、harness/ready”，`busyCount=0` 符合当时没有任务运行的现场状态。
- App executable SHA-256：`d5f5bf89177a2c2ad90d423786285d87c4fe58b1c16f6a2b05ead4110c60e067`。
- 内置 Universal ADB SHA-256：`8c2672e2a9aa6ab6efec787195a54451b66f3a3043c4f27d1ef67f7b339e6970`。
- 新 App 内置 ADB 对 `192.168.3.63:5555` 的真实只读验收：`1/1` 通过。

全仓库无筛选并行测试还暴露 `27` 个既有环境/隔离失败（当前 Mac 缺 Git/Windows Node 等测试 runtime，以及部分依赖全局单例或平台 UI 的测试在全并发运行时互相污染）；本轮相关测试单独和组合运行均通过。上述失败没有被隐藏，也不计入本轮功能通过数，后续应单独治理全仓测试隔离。
