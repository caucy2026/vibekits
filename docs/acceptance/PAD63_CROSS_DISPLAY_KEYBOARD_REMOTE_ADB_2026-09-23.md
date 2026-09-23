# PAD63 跨屏键盘与广域网 ADB 验收记录

日期：2026-09-23。目标设备：PAD63；控制端为本机 VibeKits Harness。

## 签名与权限实测

- `priv/xtqx.md` 指定的本地签名证书用于 VibeKits 与 KBoard。两包在 PAD63 上的 SHA-256 签名指纹均为 `c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8`。
- PAD63 `dumpsys package com.vibekits.vibekits` 显示 `com.newlink.kemi.kboard.permission.IPC: granted=true`。KBoard 仍校验调用包名和签名，因此白名单显式加入 `com.vibekits.vibekits`。
- VibeKits UID 为 10091，KBoard UID 为 1000。相同签名取得的是声明过的签名级权限，不能据此推断 VibeKits 自动获得所有系统 UID 权限。

## 当前已通过的真机步骤

- KBoard `1.4.3+212` 由项目标准脚本签名，APK 签名指纹与 PAD63 已安装包一致；`adb install -r` 成功。
- 在 PAD63 的 0 号屏点击 Harness 输入框后，KBoard 报告 `ready request=2 physicalDisplay=2 size=1920x1280`；`dumpsys window` 显示 `KBoardPhysicalKeyboard` 只在 2 号屏，0 号屏 Harness Activity 仍为 RESUMED。
- `adb input -d 2` 触摸事件命中 KBoard 的 2 号屏触摸窗口；在签名候选包上，D2 按键 `a` 和空格传回 D0 Harness 输入框，连续两次退格使输入长度从 2 归零，返回键关闭副屏键盘。
- 2 号屏视频应用 `com.huanglong.portui/.MainActivity` 保持 RESUMED，但本轮采样时它的画面帧没有变化；不能据此宣称播放不中断已通过。
- Android JNI 与 macOS arm64 Harness relay 均由当前源码编译。原生隧道以 `--relay` 强制 HBBR，远端仅允许固定 `127.0.0.1:5555`；本机 `adb connect 127.0.0.1:<隧道端口>` 成功，`adb shell getprop ro.product.model` 返回 `KEMI Vibe Pads S1`。
- 真实 VibeKits 控制器测试 `flutter test --no-pub tool/manual_pad63_remote_adb_test.dart` 在恢复真实 HTTP、保留 macOS 控制通道引导后通过：MCP 目录、自动 ADB 隧道和远端 `getprop` 均成功，测试命令使用 `forceRelay=true`。普通模拟测试中的 HTTP 覆盖会返回 400，不能用于这项验收。
- PAD63 的 `service.adb.tcp.port=5555` 且 `ss` 显示 adbd 正在监听；`adb root` 与 `su -c id` 都返回 `disabled by debug policy`。不能把平台签名误当作应用可执行 root 命令。Android 仿真开关现在先探测本机 5555，未就绪时保持原生隧道关闭并显示明确错误；Mac、Windows、Linux 不走此探测。跨网控制端只经已授权的原生隧道连接该固定端口。
- 新 APK 按签名文档重编，构建完成并 `adb install -r` 成功。高级设置真实开关显示“允许作为仿真机 / 仿真机可连接”。开关关闭再开启后，强制 HBBR 的控制器与远程 ADB 测试通过；此后强制停止并重启 PAD 应用，不手动操作开关，同项测试仍通过。首次覆盖安装后立即测试曾返回 `remote_disabled`，不能据此宣称安装瞬间连接无抖动；后续冷启动未复现。
- `flutter test --no-pub test/harness_simulator_target_runtime_test.dart test/harness_simulator_controller_test.dart` 共 17 项通过。Android 5555 探测由 `Platform.isAndroid` 限定，桌面 SSH 路径保持原样。

## xtqx.md 系统权限复核

- `xtqx.md` 的生产方案是平台签名加 `sharedUserId="android.uid.system"`。当前 VibeKits 已用与系统 UID KBoard 相同的平台证书签名，但清单没有声明共享系统 UID；PAD63 进程实测为 UID 10091。签名本身并未改变 UID。
- KBoard 实测 UID 1000；其补充组没有 `shell`（2000）。`/system/xbin/nlsu` 为 `root:shell`、模式 `4750`，因此系统 UID 进程也不能直接执行。用 `nlsu 1000,1000 /system/xbin/nlsu 0 id` 验证返回 `Permission denied`。
- 用当前 ADB shell 的 `nlsu` 临时切换到 UID 1000，只把 `service.adb.tcp.port` 写回原值 5555，`setprop` 返回 0；对已经运行的 adbd 执行幂等 `ctl.start adbd` 也返回 0。因此 PAD63 的系统 UID 确有控制 adbd 启动和 TCP 属性的能力，不依赖再提权到 root。未关闭实际 ADB 链路测试冷启动。
- 不应在现有主 APK 原位增加 `sharedUserId`：已安装包从 UID 10091 迁移到 1000 不属于普通无损覆盖升级，且主应用包含 WebView。`android:process=":web"` 仅分进程，不会改变 APK 的 Linux UID；`xtqx.md` 关于子进程变为普通 UID 的说法不能直接用于 VibeKits。可行适配是单独的平台签名、系统 UID 辅助 APK，通过签名权限限定的本机 IPC 接受 VibeKits 仿真开关请求，控制 adbd 后再开放原有固定隧道。

