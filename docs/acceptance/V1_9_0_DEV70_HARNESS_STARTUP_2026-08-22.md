# v1.9.0-dev.70 Harness 本地启动性能验收

日期：2026-08-22  
平台：Windows x64  
版本：`1.9.0-dev.70+80`

## 目标

用户进入 Harness 后，本地官方 DSH Web 在 3 秒内可执行任务。空白加载壳、只有静态页面或端口尚未提供完整 API 均不算通过。

## 根因与修改

1. Release 内置运行时约 313 MB。官方 `@deepseek-ai/dsh@0.1.0-rc.7` Web profile 由大量 npm 模块组成，冷启动受小文件读取、Node 模块装载和 Windows 安全扫描影响；启动不访问 npm 或下载组件。
2. Vibekits 旧实现对每个 stdout/stderr 小块强制 `flush`，并对每个小块重建 Flutter 工作区。dev.70 改成日志 2 秒批量落盘、退出完整落盘，诊断 UI 每 100 ms 合并一次。
3. 运行时清单结果在进程内缓存；运行时定位与调试目录准备并行；相同 `cordis.patch.yml` 不再重复写盘。
4. 用户截图为旧 `dev.63+73`。旧进程锁住 Release EXE 时链接器会报 `LNK1104`，因此本轮关闭旧进程后重新构建，并从 EXE 资源核对 FileVersion 与 ProductVersion。

## 实测

| 场景 | App 启动到 DSH 子进程 | DSH 子进程到官方 Web 就绪 | App 到 Web 就绪 |
|---|---:|---:|---:|
| dev.70 首轮 | 约 2.15 s | 4.192 s | 约 6.3 s |
| dev.70 第二轮 | 1.764 s | 3.886 s | 5.650 s |
| 脱离 App、官方 DSH 热缓存对照 | 不适用 | 3.426 s | 不适用 |
| 系统受后台 I/O 干扰的重启 | 约 1.77 s | 15.846 s | 17.619 s |

结论：相比用户截图的 25 秒已明显改善，但稳定 3 秒硬门槛 **未通过**。不得用平均值、加载动画或预先截取的 UI 宣称通过。

## 已通过证据

- `flutter test --no-pub test/deepseek_harness_test.dart`：13/13 通过。
- `flutter build windows --release --no-pub`：成功。
- `build/windows/x64/runner/Release/Vibekits.exe`：FileVersion 和 ProductVersion 均为 `1.9.0-dev.70+80`。
- 最新 Release 已启动到前台；本地日志记录 PID、回环 URL 和 `dsh web` 就绪时间。

## 下一门槛

要稳定进入 3 秒，下一阶段只接受以下能减少官方模块装载量的方案：

1. 为官方 DSH 生成可搬运 V8 启动快照或经过兼容性验证的单文件 bundle；
2. 让 Vibekits MCP 在官方 Web 可操作后热加载，且工具清单和首次调用不能丢失；
3. 官方 DSH 提供原生延迟插件启动能力后升级固定版本。

每个方案必须同时验证工作区/会话、Models/API Key、权限、推理中间态和 Vibekits MCP 工具调用，不能为速度删除核心功能。
