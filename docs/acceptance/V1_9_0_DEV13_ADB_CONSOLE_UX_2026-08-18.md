# Vibekits 1.9.0-dev.13 ADB 命令终端与记录体验验收

日期：2026-08-18

平台：Windows x64

## 本次目标

- ADB 不能只连接和列出设备；选中设备后必须能直接执行命令并看到结果。
- 设备目标由列表锁定，避免用户命令误操作其他设备。
- 普通 Android Shell 命令自动补 `shell`，同时保留安装、文件、Logcat 等 ADB 顶层命令入口。
- Harness 调用记录采用紧凑字号和人类可读摘要，不以大字号原始 JSON 作为主界面。
- 将“工具必须独立完成核心任务”提升为所有工作区的统一验收合同。

## 自动验收

- `flutter analyze`：通过，`No issues found`。
- `flutter test test/adb_service_test.dart test/adb_workspace_widget_test.dart --reporter expanded`：8/8 通过。
- 命令解析覆盖：引号、普通命令自动 Shell、禁止 `-s/-d/-e` 覆盖选中设备、禁止服务器管理命令。
- Widget 覆盖：输入 `getprop ro.product.model` 后真实参数为 `-s <选中设备> shell getprop ro.product.model`，终端展示命令与 stdout。
- 日志覆盖：ADB 进程完成后记录可执行文件、原始参数、退出码、stdout/stderr 和 `adb-process` 证据来源。

## Windows 真机证据

使用 APP Release 目录内置 `tools/adb/adb.exe`：

- `adb devices -l` 同时识别 `192.168.3.62:5555` 与 `192.168.3.63:5555`，状态均为 `device`，型号均为 `huanglong`。
- `adb -s 192.168.3.63:5555 shell getprop ro.product.model` 返回 `huanglong`。

## 仍需继续

- 在同一设备工作台增加文件传输、Logcat 流式查看、截图和 APK 安装的简化交互；底层命令现已可直接使用。
- 按 DEV-117 对其他工作区逐项检查，删除只展示状态但不能完成任务的入口。
