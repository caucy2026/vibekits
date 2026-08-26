# v1.9.0-dev.121 macOS 编译门禁

## 修复

- Windows 路径仿真不再调用宿主系统的 `File.parent`，改为同时识别 `/` 和 `\\` 的平台无关父目录解析。
- 修复 macOS runner 把 `D:\\Apps\\Vibekits\\vibekits.exe` 当成普通文件名，导致 Windows 存储合同测试失败的问题。
- macOS 云端工作流从 `pubspec.yaml` 自动读取产物版本，并在编译前执行 Analyze 与平台存储、清理、设置迁移测试。

## 验收口径

- Windows 本机仅做 macOS 策略仿真和静态编译检查。
- GitHub `macos-14` runner 的 `flutter build macos --release` 成功才记录为 macOS 编译通过。
- 不把 unsigned 编译通过等同于签名、公证或 macOS 真机功能通过。

## 云端结果

- GitHub Actions run：`33022087516`。
- Resolve dependencies：通过。
- Analyze macOS platform integration：通过。
- Test macOS storage and cleanup policy：通过。
- Build unsigned macOS Release：通过。
- Package/checksum 与 artifact 上传：通过。
- 结论：`v1.9.0-dev.121+131` 已确认 macOS 编译通过；签名、公证与真机交互不在本次仿真验收范围。