## 待完成的发布门禁

1. 在 2 号屏实际播放视频期间复测帧推进、音频和键盘开关，不以 Activity 的 RESUMED 状态替代播放证据。

## PAD63 Key 输入后模型请求失败（2026-09-23）

- PAD63 当前已安装 VibeKits `1.9.0-dev.225`，Harness 工作区保持就绪，输入框非空。实际执行时间线显示“移动端 Harness 请求失败：API Key 无效或无权访问当前模型”，进程退出代码 1；这来自模型接口的 HTTP 401 或 403 分支，不是本地 Harness 启动失败。
- 设置页使用 `https://api.deepseek.com` 和 `deepseek-flash`；DeepSeek 官方接口文档确认两者是当前有效组合。旧代码把 401 与 403 合并成同一句话，无法从现有本机日志再区分。新代码分别提示“401：Key 未通过认证”和“403：密钥无权访问模型”，并在模型列表验证入口同样区分。
- 本地回环假服务测试覆盖 401、403 与正常模型列表，不使用真实 Key；相关 Harness 回归共 32 项通过。真实 Key 的再次外发验证未执行，设备上需经用户正常操作触发，不能把本地测试宣称为远端认证成功。

## PAD 与 macOS 推理呈现差异（2026-09-23）

- 用户在 PAD63 上自行恢复 Key 后，新任务成功返回；真实控件树显示“执行时间线 · 6 步”和约 5.9 秒的最终回复。不能继续把 Key 错误标记为当前阻塞。
- PAD Android 由 `_MobileHarnessAgent` 直接调用 DeepSeek Chat Completions，发送 `stream: false`，只在完整回复或工具调用结束后输出文本。UI 的“理解任务／规划操作／生成回复”是 VibeKits 本地构造的进度节点，并非模型逐段推理内容。
- macOS 使用官方 DSH 进程和原生 WebView；两端目前不共享同一推理事件流或呈现机制。PAD 的任务结果成功不等于推理过程与 macOS 同步。后续若要求体验一致，需定义官方事件的移动端等价映射并做真实流式、工具事件与取消验收，不能只更改时间线文字。

## PAD 流式推理与原生俄罗斯方块 APK 复验

- Android 模型请求已改为 SSE 流式；按官方 DeepSeek 参数显式开启 `thinking` 与 `reasoning_effort=high`。客户端解析真实 `reasoning_content`、`content`、工具调用增量，工具思考内容在后续工具轮次传回模型。PAD 会话新增可滚动、可折叠的真实推理区及持久化字段，不再把 UI 的“理解任务”文字当成模型返回内容；回复增量按 200ms/512 字节合并，避免逐 token 重建 UI 与远程历史。
- 本地假模型 SSE 测试证明真实推理段可被解析和显示，Harness 界面测试覆盖缺少 Key、HTTP 401 的输入框内提示、历史推理区与原有时间线，共 34 项通过；相关 Dart 分析通过。最终签名 PAD 包安装成功，包版本仍为 `1.9.0-dev.225`（versionCode 2225，尚未作为商场新版本发布）。
- PAD63 自己的 Harness 通过远程仿真会话先写出 `tetris.html`，后按纠正要求改写原生 `tetris-apk/TetrisActivity.java`（32,309 字节）。控制端只负责把 PAD 生成的 Java 源码放入独立 Android Gradle 壳工程编译；`targetSdk` 改为 35 后 `:app:assembleRelease` 成功。原生测试 APK 安装为 `com.vibekits.tetris.demo`，PAD 上真实启动并显示 10×20 棋盘、七种方块预览、触摸按钮；点击“暂停”后出现“已暂停/继续”，进程未崩溃。
- 最终 VibeKits 包上做了两次纯算术远程会话，分别 6 秒、8 秒完成，远程历史游标为 5 与 10，远少于旧逐 token 任务的 1106。两次实机均未显示“推理过程”卡片；本机只读检查持久会话发现 `reasoningTrace` 长度均为 0。因此当前版本能呈现 API 真正提供的推理段，但不能宣称 PAD 与 macOS 的真实推理显示已经一致。需继续查明 DeepSeek 当前模型/账号的实际流式返回；不得用合成文字冒充推理。
- 自动审批拒绝过一次拟议的“读取 PAD 私有游戏源码并发给 DeepSeek”复查，理由是源码可能外发且本次授权不覆盖该数据传输。随后改用完全不读取文件的算术题验证流式任务，没有重试该源码外发动作。
- 实机升级复查暴露 Android `HOME` 指向 `code_cache`：旧会话文件会随覆盖安装消失。现改存于应用持久 `files/Vibekits/Harness`，旧缓存尚在时自动复制。PAD63 当前会话文件先在本机复制到持久目录，再安装修复包；随后创建纯算术会话，覆盖安装同一签名 APK，持久目录会话数从 1 保持为 1，UI 再次显示该会话及“模型未返回推理文本”说明。旧版已被系统清掉的历史内容无法由代码恢复。
- 输入框内在 Key 缺失或 API 401/403 时显示设置和验证入口；缺失与 401 的 Widget 回归均通过。最终 PAD 实测保留原生俄罗斯方块包 `com.vibekits.tetris.demo`；测试 APK 只安装到 PAD，未上商场。
