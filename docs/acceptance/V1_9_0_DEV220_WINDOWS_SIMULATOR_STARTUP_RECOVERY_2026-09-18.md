# dev.220 Windows 更新后远程仿真启动恢复验收

## 1. 结论

Windows `1.9.0-dev.220+2220` 更新后出现的“远程仿真开关打不开”已经定位并修复。根因不是密码、MCP 端口或 Flutter 开关状态，而是旧版 `vibekits-harness-relay.exe` 仍作为脱离主进程的单实例服务运行，占用了 `VibekitsHarness` 原生 IPC 命名空间。新版 APP 能找到包内 Relay，却无法让这个旧服务响应控制命令，最终在 5 秒后报：

```text
TimeoutException after 0:00:05.000000: Harness native control command timed out
```

修复提交 `e376a5e` 为 Windows 增加了受限的旧 Relay 接管流程。真实启动旧 dev.211 Relay 后再运行 dev.220，新版能够自动终止无响应的旧单实例、启动当前包内 Relay、恢复持久化的远程仿真开关，并取得服务端确认 ID。用户不再需要到任务管理器结束旧进程，也不需要反复点击开关。

本报告只确认“Windows 更新后的目标端启动与旧 Relay 接管”已经完成。两个不同 routing ID 的真实 P2P 与强制 HBBR 双机连接仍必须单独验收；HBBS 不会把同一个注册身份路由给自身，因此本机连接自己的 ID 超时不能替代双机结论。

## 2. 现场现象

现场运行版本为 `1.9.0-dev.220+2220`。高级设置中远程仿真保持关闭，打开后回落并显示原生控制命令超时。系统中同时存在一个来自历史开发目录的旧服务：

```text
D:\KEMI-Test\work\vibekits-dev211\build\windows\x64\runner\Release\vibekits-harness-relay.exe
  --vibekits-harness-service
```

新版包内服务位于：

```text
D:\vibecode\vibekits\.worktrees\remote-simulator-latest\build\windows\x64\runner\Release\vibekits-harness-relay.exe
```

旧服务虽然仍占用单实例 IPC，但已经不能正确响应新版 `--vibekits-harness-stop` 控制命令。Windows 的单实例行为又使新版第二次启动服务成为无效操作，所以 UI 看到的是“服务存在但控制不可用”，不是普通的“进程不存在”。

## 3. 更新前算法为什么失败

更新前 `RustDeskHarnessShareService.ensureHostAvailable` 的接管顺序是：

1. 检查包内 Relay 与当前原生服务状态；
2. 如果服务不可调用，尝试启动当前包内 Relay；
3. 再次检查仍不可调用时，向已占用 IPC 的服务发送 `--vibekits-harness-stop`；
4. 只有旧服务正常返回 `{\"ok\":true}` 才重新启动当前版本；
5. 旧服务无响应时，5 秒超时直接终止接管并让开关进入错误状态。

这个算法只覆盖“旧服务仍理解新版停止命令”的升级路径，没有覆盖以下真实场景：旧进程仍活着、单实例锁仍存在、状态 IPC 不兼容或卡死、停止命令也无法返回。结果是 APP 每次重试都会回到同一个超时点。

## 4. 修复算法

`lib/features/dev_tools/domain/rustdesk_harness_share_service.dart` 现在执行以下有界接管：

1. 先执行正常的 `--vibekits-harness-stop`，保留兼容版本的优雅退出；
2. 如果停止命令超时、异常或返回非成功状态，仅在 Windows 启用残留进程处理；
3. 先校验目标可执行文件的精确文件名必须为 `vibekits-harness-relay.exe`，拒绝对任意进程名执行终止；
4. 使用参数数组直接运行 `taskkill.exe /F /IM vibekits-harness-relay.exe`，不经过 shell、不使用通配路径；
5. 强制退出后等待 250 ms，让 Windows 释放单实例 IPC 命名空间；
6. 启动当前 APP 包内 Relay，并在限定时间内轮询 `callable`、HBBS 在线和注册密钥确认状态；
7. 仍失败时保留原始 graceful-stop 错误，输出可诊断的 `HARNESS_RELAY_NOT_CALLABLE_AFTER_TAKEOVER`，不把失败伪报成成功。

该处理只针对 VibeKits 自带的独立 Relay 文件名，不终止 RustDesk、KEMI 远程办公、SSH、Harness/Node 或其他用户进程。

## 5. 自动化与真实复现

新增回归用例：

