# v1.9.0-dev.125 Android 63 APK 连续安装与串口监听验收

## 目标

- 由官方 DeepSeek Harness 发起测试，不用普通 ADB 脚本冒充智能体调用。
- 通过 VibeKits 内置 ADB 向 `192.168.3.63:5555` 连续覆盖安装同一 APK 100 次。
- 同时保持 COM33 串口监听，并以 Android `boot_id` 双重判定设备是否重启。
- 原始串口和异常 Logcat 只保存在本机，Harness 仅接收汇总。

## 测试输入

| 项目 | 值 |
| --- | --- |
| APK | `build/app/outputs/flutter-apk/app-release.apk` |
| APK SHA-256 | `56708518ABD89CFD3E461DF9B04F5A6FAF75A26CE60184825343041FC40060B1` |
| APK 大小 | 115,541,133 B |
| APK 构建时间 | 2026-08-27 09:50:54 |
| ADB 设备 | `192.168.3.63:5555` |
| 串口 | `COM33` / `USB-SERIAL CH340` / VID `0x1A86` / PID `0x7523` |
| 串口参数 | 115200、8 数据位、1 停止位、无校验、RTS/CTS |
| 初始 boot_id | `e2835cf6-0b74-4102-a90b-4a8ba081eb43` |

本轮原计划重新构建 dev.125 APK，但 Gradle Wrapper 下载 `gradle-8.14.3-bin.zip` 两次连接超时，本机缓存只有 0 B 临时文件。因此设备压力段使用当天已经成功构建的上述 Release APK；没有把失败构建冒充为新产物。

## 执行方式

Harness 调用单个 `android__apk_install_stress_100` 聚合工具。工具在本地顺序执行：

1. 调用 `vibekits.adb.connect`，打开 ADB 心跳会话。
2. 调用 `vibekits.serial.list_ports` 核验 COM33 为 CH340，再打开串口长连接。
3. 读取初始 `boot_id` 并清空串口初始缓存。
4. 每轮调用 `vibekits.adb.install_apk(replace=true)`；随后读取 `boot_id` 和串口增量缓存。
5. 如 `boot_id` 改变，或串口出现 `Booting Linux`、`Linux version`、`Restarting system`、`reboot`、`coldboot`，立即停止并在本地采集最近 1000 行 Logcat。
6. 无论结果如何都关闭 ADB 与串口会话。

专用启动参数只对本次压力测试放行明确列出的 ADB/串口接口，正常启动的权限策略不变。原始串口和 Logcat 不返回给外部模型。

## 实测结果

| 指标 | 结果 |
| --- | --- |
| Harness 开始 | 2026-08-27 20:37:00（Asia/Shanghai） |
| Harness 完成 | 2026-08-27 20:54:01（Asia/Shanghai） |
| 完成轮次 | **100 / 100** |
| 安装成功 | **100** |
| 安装失败 | **0** |
| 单轮最短 / 平均 / 最长 | 7.734 s / 10.154 s / 12.974 s |
| boot_id 变化 | **0** |
| 串口重启关键字 | **0** |
| 检测到系统重启 | **否** |
| ADB 会话关闭 | 通过 |
| 串口会话关闭 | 通过 |

官方 Harness 最终返回 `completed=100`、`installsPassed=100`、`installsFailed=0`、`rebootDetected=false`。

## 串口子项结论

COM33 枚举、参数配置、句柄打开、100 轮增量读取和最终关闭均成功，但累计接收字节为 **0 B**。因此：

- “100 次安装未导致系统重启”由每轮真实 `boot_id` 闭环确认，结论有效。
- “串口监听接口被持续调用”有工具活动与本地逐轮记录证明。
- “串口实际收到系统日志”本轮**未通过**，不能因为端口成功打开就标成全绿。后续需在设备主动输出日志或重启夹具下，分别复核 RTS/CTS 与无流控，并验证接收字节大于 0。

压力段完成后又以同一 APP 串口接口执行无流控被动监听 5 秒，句柄正常打开且无错误，仍为 0 B；因此不是 RTS/CTS 单一配置造成。当前更可能是测试窗口内设备串口没有主动输出，或 COM33 的接收线路/硬件流向与 SecureCRT 当时场景不同。未主动重启设备来制造日志，因为该动作不属于本轮授权。

## 本地证据

- 逐轮原始记录：`build/acceptance/android63-stress/android-install-stress-2026-08-27T12-37-00-621Z.jsonl`
- 汇总：`build/acceptance/android63-stress/android-install-stress-2026-08-27T12-37-00-621Z.summary.json`
- APP 工具活动：`%LOCALAPPDATA%/Vibekits/Harness/tool_activity.json`

工具活动文件只保留最新 500 条，3 秒 ADB 心跳会挤出较早条目；100 轮完整事实以不可截断的本地 JSONL 为准。当前 500 条活动全部为成功状态。

## 代码门禁

- Windows Release 构建：通过。
- 本地压力 MCP 脚本 `node --check`：通过。
- 本次 3 个 Dart 文件定向 `flutter analyze --no-pub`：无问题。
- Android dev.125 重建：未通过，原因是 Gradle 分发下载超时；不影响本轮既有 APK 的 100 次设备稳定性结论，但正式发布前必须补构建。
