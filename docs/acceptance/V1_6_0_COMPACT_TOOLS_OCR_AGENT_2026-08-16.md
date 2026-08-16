# Vibekits v1.6.0 极简工具、截图 OCR 与智能体验收记录

日期：2026-08-16  
平台：Windows x64  
版本：`1.6.0+7`

## 验收范围

| 能力 | 自动证据 | 结果 |
|---|---|---|
| 微工具收敛 | 搜索 Base64 时左侧只出现“转换与检查”；进入后自动定位 Base64；分类 Tab、共享输入/输出、错误保留、结果继续输入和清空通过 Widget 测试 | 通过 |
| 模型页信息架构 | 首屏只显示“截图 OCR / DeepSeek 智能体”；模型清单和 VAD 不占首屏；800px 测试宽度无 RenderFlex 溢出 | 通过 |
| 截图即 OCR | 注入系统截图结果后自动预览并只调用一次 OCR，不需要再次点击“识别文字” | 通过 |
| DeepSeek 智能体 | 官方包与 headless 参数固定；选择工作区、保存路径、提交任务、流式输出、运行中停止入口、进程结束恢复运行按钮 | 通过 |
| 原有自动路由 | 图片拖入仍自动进入 OCR；模型已安装时仍自动识别；文档、数据库、模型和未知文件路由全量回归 | 通过 |

## 发布验证

- `dart format lib test`：完成；无本批格式差异。
- `flutter analyze`：`No issues found`。
- `flutter test --reporter expanded`：235/235 通过。
- `flutter build windows --release`：成功，耗时约 117.8 秒。
- `vibekits.exe` FileVersion/ProductVersion：`1.6.0+7`。
- Release 携带 `README.md` 隐藏启动，5 秒后仍存活；随后只结束该测试进程。
- `vibekits_onnx.dll`、`onnxruntime.dll`、`sqlite3.dll`、`tools/7zip/7z.exe`、`tools/7zip/7z.dll` 均存在。

## 未冒充完成的项目

- Windows 系统截图需要人工框选，本轮自动测试通过可注入适配层验证“完成后立即 OCR”，未把无人值守测试写成真实人工框选证据。
- DeepSeek 官方仓库仍标记 Developer Preview；固定 RC5 的进程适配与 UI 已验证，但当前网络下 npm 包未完成真实下载、模型配置和端到端代理任务，不能写成官方智能体实启通过。
- macOS 截图权限、`screencapture`、ONNX Runtime、Harness 和 Release 仍需在 macOS 实机验收。

## 备份

- 实现提交：`593e6a9`（`feat: compact tools and add OCR agent workspaces`）。
- `main` 已同步到本地 `backup` 和 GitHub `cloud`；本验收记录更新后创建 `v1.6.0` 标签，并再次同步最终发布提交与标签。
