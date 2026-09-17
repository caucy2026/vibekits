# PAD 63 Harness 编写小程序卡死：诊断记录

日期：2026-09-15（Asia/Shanghai）。目标仅为用户指定的 192.168.3.63:5555，不以 PAD 75 的结果代替。

## 本次实测

- 从正在运行的本机 VibeKits `/catalog` 刷新 `vibekits.adb.connect`、`vibekits.adb.list_devices`、`vibekits.adb.command`、`vibekits.serial.list_ports` 的定义；通过认证的本机 `/invoke` 调用，未暴露桥接凭据。
- `adb.connect` 到 63 返回：ADB 命令 10 秒未完成，已终止。
- `adb.list_devices` 仅返回 192.168.3.75:5555，状态 device；没有 63。
- 独立 TCP 5555 连通性检查也超时。
- 串口列表仅 Bluetooth-Incoming-Port、debug-console，无可验证的 CH340 设备；未打开无关串口。
- 未获得 63 的设备身份、ANR、崩溃日志、CPU/内存、温度或生成任务现场；没有重启、清日志、覆盖安装或远程桌面操作。

结论：当前无法连接 63，卡死根因未确认。连接超时不能证明卡死由网络引起，也不能证明只是应用界面问题。

## 源码中确认存在的性能风险（不是现场根因结论）

`lib/features/local_models/presentation/deepseek_agent_workspace.dart`：

- `handle.output.listen` 每收到输出片段即调用 `setState`，拼接全部已有回复，并更新进度。
- 每片段调用 `_syncRunningSessionCache`，复制消息和会话列表；可见会话另调用 `_scrollToEnd`。
- 回复组件 `MarkdownBody(data: message.text)` 接收不断增长的整段文本，生成长代码时存在重复解析与布局开销。

这些工作位于界面路径；后台网络异步不等于 UI 的字符串处理、缓存复制和 Markdown 布局已移到后台。尚未测量实际输出频率及帧耗时，也未核实 63 当时使用的具体版本和页面路径。

## 最小修复方向与验证

1. 连接恢复后先保留现场：设备身份、版本、进程状态、ANR/crash/main/events 日志，以及 CPU/内存/温度采样。若是整机卡死，需独立串口或内核证据，不能仅改 UI。
2. 对同一个小程序任务记录首字时间、流输出频率、帧耗时、停止响应、峰值内存与后台进程占用。
3. 若证实输出刷新瓶颈，合并短时间内的输出，降低刷新与缓存复制频率；任务结束/停止时完整刷出尾部，保证不丢字、不错会话。
4. CPU 密集解析、压缩、文件扫描按实际热点移到有界后台 isolate/工作线程；I/O 保持异步。不能无限增加线程，也不能把 Flutter UI 本身放到工作线程。
5. 长代码生成、停止、切换会话、并行任务和完成尾帧均需回归；必须在 63 上验证可操作、无新增 ANR、资源稳定后才能宣称问题解决。

## 未完成项

- 63 真机卡死复现及根因确认：设备连接阻塞。
- 串口/ADB 时间关联及硬件源码映射：无目标身份和故障证据，未开展无关硬件源码抓取。
- 未修改产品代码，未构建或发布。当前不能给出修复通过结论。
