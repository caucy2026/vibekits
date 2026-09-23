# 2026-09-23 改动记录与云端备份范围

本记录对应当前 VibeKits 工作树从 `9a6ed3045c144c93c406d8fdc00963510a6cf80d` 之后尚未归档的源码、测试和验收文档。测试包不是商城正式发布包；本次云端备份只保存可重建的源码与记录，不上传 APK、ZIP、构建缓存、设备私有数据、凭据或密钥。

| 范围 | 本日改动 | 验证与现状 |
| --- | --- | --- |
| Harness 会话 | 派生会话交接、摘要入口、来源关系、删除入口及刷新；修复 PAD 默认工作区会话启动时未读取、未加载完成时可能把旧聊天覆盖为空。 | Mac 隔离试用与回归见 `DEV227_CONTINUATION_SUMMARY_DELETE_2026-09-23.md`；PAD63 dev232 真机新建会话后强制结束、重启，侧栏与正文恢复。原打地鼠聊天在修复前已经为空，不能还原原文。 |
| Harness 显示与交互 | 推理过程、Key 检测、模型名称、运行时状态与输入区修正；Windows/macOS 共存端口、版本和会话入口相关调整。 | `test/deepseek_harness_test.dart` 34 项全过，修复文件静态分析 0 issue；Windows dev228 结果和未通过的远程命令见 `DEV228_WINDOWS_HARNESS_2026-09-23.md`。 |
| PAD 双屏和原生游戏 | Harness 留在 display 0；PAD 本地打地鼠构建桥安装后把 APK 启动在 display 2；增加每次锤击及命中裂纹效果。 | PAD 本机资源编译、Java、DEX、打包、签名、验签、安装、第二屏启动八步均退出码 0；两屏 Activity 同时 RESUMED。此轮触发来自设备控制端，Harness 再次发起完整构建仍待验。 |
| PAD 远程 ADB | 加入同证书 system UID 的可选 ADB 辅助组件和主 App 引导、恢复状态机；跨屏键盘经 KBoard IPC。 | PAD63 adbd 被停止后曾自动恢复；跨网、关闭撤销与重启后的整条链仍未验满，六项 PAD 总验收保持 BLOCK。见 `PAD63_CROSS_DISPLAY_KEYBOARD_REMOTE_ADB_2026-09-23.md` 和 `PAD63_HARNESS_REASONING_NATIVE_GAME_2026-09-23.md`。 |
| PAD 仿真开启密码与关闭路径 | Android PAD 手动开启需输入默认 `2580`；错误密码在原位提示且不授权。修复 Android 关闭仿真时误调用桌面 SSH 密钥撤销。 | dev.237 在 PAD63 真机通过错误/正确密码、开启后强制 HBBR 远程 ADB；关闭测试保留了网络 ADB 保护，不等于真实断链验收。详见 PAD63 远程 ADB 文档。 |
| PAD 代理订阅 | Android 订阅入口增加扫码、HTTPS 地址校验和提交前确认；Android 页面只提供订阅管理。修复初始化误等待桌面 QEMU/Mihomo 探测导致 PAD 页面持续转圈；扫码前申请相机运行时权限。 | 无 Android Mihomo/VpnService 核心，页面明确提示“不会修改系统网络”，不能宣称 PAD 代理已生效；订阅 URI 单元测试通过。 |
| 应用中心与可选组件 | 平台适配、组件包验证和下载/安装逻辑及相关测试；侧栏编号移除。 | 源码和专项测试随本次归档；不把未完成的平台真机/商城测试写成发布通过。 |

备份目标为既有 GitHub 仓库 `caucy2026/vibekits` 的 `main`，使用项目记录过的 `ssh.github.com:443` 入口做普通 fast-forward push，并以远端 `refs/heads/main` SHA 与本地提交 SHA 相等为完成标准。明确排除 `.codex-artifacts/`、`android/build/`、`dist/`、`700`、`700.pub`、运行日志、截图和签名产物。
