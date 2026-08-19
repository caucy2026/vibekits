# v1.9.0-dev.42 Android 真机验收

日期：2026-08-20

## 验收结论

Android arm64 Release APK 已在 `192.168.3.63:5555` 真机完成构建、安装、冷启动、热恢复和实际界面操作，核心移动端入口验收通过。

本次结论只覆盖 Android 基础运行与已验证的纯 Flutter 工具，不把 Windows 专属的 DSH/Harness、内置 ADB、MinGit、Mihomo、QEMU 等桌面运行时写成 Android 已完成。

## 设备与产物

- 设备：`huanglong`
- Android：12
- ABI：`arm64-v8a`（设备同时声明兼容 armeabi-v7a/armeabi）
- ADB：项目 Windows Release 随包 `tools/adb/adb.exe`，无线目标 `192.168.3.63:5555`
- 包名：`com.vibekits.vibekits`
- 版本：`1.9.0-dev.42`，versionCode `52`
- minSdk：24；targetSdk / compileSdk：36
- APK：`build/app/outputs/flutter-apk/app-release.apk`
- 大小：112,085,172 bytes
- SHA-256：`947F794C97D7EE265E3CAABA5196255567B4C428E02DD3B0FDCE9947C63CF950`

## 真实闭环

1. 使用官方 Android command-line tools 安装 platform 36、build-tools 36.0.0 和 NDK 28.2.13676358。
2. Release APK 构建成功，通过 `aapt` 复核包名、版本、SDK 和 INTERNET 权限。
3. 通过随 App 发布的 ADB 连接目标，清除且仅清除测试包数据，重新安装返回 `Success`。
4. 冷启动 `MainActivity`：`Status: ok`，TotalTime 793 ms，WaitTime 802 ms。
5. 首次 Android 启动进入可工作的“开发工具”，不等待桌面专属 Harness Web 运行时；底部版本为 `v1.9.0-dev.42+52`。
6. 在真机程序员计算器输入 `255`，界面实际返回 DEC `255`、HEX `FF`、OCT `377`、BIN `1111 1111`。
7. HOME 后恢复为 HOT launch：TotalTime 119 ms，WaitTime 122 ms。
8. 前台 Activity 为 `com.vibekits.vibekits/.MainActivity`；本轮 logcat 未发现 FATAL EXCEPTION 或 ANR。
9. 运行时内存快照：TOTAL PSS 117,626 KB，TOTAL RSS 254,704 KB。
10. `flutter analyze`：No issues found。

定向测试收尾时发现主机 Flutter SDK 的全局 Pub 缓存缺失 analyzer/archive 源文件；`pub cache repair` 重装 91 个包后 SDK 源码模式仍失败。该主机工具链问题发生在 APK 构建、静态分析和真机验收之后，不改变已记录的设备证据，但后续完整测试门禁前必须修复 Flutter SDK 缓存并重跑。

## 构建问题闭环

- 补齐 Android 工程和 INTERNET 权限。
- JDK 固定为 17，构建工具使用可复现的本地 Android SDK 目录。
- 禁用 Kotlin 跨盘增量缓存，避免 Windows 不同盘符造成缓存根路径错误。
- sqlite3 Android arm64 原生资产按上游版本和 SHA-256 固定后进入构建缓存。
- 增加 `tool/prepare_android_build_environment.ps1`，统一检查 Java、SDK、平台、构建工具和 NDK。
- 修正 App 内展示版本与 `pubspec.yaml` 不一致的问题。

## 证据

- 首次启动：`build/acceptance/android-v1.9.0-dev.42-first-launch.png`
- 计算器实际输入：`build/acceptance/android-v1.9.0-dev.42-calculator.png`

## 未越界声明

- Android 版目前不包含桌面 DSH Web/Node Harness 运行时；移动端 Harness 需要单独的移动架构或远端服务设计。
- Windows/macOS 专属系统工具不会因为 APK 能启动而自动成为 Android 能力。
- 本次没有执行破坏性设备操作、系统设置修改或文件删除。
