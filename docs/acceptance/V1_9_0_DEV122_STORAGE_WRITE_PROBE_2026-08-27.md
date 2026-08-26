# v1.9.0-dev.122 客户端存储可写门禁

## 实现

- 使用各平台官方应用支持、应用缓存、临时目录和文档目录 API，不再只依赖环境变量推导。
- APP 启动前逐一验证设置、模型、下载、缓存和 Harness 调试目录可创建、可写、可读、可删除。
- Windows 安装目录不可写时自动将 Harness 调试目录切换到用户缓存。
- 持久目录优先回退到用户文档；仅在全部持久位置不可写时使用临时应急目录并显示警告。
- 设置界面和 Harness `platform.storageLocations.access` 同时暴露实际路径、可写状态和降级原因。

## 自动化

- 路径解析和不可写降级：6 项通过。
- 设置迁移、三平台清理边界、清理 UI 与 Harness 能力回归：47 项通过。
- 目标代码静态分析：0 问题。

## 编译门禁

- Windows Release：通过，`build/windows/x64/runner/Release/vibekits.exe`。
- Windows 冷启动：进程正常响应；设置、缓存、本地模型、Harness 调试目录均创建成功；写探针残留 0。
- Windows 实际设置目录：`%APPDATA%\com.vibekits\vibekits`；缓存：`%LOCALAPPDATA%\com.vibekits\vibekits`；模型继续使用 `%LOCALAPPDATA%\Vibekits\Models`，不会进入漫游配置。
- Android ARM64 Release APK：通过，`build/app/outputs/flutter-apk/app-release.apk`，110.2 MB。
- macOS unsigned Release：GitHub Actions `33024241863` 通过；依赖解析、平台集成 Analyze、存储与清理策略测试、Release 编译、压缩校验和及产物上传全部成功。
- macOS 构建记录：<https://github.com/caucy2026/vibekits/actions/runs/33024241863>。
