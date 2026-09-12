# VibeKits dev.187 PAD 协同会话与 KEMI 商场发布验收

日期：2026-09-11
版本：`1.9.0-dev.187+2187`

## 1. 修复范围

- 协同控制会话改由进程级 `HarnessRemoteControllerRuntime` 持有，关闭高级设置页不再中断 P2P/中继连接。
- macOS 官方 Harness 工作区和 Android/PAD 原生 Harness 工作区共用同一远端会话投影、命令输入、停止和断开能力。
- 主界面状态优先读取真实控制会话，连接成功后显示绿色“协同已连接”，不再因旧链路快照误显示“协同连接中”。
- 远端项目文案改为“项目状态已同步”，避免把具备命令能力的协同界面误称为只读。
- Windows Release 增加内置 `vibekits-harness-relay.exe` 强制打包门禁；缺失时构建必须失败，禁止发布只有界面、没有传输引擎的包。

## 2. 自动测试

- `flutter analyze --no-pub`：通过。
- 重点回归 55 项通过，覆盖控制会话、协同设置、PAD Harness、官方 Harness 和主界面。
- 默认并行完整套件共运行 829 项，唯一一次失败是 OCR 截图回调在全并发压力下超时；该用例隔离连续 3 次均通过。
- 最终以单并发重新运行全部套件：830 项通过、18 项按环境条件跳过、0 失败，耗时 2 分 22 秒。

## 3. PAD 75 到 macOS 真机业务闭环

- PAD：`192.168.3.75:5555`，`huanglong`。
- Android 包：`/private/tmp/Vibekits-dev187-2187-pad75-signed.apk`。
- APK 使用项目授权 keystore 签名，v2/v3 签名均通过；采用 `adb install -r --no-incremental` 覆盖安装，保留用户数据。
- macOS 被协助端统一 ID：`1554650784`；中继在线、注册密钥确认、可调用状态均为真。
- PAD 关闭设置页后，主界面持续显示绿色“协同已连接”，展示远端 `harness` 项目、18 个会话、READY 状态以及发送、停止远端任务、断开操作。
- PAD 主界面真实发送 `Reply only: REMOTE_OK. Do not call tools.`；macOS Harness 返回 `REMOTE_OK`，界面收到完整反馈，证明不是只显示在线状态。
- 截图：`/private/tmp/vibekits-pad75-dev187-notarized-mac-main.png`、`/private/tmp/vibekits-pad75-dev187-command.png`。

## 4. macOS 正式包

- App：`/Volumes/ORICO/newlink-new/vibekits/build/macos/Build/Products/Release/Vibekits.app`。
- Developer ID：`Developer ID Application: zhen ji (26T5WV4GLP)`。
- Apple 公证提交 ID：`6e5201a1-ac3e-4594-947e-f6b10c38d5ff`，状态 `Accepted`。
- staple、stapler validate、`codesign --deep --strict` 和 Gatekeeper 均通过；Gatekeeper 来源为 `Notarized Developer ID`。
- 最低系统：macOS 12；主程序架构：`x86_64 arm64`。
- 正式 ZIP：`/private/tmp/Vibekits-1.9.0-dev.187+2187-macos-universal-notarized.zip`。
- 字节数：`311284520`。
- SHA-256：`2845b4327c265fc12120558605d9bb38ed820847e0b358cbacd14d02b6b81944`。

## 5. KEMI 商场闭环

- `app_id=53`，包名 `com.caucy.vibekits`，线上版本 `1.9.0-dev.187`，版本码 `2187`。
- 正式 CDN：`https://cdn.newlink-sz.com/kemiAppStore/macpkg/2026/09/1789140807045_32cc8e09_Vibekits-1_9_0-dev_187_2187-macos-univer.zip`。
- 公网详情、未过滤 macOS 列表、2186 正向更新、2187 当前版不更新均通过。
- 从 CDN 完整下载后字节数和 SHA-256 与本地包一致；下载包再次通过 Developer ID、公证票据、Gatekeeper 和双架构验证。

## 6. Windows 门禁状态

- Windows 58 节点已准备 dev.187 源码目录和旧正式版自包含运行时。
- 节点：Windows 10 22H2 build 19045；全部源码、缓存、临时目录、构建和产物位于 `D:\KEMI-Test`。
- 首次分析因 Mac `.dart_tool/package_config.json` 的绝对路径污染产生伪错误；使用 D 盘离线 Pub 缓存重建配置后，`flutter analyze --no-pub` 通过（442.6 秒）。
- 重点测试执行 54 项：53 项通过；唯一失败是测试错误地要求 Windows 展示 macOS 专属“协助另一台设备”输入框。源码已改成平台感知断言，macOS 对应用例 3/3 通过；该修复仍需同步到 58 后复跑 Windows。
- 首次 Release 暴露两个真实构建输入问题：`flutter_window.cpp` 缺少 `<cwctype>`，以及 Mihomo 许可证文件未进入同步源。源码已补 `<cwctype>`；58 使用等价 `/FIcwctype` 增量验证，并从既有正式运行时恢复相同许可证文件。
- 最终增量 `flutter build windows --release --no-pub` 成功，开始 `00:51:19`、结束 `00:53:22`、耗时 108.8 秒、退出码 0；生成 `vibekits.exe`，版本 `1.9.0-dev.187+2187`。
- `vibekits.exe` 字节数 `160768`，SHA-256 `986e0cb2bf472827d3657f50978cc60025cb4cf2152b5709f34a65d38108a1da`；两次启动 8 秒后进程均存活。内置 Git `2.55.0.windows.3`、ADB `1.0.41`、7-Zip `26.02 x64` 可执行。
- 最终 Windows 源码明确要求将 `vibekits-harness-relay.exe` 与 `vibekits.exe` 同目录打包；缺少该二进制时 Release 主动失败。
- Windows 端只有在精确最终源码、内置 relay、Release 构建、隔离启动和真实协同/仿真命令全部通过后才能发布。不得用旧版普通启动或 SSH 会话冒充本功能验收。

## 7. 当前结论

macOS dev.187 已完成签名、公证、商场发布与公网回读；PAD 75 到 macOS 的真实协同命令和反馈闭环通过。Windows 仍受内置 Windows relay 构建输入约束，保持阻断发布，直至本记录第 6 节门禁全部通过。
