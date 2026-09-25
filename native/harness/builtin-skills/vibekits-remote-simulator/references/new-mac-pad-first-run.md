# 全新 Mac + 全新 Android PAD：从商城安装到按 ID 远程 ADB

本页给首次部署者使用。这里的 PAD 指运行 Android 的 KEMI PAD，**不是 Apple iPad/iPadOS**。Mac 和 PAD 可以位于不同局域网；远程 ADB 走 VibeKits 已授权的 P2P/中继仿真通道，不填写 PAD 的公网 IP，也不把 PAD 的 `:5555` 暴露到公网。设备主人必须在 PAD 本机允许仿真与首次系统授权；仅知道 ID 不构成授权。

## 三个下载位置

| 下载对象 | 在全新设备上打开的位置 | 核对项 |
|---|---|---|
| Mac 版 VibeKits | [KEMI 商城 Mac 版 VibeKits 公开下载页](https://kemi.newlinksz.com/kd/s/com.caucy.vibekits?os=macos) | 页面应显示 `com.caucy.vibekits` 对应的 macOS 安装包；按页面操作下载、安装，启动后在“关于我们”核对已安装版本。不要去开发者后台上传页下载，也不要把 Android APK 装到 Mac。 |
| Android PAD 版 VibeKits | 在 **PAD 自己的浏览器**打开 [KEMI 商城 Android/PAD 版 VibeKits 公开下载页](https://kemi.newlinksz.com/kd/s/com.vibekits.vibekits?os=android) | 页面应显示 `com.vibekits.vibekits` 的 Android APK；下载安装时由 PAD 本机用户完成 Android 安装确认。Android 商城记录的 `platforms=pad2` 也属于 PAD。 |
| 远程仿真技能 | [云端 `caucy2026/skills/vibekits-remote-simulator`](https://github.com/caucy2026/skills/tree/main/vibekits-remote-simulator) | 下载**整个技能目录**，保留 `SKILL.md`、`agents/`、`references/`、`scripts/invoke.rb`；只下载本页 Markdown 不能执行连接。仓库根目录是 `https://github.com/caucy2026/skills`。 |

这两个商城链接是公开分享页，带有**不同的包名和明确的 `os` 参数**。每次部署都以页面当时显示的版本为准，不把下面的版本快照当作永久下载链接。VibeKits 已安装以后，后续更新按用户要求在 App 的“应用中心”商场页面主动操作；不依赖启动时自动弹窗。

**发布状态快照（2026-09-25，已从商城公开 API 核对）：**Mac 条目 `app_id=53` 为 `1.9.0-dev.304 / versionCode 2304`；Android/PAD 条目 `app_id=71` 已更新为 `1.9.0-dev.304 / versionCode 2304`，仍只面向 `pad2`。PAD 包的正式签名证书和 CDN 回下载 SHA-256 已核对；已安装相同字节包的 PAD63 能按 ID 跨网连接，返回 `adbReady=true` 并完成只读 ADB 命令。**这不是全新 PAD 首装、ADB 初始关闭、辅助组件初次安装的真机验收**；首次部署仍须按本页第 4 节逐项验证。若商城此后显示其他版本，以当时的包名、版本、签名和功能实测为准。

## 1. 在两台新设备上准备

1. **Mac：**从上表的 Mac 商城页下载并安装 VibeKits，正常打开应用。核对“关于我们”的真实版本，以及智能体/Harness 是否能加载。若首次启动被 macOS 拦截，依照系统显示的签名/公证提示处理，不关闭 Gatekeeper。控制端要有网络，且已登录/配置可用的 Harness 模型 Key 才能让智能体自主工作；仅做仿真连接和外部 ADB 验收不需要让模型先生成代码。
2. **PAD：**从上表的 Android 商城页下载并安装**适用于该 PAD、与系统权限辅助组件兼容且已正式发布**的 VibeKits。完成系统安装确认后，在“关于我们”核对版本，并确认设备显示 6–16 位 VibeKits ID。首次安装时仿真默认关闭。开启仿真前确认此机型允许正式包内的同签名系统 UID ADB 辅助组件安装并运行；平台签名不等于任何 Android 设备都允许共享系统 UID，不能跳过实际检查。2026-09-25 商城的 `dev.304` 在 PAD63 已验证，但其他全新 PAD 仍需本机首装与 ADB 冷态验收。
3. **PAD 本机授权：**由设备主人在 VibeKits 设置/高级设置打开“允许作为仿真机”，按 PAD 本机提示输入启用密码并处理首次系统授权；界面应显示“仿真机可连接”。控制端不代填密码，不通过 ID 绕过开关。已授权开启的状态应在重启后恢复，实际新机仍须复验。
4. **Mac 的 ADB 工具：**如要在 Mac 终端直接运行 ADB，安装 Google 官方 [Android SDK Platform-Tools for Mac](https://developer.android.com/tools/releases/platform-tools)，然后运行 `adb version`。Android Studio 已安装时也可使用其 SDK 下的 `platform-tools/adb`。不要从不明站点下载 `adb`。

## 2. 在 Mac 安装云端技能

新 Mac 上安装 Git 后在终端执行。下面以 Codex 的默认技能目录为例；若用户自定义了 `CODEX_HOME`，命令自动使用它。已有同名技能时应先比较版本，避免覆盖工作中的自定义文件。

```sh
git clone --depth 1 https://github.com/caucy2026/skills.git "$HOME/Downloads/kemi-skills"
SKILL_DEST="${CODEX_HOME:-$HOME/.codex}/skills/vibekits-remote-simulator"
mkdir -p "$SKILL_DEST"
cp -R "$HOME/Downloads/kemi-skills/vibekits-remote-simulator/." "$SKILL_DEST/"
test -f "$SKILL_DEST/SKILL.md"
test -f "$SKILL_DEST/references/mac-pad-remote-adb.md"
ruby -c "$SKILL_DEST/scripts/invoke.rb"
```

若 `~/Downloads/kemi-skills` 已存在，先在该仓库核对远端和工作树，再 `git pull --ff-only`，不要对已有目录再次 `git clone`。技能装好后，Mac 上的 Codex 可按 `vibekits-remote-simulator` 自动选择此技能。VibeKits 自带的 Harness 则优先调用已注册的 `vibekits.simulator.*` MCP 工具，不需要通过脚本模拟 Harness 工具调用；若要用 Mac 终端外部控制，才使用技能内的 `scripts/invoke.rb`。

## 3. 按设备 ID 建立远程仿真与 ADB

先让 PAD 保持开机、联网、仿真已启用，再在 Mac 的 VibeKits Harness 对话里给出 PAD 的真实 ID，并要求：

> 连接我已授权的 Android PAD，VibeKits ID 为 `<设备ID>`；先报告连接状态、传输方式和远程 ADB 是否就绪，再用只读命令核对 Android 型号、系统版本与 VibeKits 安装版本。

Harness 路线应调用 `vibekits.simulator.connect`（参数 `routingId`），检查 `connected=true`、ID 一致、`transport=p2p_or_relay`、`adbReady=true`；之后按 `vibekits.simulator.catalog` 所列工具做只读查询。`connected=true` **不等于** ADB 一定就绪。

需要 Mac 终端实际执行 `adb` 时，完整照 [Mac → PAD 远程 ADB 操作指南](mac-pad-remote-adb.md) 的第 1、2、6 节操作：从本次连接返回的 `adbSerial=127.0.0.1:<动态端口>` 提取串口，在 Mac 使用隔离 ADB server 端口连接，执行 `adb get-state` 和只读 `getprop`；结束时只断开本次串口和仿真。**不要**把 `127.0.0.1:<端口>` 写成 PAD 的固定地址，下一次连接可能改变。

## 4. 新机验收：四项都通过才算可交付

1. Mac 和 PAD 从各自的商城公开页下载，分别核对实际安装包名、版本与平台；PAD 必须是已发布的、包含正式 ADB 辅助组件且支持目标机型的版本。
2. PAD 在初始 ADB 关闭的条件下由设备主人本机开启仿真；Mac 仅凭 ID 建立 `p2p_or_relay` 连接，`adbReady=true`，Mac 的动态串口上 `get-state=device`，只读 `getprop ro.product.model` 返回预期 PAD 型号。全新首装场景需要现场恢复手段，不能为了测试先切断唯一可用连接。
3. 控制端与 PAD 放在不同局域网或蜂窝/宽带网络，重复上述 ID→ADB 闭环，证明没有依赖同网段 IP。记录真实传输方式，不以 UI 的“可连接”字样代替 ADB 命令结果。
4. PAD 保持仿真开启并重启，重连后 ADB 仍可用；用户主动关闭仿真后连接应被拒绝且后台服务停止。关闭验证只能在有现场恢复方案时进行。

若返回 `remote_disabled`，在 PAD 本机处理开关和首次授权；若 `connected=true` 但 `adbReady=false`，按 [操作指南的故障表](mac-pad-remote-adb.md#5-失败时按真实状态分流)检查系统 UID 辅助组件、设备兼容性和服务状态。现有材料**尚未证明**任意全新 PAD 在没有辅助组件、没有系统权限且 ADB 已关闭时仍能仅凭 ID 自动恢复；把这种失败如实记录为阻塞，不承诺无条件成功，也不擅自打开公网 5555、执行 root 或改用未经授权的桌面连接。
