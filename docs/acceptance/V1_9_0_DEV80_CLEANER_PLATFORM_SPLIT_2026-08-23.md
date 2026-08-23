# v1.9.0-dev.80 清理算法平台拆分验收

日期：2026-08-23

## 完成项

- Windows、macOS、Android 目标发现改为互斥分派。
- Windows 规则资产仅在 Windows 加载，后台解析再次验证平台。
- Android 只扫描/删除 Vibekits 私有 cache、tmp 和 Harness 调试目录。
- macOS 使用独立规则目录和 Trash 语义，谨慎规则保持人工确认。
- 决策层与删除层都有平台越界保护；非 Windows 禁止复用 Windows 全盘分析。
- Gradle 缓存由文件级自动清理改为完整旧版本目录、30 天、默认不选，防止产生半套缓存。

## 自动证据

- `flutter test test/cleanup_platform_policy_test.dart test/cleanup_targets_test.dart test/cleanup_background_runner_test.dart test/cleanup_deleter_report_test.dart test/cleanup_decision_engine_test.dart`：37 项通过。
- `flutter analyze`：No issues found。
- 使用项目隔离 `GRADLE_USER_HOME` 完成 `flutter build apk --release --target-platform android-arm64`，产物 `build/app/outputs/flutter-apk/app-release.apk`（113,319,934 bytes），SHA-256 `874391E070D0B4592264CA91BFECCD28C71044AD740C83AD383AA1436CF3E5AB`。
- Android 私有缓存真实临时文件删除成功；同级越界文件保持存在。
- 注入同时含 Windows/macOS/Android 环境变量后，各平台只发现自身目标。

## 未冒充完成

macOS APFS 全盘分类、macOS 应用清单和 Android PackageManager/StorageStats 仍需要对应原生适配与实机证据，因此当前保持禁用，绝不回退到 Windows 算法。
