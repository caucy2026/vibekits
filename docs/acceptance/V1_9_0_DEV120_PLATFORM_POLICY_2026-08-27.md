# v1.9.0-dev.120 多平台存储与清理验收

## 自动化

- Windows/macOS/Android 存储路径合同：3/3 通过。
- 三平台清理能力、目标隔离和删除边界：6/6 通过。
- 设置迁移：旧位置的 SSH/ADB 历史迁移到新持久位置并可重新读取。
- 清理 UI、设置和 Harness 平台信息等定向回归合计 50 项通过。
- 目标文件 Flutter Analyze：0 问题。

## Windows 本机只读实测

- 使用 APP 的真实目标发现器和决策引擎扫描当前 Windows 环境，不删除文件。
- 21 秒检查出 89,143 个候选，共 6.494 GiB。
- 自动安全项 582 个 / 1.320 GiB；建议项 46,958 个 / 4.358 GiB；需复核项 41,603 个 / 0.815 GiB；受保护误删 0。

## Android `.63` 真机实测

- 使用 APP 内置 ADB 连接 `192.168.3.63:5555`，设备在线。
- dev.120 release APK 已安装并启动，实际版本为 `versionName=1.9.0-dev.120`、`versionCode=130`。
- APP 实际显示并使用以下沙箱位置：
  - 设置：`/data/user/0/com.vibekits.vibekits/files/Vibekits/settings.json`
  - 缓存：`/data/user/0/com.vibekits.vibekits/code_cache/Vibekits`
  - 凭据：Android Keystore
- 在真机进入系统清理并执行扫描：完成 0 项、不可读取 0 项、无崩溃、未删除内容；UI 明确说明只处理 Vibekits 私有缓存和调试数据，保护共享存储、Download、系统与其他 APP。
- 通用 APK 因旧版 ABI 分包的 `versionCode=2128` 高于通用包 `130`，本次保留数据安装使用了 Android 的降级覆盖参数。后续 ARM64 ABI 正式分包构建尝试因本机缺失 Flutter 32 位/x86 构件且网络连接重置、继而 Gradle 挂起而未完成；正式发布升级链路仍须以 `versionCode>2128` 的签名 ARM64 包复验，不能将此项写为通过。

## 环境边界

- 当前执行机不是 macOS，因此 macOS 完成规则发现、路径、Trash 边界仿真，尚未声称 Keychain 和真实文件系统调用通过。

## macOS 仿真与云端编译门禁

- Windows 本机以纯 Dart 合同测试模拟 macOS 环境变量、`~/Library` 路径和 Trash 删除边界。
- `.github/workflows/macos-release.yml` 在 `macos-14` 上依次执行依赖解析、目标代码 Analyze、平台策略测试和 unsigned Release 编译。
- 产物版本从 `pubspec.yaml` 自动读取，不再使用旧的 `dev.69` 固定名称；云端构建通过才视为“macOS 编译通过”，本报告不将仿真等同于真机功能验收。
