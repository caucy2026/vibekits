# v1.9.0-dev.126 Harness 剪贴板验收

日期：2026-08-27
平台：Windows / WebView2
构建：`v1.9.0-dev.126+2126`

## 问题与修复

官方 DSH 的消息编辑器可能使用普通 `textarea`，也可能在版本演进后使用 `contenteditable` 富文本节点。旧逻辑只识别 `input/textarea`，外层截获快捷键后无法把剪贴板内容交给富文本编辑器。

本版统一识别可见的 `input`、`textarea` 和 `contenteditable` 编辑器，支持 Ctrl/Cmd+V、Ctrl/Cmd+Shift+V、Shift+Insert 与 Ctrl/Cmd+C。富文本插入继续触发标准编辑事件，普通输入框继续通过原生 value setter 通知框架状态。

## 真实验收

1. 使用最新 Release 以 `--open-harness --webview-debug-port=9333` 启动；调试端口只在显式测试参数下开放。
2. 确认 WebView2 目标标题为 `DeepSeek Harness`，地址为本机回环 DSH。
3. 内核级测试把唯一标记写入 Windows 系统剪贴板，在真实 DSH 消息编辑器发送 Ctrl+V，再从 DOM 读回：通过。
4. 选中同一编辑器内容并发送 Ctrl+C，再从 Windows 系统剪贴板读回：通过。
5. 物理输入测试按 Windows DPI、WebView 客户区和 DOM 坐标换算真实屏幕位置，移动鼠标点击输入框后发送 Windows 原生 Ctrl+A/Ctrl+V：通过。
6. 对同一真实输入框发送 Windows 原生 Ctrl+A/Ctrl+C，系统剪贴板与页面内容完全一致：通过。

最终物理测试标记：`VIBEKITS_PHYSICAL_CLIPBOARD_1787839915275`。

| 验收项 | 结果 |
| --- | --- |
| 剪贴板合同测试 | 1/1 通过 |
| WebView2 Ctrl+V | 通过 |
| WebView2 Ctrl+C | 通过 |
| 真实鼠标 + 物理 Ctrl+V | 通过 |
| 真实鼠标 + 物理 Ctrl+C | 通过 |
| Windows Release 构建 | 通过 |

## 可重复命令

```powershell
build\windows\x64\runner\Release\vibekits.exe --open-harness --webview-debug-port=9333
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\harness_clipboard_physical_e2e.ps1 -AppProcessId <PID> -DebugPort 9333
```

测试脚本只定位本次 VibeKits 启动后创建的 `msedgewebview2` 窗口，不向其他应用发送鼠标或键盘事件。
