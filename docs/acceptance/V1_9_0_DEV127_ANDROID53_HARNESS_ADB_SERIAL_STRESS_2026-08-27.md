# v1.9.0-dev.127 Android 53 Harness ADB 与串口联合压力验收

## 目标

- 必须由 VibeKits 内嵌的官方 DeepSeek Harness 发起，不用普通终端脚本冒充智能体。
- 通过 APP 自带 ADB 向 `192.168.3.53:5555` 连续覆盖安装 APK 100 次。
- 同时保持 APP 自带的 COM33 串口长连接，逐轮读取系统输出并以 Android `boot_id` 判定重启。
- ADB、串口调用必须写入 VibeKits Harness 工具活动日志，完成后释放两个长连接。

## 本次修复

首轮失败不是设备离线，而是压力 MCP 调用 APP 内嵌工具时，命令行预批准只传到了外部 MCP 服务，没有传到官方 Harness 页面内部的工具桥。写操作等待被 WebView 遮挡的授权对话框，约 5 分钟后桥接关闭并返回 `TypeError: fetch failed`。

dev.127 将预批准集合沿 `VibekitsApp → MainShell → LocalModelsTab → OfficialHarnessWorkspace` 完整传递，并在每次 Harness 会话重启时重新装载。本次专用启动参数只批准 ADB/串口压力测试需要的接口，正常启动权限策略不变。

串口参数同步为已验证 SecureCRT 配置：COM33、115200、8N1、无校验、无流控（DTR/DSR、RTS/CTS、XON/XOFF 均关闭）。压力 MCP 已纳入运行时准备、Windows 安装、Bundle 校验和官方 DSH MCP 配置，不再依赖源码目录偶然存在。

## 测试输入

| 项目 | 值 |
| --- | --- |
| APP | `v1.9.0-dev.127+2127` Windows Release |
| ADB 设备 | `192.168.3.53:5555` |
| 设备 | `huanglong` / `hi3781v730_tablet` |
| APK | `build/app/outputs/flutter-apk/app-release.apk` |
| APK 大小 | 115,541,133 B |
| APK SHA-256 | `56708518ABD89CFD3E461DF9B04F5A6FAF75A26CE60184825343041FC40060B1` |
| 串口 | COM33 / USB-SERIAL CH340 / VID `0x1A86` / PID `0x7523` |
| 串口参数 | 115200、8 数据位、1 停止位、无校验、无流控 |
| 初始 boot_id | `5108f394-db2a-44c6-86dd-8c87b5475671` |

## Harness 真实调用证据

在官方 Harness 输入任务后，页面轨迹显示真实调用：

`mcp__vibekits-android-stress__android__apk_install_stress_100`

参数固定为 `.53` 设备、上述 APK、COM33 和 100 轮。工具内部保持一个 ADB 心跳会话和一个串口会话，每轮依次安装、检查会话状态、读取 `boot_id`、读取串口增量数据；任一阶段失败都会进入逐轮 JSONL，不会被最终摘要吞掉。

## 实测结果

| 指标 | 结果 |
| --- | --- |
| 开始 / 完成 | 2026-08-27 23:13:30 / 23:31:18（Asia/Shanghai） |
| 完成轮次 | **100 / 100** |
| 安装成功 / 失败 | **100 / 0** |
| 单轮最短 / 平均 / 最长 | 7.639 s / 10.649 s / 13.810 s |
| 唯一 boot_id 数 | **1** |
| boot_id 变化 | **0** |
| 串口重启关键字 | **0** |
| 检测到系统重启 | **否** |
| COM33 累计接收 | **0 B** |
| ADB 长连接关闭 | **成功**，`adb-2` |
| 串口长连接关闭 | **成功**，`serial-1` |
| 测试后 APP 状态 | **Responding=True** |

Harness 最终回答与本地汇总一致：`completed=100`、`installsPassed=100`、`installsFailed=0`、`rebootDetected=false`。

## 结论与未通过项

- **通过**：Harness 调用 APP 自带工具；53 设备 ADB 长连接；连续 100 次覆盖安装；逐轮 boot_id 判定；无授权重复弹窗；两个会话最终释放；APP 未卡死。
- **未通过**：本轮 COM33 虽然成功枚举、以正确参数打开、保持 100 轮并成功读取/关闭，但设备没有输出任何字节。因此只能证明“串口监控链工作”，不能声称“抓到真实串口系统日志”。
- 后续若要验收串口数据本身，应在设备明确产生启动日志的窗口执行，或由用户授权一次受控重启；不能用 ADB boot_id 结果冒充串口接收成功。

## 本地证据

- 逐轮明细：`build/windows/x64/runner/Release/tmp/stress/android-install-stress-2026-08-27T15-13-30-510Z.jsonl`
- 汇总：`build/windows/x64/runner/Release/tmp/stress/android-install-stress-2026-08-27T15-13-30-510Z.summary.json`
- 工具活动：`%LOCALAPPDATA%/Vibekits/Harness/tool_activity.json`

工具活动保留最新 500 条；3 秒 ADB 心跳会挤出前 25 轮的早期活动，因此 100 轮完整事实以不截断的 JSONL 为准。保留下来的 500 条全部为成功状态，其中包括 75 次安装、270 次 ADB 会话状态、76 次 boot_id Shell、77 次串口读取以及 ADB/串口各一次成功关闭。

## 构建门禁

- Windows Release 构建：通过。
- Windows Bundle 校验：通过，压力 MCP 已包含在 `tools/harness`。
- 压力 MCP `node --check`：通过。
- 目标 Dart 文件静态分析：无报告问题。
