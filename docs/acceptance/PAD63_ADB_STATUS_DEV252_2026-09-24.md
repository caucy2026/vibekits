# PAD63 后台 ADB 状态修复验收（dev.252）

问题：主界面退出后，最小 MCP 状态工具曾固定回复“远程 ADB 可连接”，即使 5555 失联也可能误报。现在每次调用在服务进程内探测 `127.0.0.1:5555`，返回 `serviceReady` 和真实的 `adbReady`；未就绪时提示正在恢复。

正式证书签名的 APK `1.9.0-dev.252+2252`，SHA-256 `0b4e54e6212c56f7f4ad376c6c3b22825ad29de7c54dad859f4101823ddba7f6`，证书 SHA-256 `c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8`。PAD63 覆盖安装成功，重启后未打开应用主界面，设备 ID `6795854383` 连接返回 `toolCount=1`、`mcpReady=true`、`adbReady=true`；仅后台服务进程存在，远程 ADB 实际读到 `versionCode=2252`、`service.adb.tcp.port=5555`、`init.svc.adbd=running`。最小状态工具实际返回 `{"serviceReady":true,"adbReady":true}`。

以本机 ADB 临时将 TCP 端口设为 `-1` 并重启 adbd 后，后台服务恢复 5555；下一次状态调用已经返回 `adbReady=true`。由于恢复速度快于控制端调用，本轮未捕获 `adbReady=false` 的瞬态；因此“未就绪时正确显示 false”目前是代码检查结果，尚不是实机正向断言。该缺口不应被本次正常状态测试覆盖。

本次只修改 Android PAD 最小状态端点及版本号；桌面代码没有变化。其他发布缺口见 `PAD_TWO_DAY_REQUIREMENTS_AUDIT_2026-09-24.md`，总体仍为 **BLOCK**。
