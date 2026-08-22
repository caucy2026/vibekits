# V1.9.0-dev.69 Android 真机与 macOS 构建验收

日期：2026-08-22
版本：`1.9.0-dev.69+79`

## Android 真机

- 设备：`huanglong`，`192.168.3.63:5555`
- 系统：Android 12 / API 31
- ABI：arm64-v8a
- 屏幕：1920×1280，320 dpi
- APK：`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
- APK 大小：60.6 MB
- SHA-256：`C0660E6FEEC3ED514E9D6D6FE7EB75D46BD64FEA86F888143D5899CF09F7240E`
- 安装：`adb install -r` 成功，设备包版本 `1.9.0-dev.69`。
- 三次 Release 冷启动：734 ms、692 ms、721 ms，平均 716 ms。
- 稳定后内存：TOTAL PSS 104123 KB，TOTAL RSS 241356 KB，无 Swap。
- 退出检查：`am force-stop` 后 `pidof com.vibekits.vibekits` 无残留。

本轮移动端优化：

1. Android/iOS 不启动仅供桌面使用的 Harness MCP 本地服务。
2. Android 不注册 Windows 文件关联、不订阅 Windows/macOS 拖放通道。
3. 移动端切换模块时仅保留当前重型工作区，避免 OCR、解压和数据库页面持续累积内存。
4. 窄屏主导航改为图标模式，并保留 Tooltip 与语义标签。
5. Android 模型页默认进入可用的本地 OCR，不探测无法执行的桌面 Harness Runtime。
6. Android 构建限制为 3 GB Gradle Heap、2 个 Worker；Gradle 缓存迁到项目 D 盘隔离目录，避免 C 盘空间不足拖慢系统。

## macOS

Windows 主机执行 `flutter build macos` 时，Flutter 不提供 macOS 构建子命令；Xcode、codesign 和 macOS SDK 只能运行在 macOS。

已增加 `.github/workflows/macos-release.yml`，固定 Flutter 3.47.0，在 `macos-14` Runner 上执行真实的：

1. `flutter pub get`
2. `flutter build macos --release --no-pub`
3. `ditto` 打包 `.app`
4. 生成 SHA-256
5. 上传 14 天保留的构建产物

这属于未签名 Release 构建验证；正式分发仍需 Apple Developer ID、签名和 notarization。
