# VibeKits dev.188 PAD 75 仿真进程与文件通道验收

日期：2026-09-12  
候选版本：`1.9.0-dev.188+2188`  
控制端：KEMI PAD `192.168.3.75:5555`  
目标端：macOS VibeKits ID `1554650784`

## 本轮修复

- 控制端把同一设备 ID 的入口明确拆成“协同”和“仿真”，避免历史“连接”按钮错误进入 Harness 协同端口 `32146`。
- 仿真按钮固定进入整机调试端口 `32147`，仍由内置 RustDesk 身份、P2P/HBBR 和 MCP 承载，不依赖外部 RustDesk App。
- 连接成功条件从“读取工具目录”提高为四道门禁：传输已授权、MCP 初始化成功、当次目录读取成功、目标进程与目标受控文件目录只读调用成功。
- 修复载体发送失败后共享会话仍保持绿色的问题；写失败立即断开、关闭载体并通知 UI。

## 自动门禁

- Flutter analyze：0 问题。
- `harness_remote_share_dialog_test`、`deepseek_harness_test`、`harness_remote_controller_session_test`、`harness_simulator_controller_test`：36 项通过。
- 相关整合回归此前累计 59 项通过、1 项仅因环境跳过、0 项失败。

## PAD 75 真机证据

- APK 使用设备现有正式覆盖安装证书签名；APK Signature Scheme v2/v3 均通过。
- APK SHA-256：`a7e296fcccb0230372f97100ef2c7c637826cf2778c7ceaa3e7cbc890ff197a2`。
- `pm install -r -d` 返回 `Success`，未卸载、未清数据。
- 安装后版本：`versionName=1.9.0-dev.188`、`versionCode=2188`。
- PAD 只输入/复用目标 ID `1554650784`，点击“仿真”后读取目标当次 `195` 项工具。
- 隧道内真实调用 `vibekits.device.processes` 成功；随后读取目标能力摘要中的受控下载目录，并真实调用 `vibekits.files.search` 成功。
- UI 最终显示：`仿真调试已连接 1554650784 · 195 项工具 · 进程与文件自检通过`。
- 75 上主进程 `com.vibekits.vibekits` 与独立传输进程 `com.vibekits.vibekits:vibekits_harness` 同时存活；日志出现 `VibeKits embedded Harness transport started`，未发现本应用崩溃。
- 截图：`/private/tmp/vibekits-pad75-process-file-proof.png`。

### 经 ID 隧道完成安装与双向文件实测

- 另起受管回环控制会话，只提供目标 ID `1554650784`；MCP 初始化成功后调用目标端 `vibekits.adb.list_devices`，返回 `192.168.3.75:5555`、`model=huanglong`、`state=device`。
- 通过同一隧道调用目标端 `vibekits.adb.install_apk`，把目标 Mac 上的 `/private/tmp/KEMI_Send-2.0.5+151-android-common.apk` 无损覆盖到 75；远端结果为 `exitCode=0`、`Performing Streamed Install`、`Success`。75 核验 `org.kemi.send versionCode=151`，`lastUpdateTime=2026-09-12 10:04:17`。
- 通过同一隧道调用 `vibekits.adb.push_file`，向 75 的 Download 写入 52 字节探针；再调用 `vibekits.adb.pull_file` 拉回目标 Mac。发送与接收文件 SHA-256 均为 `cfc9b76dfad44b8b4a94fc973064775dc67f3c6cd87df7ea5854cb431fdcf53f`。
- 最后通过同一远端 `vibekits.adb.shell` 删除 75 上探针，返回 `exitCode=0`；临时隧道随后正常关闭。

## 安装与调试能力边界

当前已验证：远端整机进程、日志、崩溃、系统资源、应用启停、受控文件搜索，以及目标机连接 Android 设备后的 ADB 文件推送/拉取与签名 APK 安装。其中 ADB 安装和文件双向传输不是目录推断，而是已经在 75 通过 ID 隧道得到真实成功响应和校验结果。VibeKits 自身还具有同团队签名 Universal ZIP 的上传、校验、应用和回滚协议。

其他 macOS/Windows 产品的候选安装尚未实现为同团队签名白名单部署合同。当前不能把任意绝对路径写入、任意 shell 或任意安装器执行冒充成该能力已完成；后续必须分别验证 macOS Developer ID/公证身份与 Windows Authenticode 身份后再开放。

## 结论

PAD 75 到 macOS 目标的统一 ID 仿真链已完成真实传输、目录、进程、受控文件读取、ADB 双向文件和 APK 覆盖安装闭环。VibeKits 自更新已有协议；其他桌面产品安全安装仍是独立未完成项，不影响本轮已通过的远端诊断、文件与 Android 安装能力。
