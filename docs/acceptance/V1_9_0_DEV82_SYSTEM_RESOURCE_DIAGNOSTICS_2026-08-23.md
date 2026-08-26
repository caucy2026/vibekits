# v1.9.0-dev.82 系统资源诊断验收

## 交付

- 新增独立“资源诊断”工作区，后台读取 CPU、内存、GPU、磁盘和 Top 进程。
- Windows 资源路径移除慢速 CIM/WMI 主链，改用 .NET 与进程双采样；本机专项由超时降至约 3 秒完成。
- Android 本机/ADB 使用 `/proc/stat` 两点采样，读取内存、`/data`、Top 进程和可用的 KGSL GPU 计数器。
- 新增只读 Harness 工具 `vibekits.system.resources`，默认连续 3 次采样，返回序列、峰值、平均值和重复 Top 进程；自动进入分模块审计日志。

## 自动验收

| 项目 | 结果 |
|---|---|
| Windows/Android 解析与告警 | PASS |
| Windows 本机真实只读采样 | PASS，约 3 秒 |
| 资源工作区异步界面 | PASS |
| Harness 目录与全部左侧工具适配器合同 | PASS |
| 开发工具搜索入口 | PASS |
| Flutter Analyze | PASS，0 问题 |

## 安全结论

探针只读，不结束进程、不清理、不卸载。GPU 不可获取时明确返回未知；单次快照不能排除间歇性问题，Harness 默认连续采样并保留证据。
