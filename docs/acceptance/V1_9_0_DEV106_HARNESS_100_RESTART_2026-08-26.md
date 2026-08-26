# v1.9.0-dev.106 Harness 连续启停 100 次验收

## 结论

Windows Release `v1.9.0-dev.106+116` 连续执行 100 次“启动 VibeKits → 进入智能体（Harness）→ 等待真实 DSH HTTP 响应 → 从托盘退出 VibeKits → 核对 Harness 子进程退出”，结果 **100/100 通过**。

本验收不是只检查加载动画。每一轮均从新生成的 `harness-web-*.log` 读取该轮 DSH PID 和随机回环 URL，并要求实际 HTTP 响应为 200；退出后再核对同一 PID 已不存在。

## 测试对象与命令

- EXE：`build/windows/x64/runner/Release/vibekits.exe`
- 文件/产品版本：`1.9.0-dev.106+116`
- 脚本：`tool/harness_app_restart_stress.ps1`
- 命令：`./tool/harness_app_restart_stress.ps1 -Count 100 -ReadyTimeoutSeconds 90 -CloseTimeoutSeconds 20 -OutputPath .tmp/harness-app-restart-v106-100.csv`
- 原始逐轮结果：`.tmp/harness-app-restart-v106-100.csv`

## 原子验收动作

每一轮执行以下独立动作：

1. 启动新的 Release APP 进程并等待真实主窗口句柄。
2. 通过主流快捷键 `Ctrl+1` 进入智能体（Harness）。
3. 只接受本轮新建的 Harness 日志，解析真实 Node PID 和 `127.0.0.1` 随机端口。
4. 请求该 URL，只有收到 HTTP 200 才判定 Harness 正常。
5. 发送与托盘“退出并停止后台服务”相同的原生命令。
6. 要求 APP 在 20 秒内正常退出，不允许强杀算通过。
7. 再等待并确认本轮记录的 Harness PID 已退出。

## 结果

| 指标 | 结果 |
| --- | ---: |
| 总轮数 | 100 |
| 完整通过 | 100 |
| 失败 | 0 |
| 主窗口就绪 | 100/100 |
| Harness HTTP 就绪 | 100/100 |
| HTTP 状态 | 100 次均为 200 |
| APP 正常退出 | 100/100 |
| Harness 子进程退出 | 100/100 |
| APP PID | 100 个不同 PID |
| Harness 就绪最短 / 平均 / P95 / 最长 | 11.241 / 21.220 / 23.864 / 24.665 秒 |
| APP 退出最短 / 平均 / P95 / 最长 | 3.956 / 6.126 / 9.041 / 14.756 秒 |

Windows 在长批次中复用了 4 个已退出的 Harness PID，因此 100 轮共有 96 个不同的 Harness PID 数值；脚本每轮在开始下一轮前都核对当轮 PID 已不存在，这不是进程复用或残留。

测试结束后的独立检查：`vibekits.exe` 进程数为 0；最后一轮 Harness PID `3248` 不存在。系统中另有一个 Node 进程，但其 PID 从未出现在本批次 CSV 中，和 VibeKits Harness 无关。

## 本轮修复

首次旧版本批次在第 16、30、31、32 轮出现托盘退出命令超过 20 秒，而四轮 Harness HTTP 均为 200。定位到 Windows runner 先把 `WM_COMMAND` 转发给 Flutter 插件，插件可能提前消费托盘退出命令。

`windows/runner/flutter_window.cpp` 现先处理 runner 自己的 `kTrayOpenCommand` / `kTrayExitCommand`，再把其他消息交给 Flutter。修复后的 5 次预检为 5/5，通过后才从零执行本次 100 次正式验收。

## 未掩盖的性能项

连续启停稳定性已通过，但 Harness 冷启动平均仍为 21.220 秒，尚未达到产品要求的稳定 3 秒。这是独立的启动性能未完成项，不能用本报告的 100/100 稳定性结论替代。
