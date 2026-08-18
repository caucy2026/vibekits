# Vibekits 1.9.0-dev.18 开源清理算法吸收验收

版本：`1.9.0-dev.18+28`

## 研究对象

| 项目 | 许可证 | 吸收内容 |
|---|---|---|
| Kudu | MIT | 配置化规则、最小年龄、最大深度、直接文件白名单、安全 anchor 思想 |
| constUP Garbage Cleaner | MPL-2.0 | 详细 dry-run、异常大日志、规则说明和垃圾预防建议 |
| BitCleanerX | MIT | 跨平台数据规则、分类汇总和选择后删除流程 |

没有嵌入或复制上述项目的源码、JSON/YAML/PowerShell 文件；Vibekits 规则与扫描实现为独立 Dart 代码。

## 本轮实现

- 规则库 v2：29 条。
- 新增最大扫描深度；顶层异常日志规则固定为深度 0。
- 新增 JetBrains 堆转储/日志、WSLg ETL、Gradio、.NET、Scoop、Delphi 规则。
- 危险或排障相关文件默认不选择，仍执行年龄门槛和回收站流程。

## 自动证据

| 检查 | 结果 |
|---|---|
| 用户目录顶层旧 `java_error_in_*.hprof/.log` 可发现 | 通过 |
| 项目子目录同名 `.hprof` 不递归命中 | 通过 |
| Windows build、模式和年龄过滤 | 通过 |
| 双 Isolate 聚合及取消 | 通过 |
| 清理专项回归 | 17/17 通过 |
| `flutter analyze` | 0 问题 |

自动测试仅操作测试创建的临时沙箱，没有扫描后删除真实用户文件。
