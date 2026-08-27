# v1.9.0-dev.124 Harness rc.2 首启与 100 次完整重启验收

## 验收对象

- Windows Release：`build/windows/x64/runner/Release/vibekits.exe`
- APP 版本：`1.9.0-dev.124+2124`
- 官方 Harness：`@deepseek-ai/dsh@0.1.1-rc.2`
- 入口：`vibekits.exe --open-harness`
- 约束：每轮必须创建新的 APP/DSH/WebView2 进程树，HTTP 200 后从 APP 的“退出”路径关闭，并确认本轮全部子进程消失；禁止保留 DSH 伪造热启动。

## 现场根因与修复

1. 旧 APP 或 Harness 进程仍在运行时，两个版本会同时扫描/编译同一套大量模块，真实冷启动曾达到 30～120 秒。
2. 新用户 profile 没有 Node 编译缓存，官方插件图首次编译造成 20～50 秒白屏。构建阶段现以 `NODE_COMPILE_CACHE_PORTABLE=1` 预热固定版本；Release 直接只读使用约 2,000 个内容寻址缓存文件，不在首启时复制和重复扫描。
3. 官方 Web 使用 `--no-open`，避免 DSH 再启动外部浏览器。
4. WebView2 偶发子进程会越过普通 COM 清理继续存活。Runner 在控制器销毁后只回收当前 APP 的后代进程树，不影响独立 MCP、SSH 等后台服务。
5. 原压力脚本依赖窗口焦点发送 `Ctrl+1`，第 97 轮焦点漂移造成测试误失败。新增只用于验收的确定性 `--open-harness` 入口，并将“全部后代进程退出”作为硬门禁。

## 结果

| 指标 | 结果 |
|---|---:|
| 完整退出/重启 | 100/100 通过 |
| Harness HTTP 200 | 100/100 |
| 全部 APP 后代进程退出 | 100/100 |
| 残留进程 | 0 |
| Harness 就绪最小值 | 6,231 ms |
| Harness 就绪中位数 | 6,869 ms |
| Harness 就绪 P95 | 8,005 ms |
| Harness 就绪最大值 | 9,698 ms |
| Harness 就绪平均值 | 7,025.4 ms |
| APP 完整退出中位数 | 4,461 ms |
| APP 完整退出 P95 | 6,073 ms |

另用全新临时 `LOCALAPPDATA` 模拟从未运行过 Vibekits 的用户，首次 Harness 就绪为 6,425 ms；随后两轮为 5,974/6,208 ms，3/3 通过且退出无残留。当前已消除现场 30～50 秒卡死，但尚未达到 3 秒目标，不能宣称 3 秒验收通过。

## 回归与构建

- Harness/UI 回归：14/14 通过，覆盖官方版本/参数、设置即时弹出、会话与权限持久化、停止任务、工作区恢复和滚轮转发。
- Windows Release 构建成功，文件版本与产品版本均为 `1.9.0-dev.124+2124`。
- 最终重编后二进制追加 3 轮烟测，3/3 HTTP 200、3/3 完整退出、残留 0；当时机器刚完成 Analyze/Release 构建，三轮就绪为 12.088～12.610 秒。该结果仍远低于现场 30～50 秒卡死，但也说明目前不能承诺所有机器/负载下稳定低于 10 秒。
- Flutter Analyze：无新增错误；保留 1 条既有 `github_proxy_service.dart` 风格提示，不影响构建或本次功能。

## 证据

- 最终 100 轮原始 CSV：`evidence/V1_9_0_DEV124_HARNESS_RC2_100_RESTART.csv`
- 最终重编产物 3 轮烟测：`evidence/V1_9_0_DEV124_HARNESS_RC2_FINAL_SMOKE_3.csv`
- 旧焦点驱动脚本第 97 轮失败证据：`evidence/V1_9_0_DEV124_HARNESS_RC2_100_RESTART_FAILED_AT_97.csv`
- 压力脚本：`tool/harness_app_restart_stress.ps1`

## 上游风险

DSH 仍是候选版本。官方社区已报告 rc.2 在高并发会话下可能无响应；本次验收覆盖单 APP 生命周期、首启和完整退出，不把它等同于多会话高并发稳定性证明。后续升级必须重新执行离线依赖、UI 兼容、首启以及 100 次完整退出重启门禁。
