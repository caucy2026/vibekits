# v1.9.0-dev.67 ADB 语义工具与真机验收

日期：2026-08-22
设备：`192.168.3.63:5555` / `huanglong` / `hi3781v730_tablet`

## 实现范围

Harness 新增六个独立能力：Android Shell、有界 Logcat、安装 APK、推送文件、拉取文件、保存设备截图。它们由 `VibekitsHarnessToolBridge` 注册，使用随 Release 发布的 ADB，经过同一权限策略并写入对应工具活动日志。文件输入输出采用绝对路径；覆盖必须显式声明；设备端路径只能使用 Android 绝对路径。

## 自动测试

- `test/harness_tool_bridge_test.dart`：六个语义接口全部成功，核对八次底层参数调用。
- `test/adb_semantic_live_test.dart`：仅在显式提供 `VIBEKITS_LIVE_ADB_TARGET` 时运行，防止普通回归误操作设备。

## 真实设备结果

执行入口：

```text
flutter test --no-pub --dart-define=VIBEKITS_LIVE_ADB_TARGET=192.168.3.63:5555 test/adb_semantic_live_test.dart --reporter expanded
```

结果：

- 连接与枚举：通过，状态 `device`。
- Shell：`getprop ro.product.model` 返回 `huanglong`。
- Logcat：读取 3,441 字节的有界快照。
- 文件往返：推送后再拉取，38 字节逐字节一致。
- APK：隔离 Gradle 缓存构建出 161.7 MiB Release APK，由 `vibekits.adb.install_apk` 在真机安装成功。
- 截图：最终 APK 重编后的完整复验生成 `build/acceptance/adb-semantic/screenshot-1787339468031644.png`，大小 4,434,048 字节。
- 远端临时文件：验收结尾通过语义 Shell 删除。

## 未关闭项

- 无线配对码、持续 Logcat 的停止/释放、未授权/离线设备及 APK 签名冲突矩阵不包含在本次完成声明内。

结论：ADB 的 APK 安装、常用只读、文件和截图主链路已经由 APP 自己的 Harness 工具真实调用并闭环；扩展矩阵继续受上述门禁约束。

## 发布构建

- Android：最终 `build/app/outputs/flutter-apk/app-release.apk` 构建成功，161.7 MiB，并由上述 Harness 接口再次安装通过。
- Windows：`build/windows/x64/runner/Release/vibekits.exe` 构建成功；`verify_windows_bundle.ps1` 确认版本 `1.9.0-dev.67+77`、内置 Git `2.55.0.windows.3` 和 25 项必需运行时。
- 静态分析：`flutter analyze --no-pub` 为 0 issue。
- 自动回归：ADB service、Harness bridge、ADB workspace 和开发工具 Widget 共 39 项通过；真机用例另计 1 项通过。
