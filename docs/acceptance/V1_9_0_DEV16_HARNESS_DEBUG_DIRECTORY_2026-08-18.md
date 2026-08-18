# Vibekits 1.9.0-dev.16 Harness 调试目录验收

## 目标

- Harness 调试产生的日志、截图和临时文件有统一且可配置的位置。
- 默认位置为 Vibekits 可执行文件同级 `tmp`，设置后必须真实影响执行链并跨重启保存。

## 实现

- 设置页新增“调试文件目录”和目录选择按钮。
- 空配置解析为 `<vibekits.exe 所在目录>/tmp`。
- 打开 Harness 页面时创建，保存设置时再次验证：`logs`、`screenshots`、`temp`。
- Harness 请求携带调试目录；子进程使用 `DSH_LOG_DIR`、`VIBEKITS_DEBUG_DIR`、`VIBEKITS_SCREENSHOT_DIR` 和专用 `TEMP/TMP/TMPDIR`。
- stdout/stderr 同步写入 `logs/harness-<UTC>.log`，退出时追加真实退出码。
- 截图 OCR 的输出目录改为 `screenshots`。
- 路径写入普通 AppSettings；API Key 仍只进入系统凭据和启动进程环境，不进入该设置。

## 自动验收

| 项目 | 结果 |
|---|---|
| `flutter analyze` | 通过，0 问题 |
| AppSettings 写入并重新加载调试目录 | 通过 |
| 创建 `logs/screenshots/temp` | 通过 |
| 设置页选择、保存和实际目录创建 | 通过 |
| Harness 完整组件回归 | 11/11 通过（含日志 Key 脱敏） |
| 截图收到 `screenshots` 路径且自动 OCR | 1/1 通过 |
| Windows Debug 构建与启动 | 通过，PID `34444`，Console 会话窗口标题 `Vibekits` |
| 默认目录实查 | `build/windows/x64/runner/Debug/tmp/{logs,screenshots,temp}` 三目录存在 |

## 仍待补证

- 使用真实 DeepSeek 任务补一份 stdout/stderr 日志文件证据；不得在文档中记录 Key。
- macOS 默认目录可创建性和截图权限仍需实机验证。
