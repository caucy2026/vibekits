# PAD Android 代理、扫码与远程 ADB 验收（dev.243）

日期：2026-09-24。目标 PAD75（Android 12，设备 ID `9464730211`）；主程序 `com.vibekits.vibekits`，`1.9.0-dev.243+2243`。

## 需求与实现边界

- 网络代理：Android 主包只保留管理界面和 Binder 客户端；可选的 `com.caucy.vibekits.component.network_proxy` 独立签名 APK 携带 arm64 Mihomo 核心，按商城的 HTTPS、精确字节、SHA-256、包名、版本及签名校验后安装。首次使用时从应用中心获取，不把约 21 MB 核心塞进默认主包。
- 启用时由系统 UID 辅助组件写入 Android 全局 HTTP 代理；先检查核心实际运行以及 `ConnectivityManager.defaultProxy` 生效，关闭时停止核心并精确恢复先前的系统值。此能力覆盖遵循系统 HTTP 代理的应用，不等同于全流量 VPN/TUN。
- “手机扫码输入订阅地址”显示一次性局域网二维码，手机浏览器提交 HTTPS 订阅 URL 后回填 PAD 输入框；二维码不包含订阅内容或密钥。
- 仿真开启流程先由平台签名、系统 UID 的小型辅助 APK 请求启动本机 `adbd` TCP 5555，确认回环端口就绪后才开放设备 ID 隧道。远程控制端不需要同一局域网 IP。主包维持普通 UID；签名自身不等于系统 UID。

## 已完成的真机与自动化验证

- PAD75 覆盖安装主程序和组件成功。主程序 APK：86,829,797 字节，SHA-256 `67c74155eb2daaa0f709c0534e2d7f1c8fe24422f9bc61ecb8aa9a0856ee06f6`。组件 APK：21,783,660 字节，SHA-256 `2a7443854b66ab2cb3db8b8c78f00b9d20e47f54a4b752efa6b2cdd51ad4ca61`。两包 APK v2 签名有效，证书 SHA-256 均为 `c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8`。
- 首次组件包因 Gradle 增量缓存漏打 `ProxyRuntimeService` 真机崩溃；构建脚本现强制 `clean`，并检查 dex 包含该服务。修复后的组件在 PAD75 覆盖安装成功，包版本为 1。最终构建又补了 Android 24–25 的通知兼容分支。
- 真机导入仅用于测试的 DIRECT 配置后，Binder 启动 Mihomo，PAD 端回环代理监听成功；控制端通过 ADB 端口转发向 `https://example.com` 发起 HTTP CONNECT，收到 200 和上游 HTTP/2 200。关闭后核心退出、监听端口消失，原先为 `null` 的 `Settings.Global.HTTP_PROXY` 恢复为 `null`；测试配置已删除。
- PAD75 点击扫码入口，手机端方式通过二维码提供的一次性地址提交测试 HTTPS 订阅 URL，PAD 输入框自动回填；取消后未保存测试订阅。重复/错误令牌、Harness Key 原有流程及订阅流程的自动化测试通过。
- PAD75 已安装系统 UID 辅助组件 v4，实测 UID 1000。仿真开关开启后，以设备 ID `9464730211` 通过 VibeKits P2P/中继控制协议取得远端 ADB 隧道 `127.0.0.1:56288`，执行 `getprop ro.product.model` 返回 `huanglong`。测试完成已关闭该隧道。
- `app_center_test.dart`、`lan_harness_key_receiver_test.dart`、`harness_simulator_target_runtime_test.dart` 共 41 项通过。主包与组件分别按正式平台证书签名；未使用无签名 APK。

## 尚未满足的发布与冷态门禁

- 还没有在“全新 PAD、原本关闭 ADB、尚未安装辅助组件”状态下，仅靠用户开启仿真，再以设备 ID 建立远程 ADB 的完整闭环。现有证据覆盖已安装辅助组件的运行中断线恢复（PAD63 既往实测）和 PAD75 的设备 ID 远程 ADB。不能把这些替代为首装冷态验收。测试前必须预置独立救援，以免关掉唯一的 ADB 连接。
- 商城主程序 dev.243 和网络代理组件尚未完成开发者记录、公开详情、CDN 校验和商城内实际安装。没有这些证据不能写“正式发布完成”。
