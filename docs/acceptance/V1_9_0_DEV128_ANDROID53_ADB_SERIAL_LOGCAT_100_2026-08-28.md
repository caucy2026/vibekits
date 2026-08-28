# v1.9.0-dev.128 Android 53 ADB、串口与系统日志 100 轮联合验收

## 验收目标

- 由 VibeKits 内嵌官方 DeepSeek Harness 真实发起单个联合工具调用。
- 使用 APP 自带 ADB 向 `192.168.3.53:5555` 连续覆盖安装 APK 100 次。
- 同时保持 COM33 串口长连接，必须证明当前串口能够真实收发，不能把“端口打开”冒充“串口已通”。
- 周期保存 Android Logcat 系统信息，每轮检查 `boot_id` 与串口重启关键字。
- 全程不重复弹授权、不阻塞 APP，结束后关闭 ADB 和串口会话。

## dev.127 未通过项与本次修复

dev.127 虽完成 100 次安装，但 COM33 累计接收 0 B，因此只证明监听调用存在，未达到串口真实数据闭环。

dev.128 增加以下闭环：

1. 串口打开后先发送一次无副作用控制台命令 `echo VIBEKITS_SERIAL_MONITOR_READY`，收到命令回显、标记和 `console:/ $` 后才确认当前 COM33 是目标 Android 控制台。
2. 回环确认后不再向串口写命令，100 轮期间保持被动监听，避免干扰设备。
3. 第 1 轮及每 10 轮保存最近 200 行 Logcat，共 11 份系统信息快照。
4. 汇总显式返回串口接收字节、串口读取失败数、Logcat 样本数和字节数。
5. 修复测试专用权限集合遗漏 `vibekits.serial.session_write`、导致回环步骤隐藏等待授权的问题。

专用预批准只由显式测试参数启用，正常启动的权限策略不变。

## 测试输入

| 项目 | 值 |
| --- | --- |
| Windows APP | `v1.9.0-dev.128+2128` Release |
| Harness 工具 | `mcp__vibekits-android-stress__android__apk_install_stress_100` |
| ADB 设备 | `192.168.3.53:5555` |
| 设备 | `huanglong` / `hi3781v730_tablet` |
| APK | `build/app/outputs/flutter-apk/app-release.apk` |
| APK 大小 | 115,541,133 B |
| APK SHA-256 | `56708518ABD89CFD3E461DF9B04F5A6FAF75A26CE60184825343041FC40060B1` |
| 串口 | COM33 / USB-SERIAL CH340 / VID `0x1A86` / PID `0x7523` |
| 串口参数 | 115200、8N1、无校验、无流控 |
| boot_id | `5108f394-db2a-44c6-86dd-8c87b5475671` |

## Harness 真实执行轨迹

Harness 按提示没有先调用其他工具，直接调用一次联合压力接口，并等待 15 分钟以上直至工具完成。工具内部维持一个 ADB 心跳会话和一个 COM33 串口会话，所有安装、Shell、Logcat、串口收发和会话释放均经过 VibeKits 工具桥并写入本地活动记录。

串口回环实际数据为：

```text
echo VIBEKITS_SERIAL_MONITOR_READY
VIBEKITS_SERIAL_MONITOR_READY
console:/ $
```

回环共接收 79 B，`roundTripConfirmed=true`。

## 100 轮结果

| 指标 | 真实结果 |
| --- | --- |
| 开始 | 2026-08-28 00:11:06（Asia/Shanghai） |
| 完成 | 2026-08-28 00:26:29（Asia/Shanghai） |
| 请求 / 完成 | **100 / 100** |
| 安装成功 / 失败 | **100 / 0** |
| 单轮最短 / 平均 / 最长 | 7.029 s / 9.204 s / 12.880 s |
| 串口真实接收 | **79 B** |
| 串口读取失败 | **0** |
| Logcat 样本 | **11** |
| Logcat 数据 | **256,361 B** |
| 唯一 boot_id 数 | **1** |
| boot_id 变化 | **0** |
| 串口重启标记 | **0** |
| 系统重启 | **未检测到** |
| ADB 会话关闭 | **成功**，`adb-2` |
| 串口会话关闭 | **成功**，`serial-1` |
| 测试后 APP | **Responding=True** |

## 系统信息分析

11 份 Logcat 覆盖安装开始、每 10 轮和第 100 轮，包含 `PACKAGE_ADDED`、VibeKits 包更新、内核与系统服务信息。以下重启/崩溃关键字命中均为 0：

- `FATAL EXCEPTION`
- `Fatal signal`
- `WATCHDOG KILLING SYSTEM PROCESS`
- `sys.powerctl`
- `reboot: Restarting system`
- `Booting Linux`

日志中存在设备原有的 Huawei Kit 依赖查询告警和 `gfx2d_submit_ta could not get aclk_tde_smmu` 内核警告；它们在设备持续运行、boot_id 不变且 100 次安装全部成功的情况下没有演变为系统重启。本报告保留原始日志，不把这些告警隐去，也不把它们误判为本次 APP 安装失败。

## 结论

本轮验收通过：Harness 真实调用 VibeKits 工具，在 53 设备完成 100/100 次 APK 覆盖安装；COM33 真实收发闭环成立；周期 Logcat 系统监控有 256,361 B 证据；ADB、串口与 APP 生命周期均正常；没有检测到系统重启。

## 本地证据

- 逐轮明细：`build/windows/x64/runner/Release/tmp/stress/android-install-stress-2026-08-27T16-11-06-036Z.jsonl`
- 汇总：`build/windows/x64/runner/Release/tmp/stress/android-install-stress-2026-08-27T16-11-06-036Z.summary.json`
- 工具活动：`%LOCALAPPDATA%/Vibekits/Harness/tool_activity.json`

## 构建门禁

- Windows Release：通过，`v1.9.0-dev.128+2128`。
- Windows Bundle 校验：通过，29 项必需运行时齐全。
- 压力 MCP `node --check`：通过。
- 测试完成后 APP 正常响应，ADB 与串口长连接均成功释放。
