# v1.9.0-dev.79 Android UI 与局域网 Harness Key 验收

## 本次完成

- Android 一级工作区改为 Material 3 底部导航，标签只显示当前项；桌面继续保持侧栏/紧凑顶部导航。
- 系统返回键和返回手势优先按工作区访问历史返回，历史为空才退出 APP。
- 手机工作区取消桌面圆角卡片、阴影、外边距和桌面状态栏，内容利用完整触控空间。
- 手机只挂载当前重型工作区，切换后释放隐藏页，避免移动端内存持续增长。
- Harness API Key 支持同局域网二维码输入：扫码设备打开临时网页，粘贴 Key 并确认，安卓端自动接收和持久化。
- Android 凭据由 Android Keystore 生成不可导出的 AES 密钥，以 AES-GCM 加密保存；普通设置和日志不保存明文。
- 模型、工具下载及 Harness 调试目录改为 Android 应用 files/cache 沙箱。

## 二维码安全边界

1. 二维码只包含私有 IPv4、随机端口和 256-bit 一次性令牌，不包含 API Key。
2. 只接受精确路径和令牌；错误令牌返回 404。
3. 请求体最大 8 KiB，Key 最大 4096 字符并拒绝换行。
4. 成功接收一次后立即关闭 HTTP 服务；未使用时五分钟自动过期。
5. 页面禁止缓存、外部资源、引用来源和跨站 form action。
6. 局域网页面使用 HTTP，产品明确限制在可信 Wi-Fi；公共网络下应改用手机键盘直接粘贴。

## 自动验收

| 项目 | 结果 |
|---|---|
| 页面 GET、表单 POST、Key 回传 | 通过 |
| QR/URL 不包含 Key | 通过 |
| 错误令牌拒绝 | 通过 |
| 定向 Dart/Flutter 静态分析 | 0 问题 |
| Android arm64 Release 构建 | 通过，108.1 MB |

构建产物：`build/app/outputs/flutter-apk/app-release.apk`。

## Android 全功能 review 结论

当前已适合 Android 的能力：底部导航、系统返回、文件选择、压缩/文档的 Flutter 主流程、本地 OCR、纯 Dart 计算转换、Key 配置和应用沙箱目录。

仍需逐项移动化或改为桌面节点调用：Windows 系统清理、ADB host、串口、依赖外部二进制的 Git/SSH、Mihomo 系统代理、QEMU 虚拟机、官方桌面 Node/DSH Web。它们不能仅凭 APK 可编译标记为 Android 功能完成。

## 已知测试说明

局域网 Key 专项 2/2 通过。全量历史 `widget_test.dart` 在若干文件拖入/OCR 用例出现既有持续动画导致的 `pumpAndSettle` 超时，本轮未修改这些用例，也未把它们记录为通过；后续移动 UI 专项需用固定帧推进替代无界等待。
