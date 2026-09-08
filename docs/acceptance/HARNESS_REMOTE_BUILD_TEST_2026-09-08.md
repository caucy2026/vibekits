# 远程 Harness 编译与测试记录

## 本轮已验证

- 新增 12 个远程模块运行 Dart 静态分析：No issues found。
- `flutter test --no-pub test/harness_remote_adapter_test.dart test/harness_remote_commands_test.dart test/harness_remote_sync_test.dart`：16/16 通过。
- 包含本机真实 HttpServer/WebSocket 回环适配测试（对端为协议 fixture，非生产 DSH）、回执 rpcId 校验、实际 HTTP 调用次数、撤销授权、事件范围隔离、日志溢出恢复和原有去重/同步测试。
- `192.168.3.63:5555` ADB 在线；这只证明设备可达，不代表远程 Harness 功能通过。

## 构建

- 固定 SHA256 的 GitHub CLI 2.100.0 双架构依赖已补齐。
- 默认 build 目录受并发 Xcode 构建数据库锁影响，本轮改用独立 DerivedData `/private/tmp/vibekits-remote-build.ZFll2U`。
- 执行 `xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Release -derivedDataPath /private/tmp/vibekits-remote-build.ZFll2U -quiet build`：exit 0，构建成功。
- 候选 `/private/tmp/vibekits-remote-build.ZFll2U/Build/Products/Release/Vibekits.app`；主程序 `lipo -archs` 为 x86_64 arm64，`codesign --verify --deep --strict` exit 0。此检查不等于 Apple 公证；也不等于全部内置运行库已通过双架构与 macOS 12 兼容性验收。
- 候选 Info.plist 版本 1.9.0.160，包含工作树上其他任务同时进行的版本变更。本轮没有自行递增版本、提交发布或覆盖正式包。

## 不可扩大解释的边界

没有做远程 UI、63 端命令、TLS 配对或中继端到端验收。新模块尚未接入正式页面，普通 App 编译也不能证明这些代码已在 UI 中执行。没有覆盖 bin 或发布商店。工作树同时存在其他任务的启动修复/版本变更，未覆盖这些改动；本报告不将它们记为本轮实现。
