# v1.9.0-dev.11 Harness 工具调用审计验收

日期：2026-08-18

平台：Windows x64
源码版本：`1.9.0-dev.11+21`

- 工具日志默认开启；Harness 模型设置和当前工具记录窗口均可关闭后续日志，已有记录保留。
- 开发工具左侧提供“当前工具的 Harness 记录”，按计算器、SQLite、串口、ADB、HTTP、Git、GitHub、文件搜索及微工具的真实工具 ID 过滤。
- 记录包含时间、工具、目标、参数摘要、结果摘要、成功/失败/未执行状态和耗时；支持单条删除、清空当前工具及刷新。
- API Key、密码、Secret、Token、Authorization、Cookie 和配对码不会写入记录。
- ADB 成功/失败记录由 `AdbService.runCommand` 在 `adb.exe` 进程退出后写入，包含绝对可执行路径、真实参数、退出码、stdout、stderr 和 `evidenceSource=adb-process`；Harness 桥只记录用户拒绝，避免伪成功与重复。
- Windows 真机 `192.168.3.63:5555` 实测：Harness 经内置 MCP 列出设备并读取 `ro.product.model=huanglong`、`ro.build.version.release=12`、`ro.product.manufacturer=HL2.0`，输出 `HARNESS_ADB_SMOKE_PASSED`。
- 定向自动测试：ADB 执行层、Harness 工具桥与 ADB 记录界面合计 16/16 通过；`flutter analyze` 0 问题。
