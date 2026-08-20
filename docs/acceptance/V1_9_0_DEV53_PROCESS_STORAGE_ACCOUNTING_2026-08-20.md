# v1.9.0-dev.53 进程回收与空间对账验收

## 目标

- APP 退出时不遗留由其启动的后台工具进程。
- 空间分析回答“统计到多少、是否达到 60G、剩余在哪里”。
- 软件列表显示实际安装路径。

## 实现与边界

- Windows Runner 使用带 `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` 的主 Job Object。正常独立启动时，APP 创建的所有后代进程自动继承；若启动器已有受限 Job，则 Harness 继续使用原有逐进程 Job Object 兜底。
- “目录统计合计”来自所有系统盘根项目的实际扫描结果；“未归类/系统保留”是磁盘物理已用减去目录统计量，主要包括不可读系统目录、NTFS 元数据和扫描未完成部分。
- NTFS 组件存储硬链接会让目录逻辑量大于物理已用。界面单独显示重复量，不把逻辑量伪装成实际磁盘占用。
- 安装路径优先读取注册表 `InstallLocation`，为空时采用已匹配的软件安装目录；仍无法确认时明确显示“系统未报告”。

## 验证

- `flutter test test/software_storage_analyzer_test.dart test/cleaner_widget_test.dart --no-pub`：17/17 通过。
- `flutter analyze --no-pub lib/features/cleaner lib/app/platform_process_lifecycle.dart lib/app/app_version.dart`：0 问题。
- `flutter build windows --release --no-pub`：通过，原生 Job Object 代码完成编译链接。
