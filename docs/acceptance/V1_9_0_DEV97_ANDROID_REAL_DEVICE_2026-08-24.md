# v1.9.0-dev.97 Android 真机全模块验收

## 验收环境

- 日期：2026-08-24
- 设备：`huanglong` / Android，ADB `192.168.3.62:5555`
- 布局：1920×2560 连续双屏画布（D2 上半区 + D0 下半区）
- APK：`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
- 版本：`versionName=1.9.0-dev.97`，`versionCode=2107`
- SHA-256：`9194CEA15DCEBF337B745BF9942AD55294728F0E6F7E048D174D202FF0683B48`

## 本轮修复

1. Android/iOS Harness 改为原生移动端调用链，不再把 Windows Node/DSH 运行时作为启动条件。
2. Android 工作区默认位于 App 私有目录，不依赖 Windows 路径。
3. Android 清理器只扫描/删除 Vibekits 自己的 cache/tmp、Harness 日志和调试截图，不进入系统目录和其他 App 数据。
4. 开发工具中的 Clash/Mihomo、QEMU、ADB、串口、Git 等桌面运行时在 Android 显示平台说明，不再在 PageView 预构建时启动 Windows 二进制。
5. 新增 Android `libvibekits_onnx.so`，动态使用 APK 内置 `libonnxruntime.so`；PP-OCRv6 不再被“仅支持 Windows”拦截。

## 真机结果

| 模块 | 操作 | 结果 | 证据/边界 |
|---|---|---|---|
| 冷启动 | 强制停止后启动 Release | 通过 | `MainActivity` 591 ms 显示，全画面 875 ms |
| Harness | 进入工作区 | 通过 | 显示“Harness 就绪”，不再提示运行时缺失/损坏 |
| Harness 发送 | 输入 `AndroidHarnessSmoke` 并发送 | 边界通过 | 当前真机未配置 Key，立即提示“请先点右上角设置并填写 DeepSeek API Key”；不启动 DSH，不退出 |
| PP-OCRv6 | 安装内置模型 | 通过 | 显示“已安装”并逐文件校验 |
| PP-OCRv6 | 选择真机 PNG 并执行本地识别 | 通过 | 真实 ONNX 推理返回 15 行文字，无上传 |
| 清理 | 进入 Android 安全清理、扫描 App 私有目标 | 通过 | 页面和进程保持；本次可清理候选为 0，因此未执行删除动作 |
| 解压缩 | 进入模块 | 通过 | 平台页面正常，进程未切换 |
| 文档阅读 | 进入模块 | 通过 | 页面正常，无自动网络启动 |
| 开发工具 | 打开计算器、QEMU 和资源诊断 | 通过 | QEMU 在 Android 为可解释的桌面节点；未启动 Windows EXE |
| 资源诊断 | 真机采样 | 通过 | CPU 15.2%，8 逻辑核；内存 42.0%，可用 3.2/5.5GB；GPU 无统一计数器时明确显示未取得 |
| 双屏退出 | 点击上屏退出 | 通过 | 两屏的 `MainActivity` 同时消失，随后重启正常 |
| 崩溃日志 | 全过程查找 `FATAL EXCEPTION` / `Fatal signal` / `E/flutter` | 通过 | 未发现致命记录 |

## 证据文件

- `build/acceptance/dev97/ocr-result-d2.png`
- `build/acceptance/dev97/harness-ready.png`
- `build/acceptance/dev97/harness-key-guard.png`
- `build/acceptance/dev97/resources.png`
- `build/acceptance/dev97/qemu-gate.png`
- `build/acceptance/dev97/documents.png`

## 未伪造的环境门禁

- 真机没有配置 DeepSeek API Key，所以本报告不声称已取得真实大模型回答；已验证原生移动 Harness 就绪和缺 Key 的立即反馈。
- 本次清理扫描没有发现候选，不为追求“删除通过”而在 Release 私有目录注入后门测试文件。
- Release APK 已完整构建成功。定向 `flutter analyze` 被本机 `C:\Users\caucy\AppData\Roaming\.dart-tool` 遥测文件权限卡住后中止，未在本报告中写成“Analyze 0 问题”。
