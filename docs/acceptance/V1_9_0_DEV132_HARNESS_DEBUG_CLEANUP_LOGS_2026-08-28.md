# v1.9.0-dev.132 Harness 调试目录清理与诊断日志验收

## 用户闭环

1. 系统清理扫描会并行盘点 Harness 配置的调试目录。
2. 结果顶部单独显示目录路径、总占用、24 小时前可清理容量，以及运行日志、调试截图、临时文件三个分项。
3. 达到保留期的项目默认不勾选；用户勾选“由用户选择是否清理”后才进入清理确认。
4. Harness 页面“运行日志”可查看 `harness-work.jsonl` 和 `harness-web-*.log` 的最近内容。
5. Harness 可调用 `vibekits.harness.diagnostics` 返回最近日志索引、最新日志尾部和工具调用审计；API Key、密码、Token 和 Authorization 会脱敏。

## 安全边界

- 扫描和容量统计只读。
- 24 小时内的当前任务证据不进入可清理候选。
- 低磁盘压力、10 GiB 目标和自动选择算法均不能自动选中 Harness 调试证据。
- 日志写入失败不会中断模型任务或工具任务。
- 日志查看限制在 Harness `logs` 子目录并使用有界尾部读取。

## 自动验证

- `cleanup_decision_engine_test.dart`：Harness 旧日志在极低剩余空间下仍为 review，automatic 为空。
- `harness_debug_storage_service_test.dart`：140 B 总量中仅 100 B 超过 24 小时保留期。
- `harness_runtime_log_store_test.dart`：持久化日志可枚举、可读取，API Key 内容不泄漏。
- `harness_tool_bridge_test.dart`：全部既有 Harness 工具桥回归通过。
- 合计：34/34 通过。
- 本次 8 个改动源文件定向 Analyze：No issues found。
- Windows Release：构建通过；Bundle 版本 `1.9.0-dev.132+2132`，29 项必需运行时通过。
- 真实运行：APP PID 35592 正常响应；Harness 由 starting 到 ready 约 9.2 秒，结构化日志真实落盘。
- 当前 Release 调试目录：logs 469 个文件、47,226 B，其中 24,214 B 超过 24 小时；screenshots 0 B；temp 4 个文件、0 B。该数据只用于验证算法展示，不执行删除。