```text
旧单实例控制命令超时后会终止残留 relay 并接管
```

用例模拟停止控制命令超时，验证残留终止器被调用、当前 Relay 被重新启动、最终主机状态为 `callable=true`。相关远程仿真目标与 Relay 组合测试结果为 `32/32` 通过。

真实回归不是只跑 Mock：

1. 主动启动 dev.211 历史目录中的旧 Relay；
2. 启动重新构建的 dev.220 Windows Release；
3. 等待持久化的远程仿真授权自动恢复；
4. 确认旧 dev.211 Relay 已退出；
5. 确认运行中的服务已切换为 dev.220 包内 Relay；
6. 确认 UI 显示“远程仿真已开启”；
7. 确认 Windows Release 构建成功。

修复后的现场只读状态为：

```json
{"routingId":"4567540178","callable":true,"rendezvousOnline":true,"registrationKeyConfirmed":true,"state":"registered"}
```

目标端固定回环服务同时正常监听：

```text
127.0.0.1:32147  MCP 工具端点
127.0.0.1:32148  SSH 公钥自动引导控制端点
0.0.0.0/[::]:22 Windows OpenSSH
```

## 6. 远程仿真与远程协同必须分开

本次诊断中曾错误地把远程协同的密码配对流程用于解释远程仿真失败。该判断已经撤销，后续实现、文档与现场判断必须遵守以下边界：

| 项目 | 远程仿真 | 远程协同 |
| --- | --- | --- |
| 用户入口 | 输入设备 ID 后点击“仿真” | 输入设备 ID 后点击“协同” |
| 密码 | 不需要 | 首次配对可使用协同密码证明 |
| APP 层配对 | 不走 `HarnessRemotePairingClient` | 走配对、证书固定和授权范围 |
| 目标端控制 | `HarnessSimulatorTargetRuntime` | `HarnessRemotePairingHost` / 远程会话 |
| 固定端点 | `32147` MCP、`32148` 控制、`22` SSH | `32145` 配对及远程协同会话端点 |
| 身份边界 | 已开启仿真 gate 的原生 Relay 调用方 ID | 密码证明、证书与本机批准 |

因此，不得要求远程仿真调用方输入 `12345678`，也不得以“没有出现协同审批卡片”判断远程仿真失败。远程仿真的正确调用入口是 MCP 工具：

```json
{"tool":"vibekits.simulator.connect","arguments":{"routingId":"<6-16 位设备 ID>"}}
```

成功结果必须包含 `connected:true`、请求的 routing ID、已验证设备身份以及 `transport:p2p_or_relay`；只看到目标端 `registered` 不等于双机工具通道已经连接。

## 7. Windows 防火墙结论

Windows 首次启动新路径下的 Relay 可能再次弹出 Defender 网络提示，因为每个构建目录对应不同程序路径。现场还发现过同一路径的入站 Block 规则，并已改为当前专用网络的 Allow 规则。这会影响 Windows 对入站网络程序的处理，但不是远程仿真的密码门禁，也不是旧 Relay 单实例超时的根因。

防火墙诊断必须分别记录：当前网络类别、精确程序路径、规则方向、Allow/Block 动作和 Relay 自检状态。不能因为用户点过一次提示就假定所有历史路径规则都已消失，也不能因为 `rendezvousOnline=true` 就宣称设备间传输已经成功。

## 8. 自连探针与双机门禁

对本机 ID `4567540178` 发起强制中继探针时，本地隧道能够进入 `listener_ready`，随后返回：

```json
{"code":"transport_connect_timeout","message":"Harness remote transport did not become connected","ok":false}
```

同时目标端连接列表保持：

```json
{"ok":true,"state":"idle","connections":[]}
```

这与既有验收结论一致：HBBS 不把同一注册身份路由给自身。该结果只证明控制端本地监听与超时反馈正常，不能证明真实对端失败。最终完成条件仍是使用两个不同 routing ID，分别验证默认 P2P/自动回退和显式 HBBR，并通过 MCP 目录、SSH 公钥自动引导、文件往返及断开回收。

## 9. 提交与发布状态

- `0bef733 fix(windows): stabilize simulator release packaging`：修复 Windows 自包含打包和构建稳定性；
- `e376a5e fix(windows): take over stale simulator relay`：修复旧单实例 Relay 无响应时的自动接管；
- Windows Release：构建通过；
- 定向回归：`32/32` 通过；
- 双机不同 ID 真实闭环：仍是发布前硬门禁，不以本机自连或 `registered` 状态代替。

