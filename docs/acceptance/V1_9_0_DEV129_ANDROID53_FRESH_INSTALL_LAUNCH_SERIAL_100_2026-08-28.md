# v1.9.0-dev.129 Android 53 全新安装、启动与串口并行监控 100 轮验收

## 验收口径

本轮修正此前“`adb install -r` 覆盖安装”不符合现场要求的问题。每一轮必须完整执行：

1. `pm uninstall com.vibekits.vibekits`，并核对返回 `Success`。
2. 使用 APP 内置 ADB 全新安装 APK，不带 `-r`。
3. `am start -W -n com.vibekits.vibekits/.MainActivity` 启动 APP。
4. 使用 `pidof com.vibekits.vibekits` 确认新进程真实存活。
5. COM33 串口会话在 100 轮开始前打开，由独立 worker 持续读取；卸载、安装、启动三个阶段分别排空并保存增量数据。
6. 每轮比较 `/proc/sys/kernel/random/boot_id`，同时检查串口重启标记；发现重启立即停止后续轮次并保存串口尾部、2000 行 Logcat、`ps -A -T` 最后线程、Activity/Window/Package、pstore 和 dmesg 现场。

原始串口、Logcat 和故障现场只保存在本机，不上传给模型。正式调用由官方 DeepSeek Harness 在 UI 中真实发起一次聚合工具，不用外部脚本绕过智能体。

## 测试输入

| 项目 | 值 |
| --- | --- |
| Windows 控制端 | VibeKits `v1.9.0-dev.129+2129` Release |
| Harness 工具 | `mcp__vibekits-android-stress__android__apk_install_stress_100` |
| ADB 设备 | `192.168.3.53:5555` |
| Android 包 | `com.vibekits.vibekits` |
| 启动 Activity | `.MainActivity` |
| APK | `build/app/outputs/flutter-apk/app-release.apk` |
| APK 大小 | 115,541,133 B |
| APK SHA-256 | `56708518ABD89CFD3E461DF9B04F5A6FAF75A26CE60184825343041FC40060B1` |
| 串口 | COM33 / CH340 / 115200 / 8N1 / 无流控 |

## Harness 真实执行

正式提示只允许调用一次联合工具，Harness 轨迹显示：

```text
Tool call
mcp__vibekits-android-stress__android__apk_install_stress_100
```

工具调用持续约 21 分 17 秒，模型等待本地工作完成后返回汇总。正式测试前另做 1 轮门禁，卸载、安装、启动、PID 和串口闭环均通过，避免用错误流程浪费 100 轮时间。

## 100 轮结果

| 指标 | 结果 |
| --- | --- |
| 请求 / 完成 | **100 / 100** |
| 卸载成功 / 失败 | **100 / 0** |
| 全新安装成功 / 失败 | **100 / 0** |
| APP 启动成功 / 失败 | **100 / 0** |
| 启动后 PID 校验 | **100 / 100** |
| 唯一 PID | **100**，证明每轮均为新进程 |
| 单轮最短 / 平均 / 最长 | 10.645 s / 12.660 s / 16.102 s |
| 总耗时 | 21 分 9 秒 |
| 唯一 boot_id | **1** |
| boot_id 变化 | **0** |
| 串口重启标记 | **0** |
| 串口读取失败 | **0** |
| 串口回环 | 79 B，包含 `VIBEKITS_SERIAL_MONITOR_READY` 与 `console:/ $` |
| Logcat | 11 份 / 268,068 B |
| 检测到系统重启 | **否** |

串口在测试期间没有新的输出；这与“串口未监听”不同：测试前真实收发回环成功，读取 worker 全程存活且失败数为 0，三个阶段持续排空缓冲区。由于没有发生重启，故障现场分支没有被触发，也没有伪造“最后线程”数据。

11 份系统日志中以下关键字命中均为 0：

- `FATAL EXCEPTION`
- `Fatal signal`
- `ANR in com.vibekits.vibekits`
- `WATCHDOG KILLING SYSTEM PROCESS`
- `sys.powerctl`
- `reboot: Restarting system`
- `Booting Linux`

## 结论

本轮验收通过。Harness 通过 VibeKits 自有 ADB 和串口接口完成 100 次“删除旧 APP → 全新推送安装 → 启动 APP → 确认进程”，COM33 同步保持独立监听；100 轮均成功，没有检测到 Android 系统重启、VibeKits ANR 或致命崩溃。

该结论限定于本次 100 轮压力场景，不等同于对设备所有硬件和长期运行状态作无限保证。

## 本地证据

- 正式逐轮明细：`build/windows/x64/runner/Release/tmp/stress/android-install-stress-2026-08-27T22-28-29-170Z.jsonl`
- 正式汇总：`build/windows/x64/runner/Release/tmp/stress/android-install-stress-2026-08-27T22-28-29-170Z.summary.json`
- 1 轮门禁明细：`build/windows/x64/runner/Release/tmp/stress/android-install-stress-2026-08-27T22-27-40-465Z.jsonl`
- Harness 工具活动：`%LOCALAPPDATA%/Vibekits/Harness/tool_activity.json`

## 构建门禁

- 压力 MCP `node --check`：通过。
- Windows Release：通过。
- Windows Bundle：通过，版本 `v1.9.0-dev.129+2129`，29 项运行时齐全。
