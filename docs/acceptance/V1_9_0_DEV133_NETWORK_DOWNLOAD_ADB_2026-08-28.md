# v1.9.0-dev.133 网络下载与 ADB 安装链验收

## 目标

Harness 接收网络 APK URL 后，不借助 shell、浏览器或系统 ADB，使用 Vibekits 工具完成下载、校验、安装和设备侧验证。

## 接口

1. `vibekits.network.download`
   - 必填：`url`
   - 可选：`fileName`、`outputDirectory`、`overwrite`、`expectedSha256`、`timeoutSeconds`、`maxBytes`
   - 返回：`outputPath`、`bytes`、`sha256`、`statusCode`、`finalUrl`、`artifactType`、`elapsedMs`
2. `vibekits.adb.connect/list_devices/install_apk/shell`
   - 下载返回的 `outputPath` 直接作为 `install_apk.apkPath`，不要求用户重复输入路径。
   - `install_apk.allowDowngrade=true` 只显式追加标准 `-d`；若设备仍拒绝，禁止自动卸载和清除应用数据。

## 自动验证

- 有效 APK 容器：流式下载、大小与 SHA-256 一致、最终文件唯一存在。
- 无效 APK/HTML 错误页：拒绝，并且下载目录不残留 `.part` 文件。
- Harness 工具目录：接口可发现，审批后真实写入所配置目录。
- `network_download_service_test.dart` 与 `harness_tool_bridge_test.dart`：27/27 通过。

## 真实环境记录

- URL：`https://cdn.newlink-sz.com/Common/upgradefile1786777913543_KEMI-PAD.apk`
- 目标：`192.168.3.53:5555`
- Harness 已真实调用 `network.download`，下载成功并返回本地路径；随后连接 53、枚举为 `device` 并调用 `adb.install_apk`。
- 首次安装由设备返回 `INSTALL_FAILED_VERSION_DOWNGRADE`，没有伪造成功。该真实失败推动 `allowDowngrade` 接口补齐；最终重试结果见本轮后续记录。

## dev.134 最终闭环

- Harness 第二次真实执行：`network.download → adb.connect → adb.list_devices → adb.install_apk`，全过程没有调用 shell、PowerShell、curl、浏览器或系统 ADB。
- 下载：HTTP 200，`24,729,270` 字节，SHA-256 `b398cb2cc9cdd53361a0b2baa8397ad4faa93603340ebac5095d6c8ce792a245`，`artifactType=android-apk`，下载约 7.3 秒。
- 设备：`192.168.3.53:5555`，`state=device`，`model=huanglong`，`product=hi3781v730_tablet`。
- 安装：Harness 传入 `replace=true, allowDowngrade=true`；内置 ADB 实际参数为 `install -r -d <downloaded-apk>`，返回 `Performing Streamed Install / Success`，退出码 0，耗时约 3.8 秒。
- 工具调用记录已真实写入 `tool_activity.json`，可在对应工具的 Harness 记录中查看和删除。结论：真实下载与 53 设备覆盖/降级安装闭环通过。
