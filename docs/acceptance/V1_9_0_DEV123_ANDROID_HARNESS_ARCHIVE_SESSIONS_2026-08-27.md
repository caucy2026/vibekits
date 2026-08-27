# v1.9.0-dev.123 验收报告

日期：2026-08-27  
目标：Android 清理可用、工具自动发现、Harness 安全自迭代、标准压缩互操作、串口/ADB 长连接，以及 Windows DSH 首次启动异常修复。

## 结论

| 项目 | 结果 | 证据 |
| --- | --- | --- |
| Android 清理 UI/扫描 | 通过 | `192.168.3.62:5555` 安装 `1.9.0-dev.123(2123)`；进入清理页可见扫描入口；扫描返回 `0 项/0 个不可读位置`；APP PID 保持存活 |
| Android 删除安全边界 | 通过（自动夹具） | 临时应用缓存可删除；共享目录和越界文件保持不变；发现与删除共用平台真实 cache path |
| Android 私有缓存真机删除 | 未完成 | Release 不可 `run-as` 造夹具；临时 Debug 构建在 Gradle 原生库合并阶段长时间无输出后主动终止，未把自动测试冒充真机实证 |
| Harness 自动发现 | 通过 | 161 个定义接口、139 个可执行接口、公开 `missingHandlers=0`；目录从 `ToolSpec/handler` 自动生成 |
| Harness 自迭代 | 通过 | `project.iteration_inspect → project.build` 顺序、参数、失败阶段和“仅生成候选”门禁测试通过 |
| 串口长连接 | 通过 | 同一 session 跨调用读取缓冲、写入、关闭并释放句柄 |
| ADB 长连接 | 通过 | open 后立即与定时执行真实 `get-state`；status 刷新；close 取消心跳并释放 |
| 压缩/解压 | 通过 | ZIP、TAR、TAR.GZ、外部 7z、外部 ZIP、RAR5；中文/空文件/全字节二进制逐字节一致 |
| Windows DSH 首启 | 通过（异常修复） | 旧日志 47,852 ms；单 Junction 修复后新 Release 5,094 ms，下降 89.4%，HTTP 正常 |
| Windows Release | 通过 | `build/windows/x64/runner/Release/vibekits.exe` |

## 启动根因与修复

官方 DSH 的 `healProfilesModuleFallback` 在每次启动同步遍历完整依赖闭包，并在 `$DSH_HOME/profiles/node_modules` 为每个包检查 Junction。本机运行时约 32,761 个文件，且测试时 C 盘剩余为 0 B，进程创建到 `dsh web` 输出实测 47.852 秒。

构建补丁把共享 fallback 改为一个指向内置运行时 `node_modules` 的目录 Junction。profile 自己安装的插件仍位于 profile 目录，解析优先级不变；运行时移动时 Junction 会原子重建。修复后的进程创建到 Web 就绪为 5.094 秒。当前没有通过残留后台 DSH 伪造热启动。

## 自动测试

定向命令覆盖：

- `cleanup_platform_policy_test.dart`
- `harness_connection_sessions_test.dart`
- `project_iteration_service_test.dart`
- `archive_interoperability_test.dart`
- `harness_tool_bridge_test.dart`
- `harness_capability_catalog_test.dart`

结果：42/42 通过。Flutter Analyze 用时 140.9 秒，仅发现 `github_proxy_service.dart:142` 一条本次修改前已有的 `prefer_initializing_formals` info，无 error/warning。

## 安全说明

- Android 只自动删除 APP 自己的 cache/code-cache，不扫描或删除其他 APP 私有目录。
- 长连接有显式 session id、状态与关闭动作；桥接销毁时兜底释放。
- 自迭代不会自动安装、覆盖运行中程序、签名、推送或发布。
- 本轮为恢复构建环境，仅删除系统 Temp 中严格匹配 `flutter_tools.*`/`pub_*` 的可重建缓存，共释放 1,248.7 MiB；未删除用户资料。
