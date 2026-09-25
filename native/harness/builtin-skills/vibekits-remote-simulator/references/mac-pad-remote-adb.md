# 从 Mac 按 VibeKits ID 远程仿真 Android PAD 并使用 ADB

适用：控制端是装有 VibeKits 和 Android `platform-tools/adb` 的 Mac，目标是已获设备主人授权的 Android PAD。操作者只需目标的 6–16 位 VibeKits ID；不需要 PAD 的公网/局域网 IP、SSH 账号、RustDesk 密码或与 PAD 同网。这里的 ADB 串口是 **Mac 本机动态 `127.0.0.1:<端口>`**，经 VibeKits 加密 P2P/中继转发到 PAD，绝不是直接访问 PAD 的 `:5555`。

本页是 **Mac 外部控制器** 的实际操作；若命令运行在 VibeKits Harness 内且已有注册的 `vibekits.simulator.*` MCP 工具，直接调用工具，不运行本页的 Ruby 桥脚本。两种入口连接的是同一仿真能力。

## 0. 必须真实满足的前提

1. PAD 的 VibeKits 已安装、联网；设备主人已在 PAD 上开启“允许作为仿真机”并完成首次授权。PAD 从关闭状态手动开启时有本地密码确认，远程控制端不接收或代填这个密码。原来已启用的状态可在开机后恢复。**ID 不能绕过关闭的仿真开关、首次同意或 Android 权限。**
2. Mac 上运行的是支持 VibeKits 仿真工具桥的 VibeKits，且本地 Android `adb` 可执行。正常启动已安装的 App 可用 `open -a Vibekits`；不要启动另一个同名旧候选或官方 Harness 来代替。Mac 桥配置位于当前用户的 `~/Library/Application Support/com.caucy.vibekits/Vibekits/mcp/tool-bridge.json`，只检查文件是否存在，**不要显示/复制其中的 token**。
3. `scripts/invoke.rb` 已随本技能安装。它只向上面的本机 loopback 桥发请求，并验证 endpoint 是 loopback；不要把桥 token、认证头或配置文件贴到聊天和日志。若同事的 Mac 没有本技能，先从项目 `native/harness/builtin-skills/vibekits-remote-simulator/` 安装同一版本到该 Mac 的 Codex skills 目录。

## 1. 只输入设备 ID：连接并取得动态 ADB 串口

在 Mac 终端执行。把第一行示例数字替换为用户提供的 ID；其余路径按该 Mac 的 Codex skills 安装目录定位。`CODEX_HOME` 未设置时使用 `~/.codex`。

```sh
PAD_ID='1234567890'
case "$PAD_ID" in *[!0-9]*|'') echo '设备 ID 必须是数字'; exit 1;; esac
test ${#PAD_ID} -ge 6 && test ${#PAD_ID} -le 16 || { echo '设备 ID 必须为 6–16 位'; exit 1; }
SKILL_ROOT="${CODEX_HOME:-$HOME/.codex}/skills/vibekits-remote-simulator"
INVOKE="$SKILL_ROOT/scripts/invoke.rb"
test -f "$INVOKE" || { echo '缺少 vibekits-remote-simulator 技能脚本'; exit 1; }
test -f "$HOME/Library/Application Support/com.caucy.vibekits/Vibekits/mcp/tool-bridge.json" || { echo 'VibeKits Mac 工具桥未运行'; exit 1; }
CONNECT_JSON="$(ruby "$INVOKE" vibekits.simulator.connect "{\"routingId\":\"$PAD_ID\"}")" || exit 1
printf '%s\n' "$CONNECT_JSON"
```

先核对响应，而不是看到命令退出 0 就当连接成功。已实测的成功形态包含 `ok:true`、`data.connected:true`、相同的 `data.routingId`、`data.transport:"p2p_or_relay"`、`data.adbReady:true` 和 `data.adbSerial:"127.0.0.1:<动态端口>"`。`mcpReady:true` 说明目标工具目录可用；`sshReady:false` 在 PAD 上是正常的，PAD 不靠 SSH 提供远程 ADB。`toolCount` 会随目标运行状态和版本变化，不以某个固定数字作为连接依据。若有 `deviceIdentity` 等字段，应核对它们；下一步再以 ADB 读取真实 Android 型号与包版本。

接着从**刚才这一次连接**的响应严格提取串口，避免手抄端口；在同一个交互式 shell 中执行即可。

```sh
ADB_SERIAL="$(printf '%s' "$CONNECT_JSON" | ruby -rjson -e '
  result = JSON.parse(STDIN.read); data = result.fetch("data")
  abort "仿真未连接" unless result["ok"] == true && data["connected"] == true
  abort "目标 ID 不符" unless data["routingId"] == ARGV.fetch(0)
  abort "未建立 P2P/中继" unless data["transport"] == "p2p_or_relay"
  abort "ADB 未就绪；先查询仿真状态" unless data["adbReady"] == true
  serial = data["adbSerial"].to_s
  abort "ADB 串口不是本机临时端口" unless serial.match?(/\A127\.0\.0\.1:[0-9]+\z/)
  puts serial
' "$PAD_ID")" || exit 1
printf 'PAD %s 的本机 ADB 串口：%s\n' "$PAD_ID" "$ADB_SERIAL"
```

连接结果同时供人工核对和脚本提取；不要为了取串口反复建立连接。

## 2. 用隔离的 Mac ADB server 连接并确认是目标 PAD

从当前 Mac 的 `PATH` 或 `ANDROID_HOME` 找 `adb`。下面使用独立本机 ADB server 端口 `5039`，避免与其他项目默认 `5037` 会话混用；若本机 5039 已由其他任务使用，选择一个未占用的本机端口并在本次会话中始终使用同一个值。`ADB_SERIAL` 必须来自上一步的返回，不能写死成某台 PAD 的 IP。

```sh
ADB_BIN="$(command -v adb)"
if [ -z "$ADB_BIN" ] && [ -n "${ANDROID_HOME:-}" ]; then ADB_BIN="$ANDROID_HOME/platform-tools/adb"; fi
test -x "$ADB_BIN" || { echo 'Mac 缺少 Android platform-tools/adb'; exit 1; }
ADB_SERVER_PORT=5039
"$ADB_BIN" -P "$ADB_SERVER_PORT" connect "$ADB_SERIAL"
"$ADB_BIN" -P "$ADB_SERVER_PORT" devices -l
"$ADB_BIN" -P "$ADB_SERVER_PORT" -s "$ADB_SERIAL" get-state
"$ADB_BIN" -P "$ADB_SERVER_PORT" -s "$ADB_SERIAL" shell getprop ro.product.model
"$ADB_BIN" -P "$ADB_SERVER_PORT" -s "$ADB_SERIAL" shell getprop ro.build.version.release
"$ADB_BIN" -P "$ADB_SERVER_PORT" -s "$ADB_SERIAL" shell dumpsys package com.vibekits.vibekits
```

`get-state` 必须是 `device`；型号应为预期 PAD，最后一条中应核对 VibeKits 的真实 `versionCode`/`versionName`。如需控制资源状态，先经 `vibekits.simulator.catalog` 看当前设备工具，再用 `vibekits.simulator.call` 调用 `vibekits.device.*`；只读进程、日志、应用清单优先用这些专用工具。ADB 可直接完成包管理器、系统属性和真实 UI 操作。`127.0.0.1:<端口>` 是 Mac 的隧道，不表示 PAD 与 Mac 在同一 LAN。

## 3. 像本机一样操作 PAD，但显式指定屏幕

KEMI 双屏 PAD 上，VibeKits 主界面曾位于 `display 0`，另一屏曾为 `display 2`；不同设备必须先核对，不能把这两个数字当通用常量。先读 `dumpsys display`、`dumpsys activity activities`，必要时取一张指定显示屏的诊断帧；优先使用 catalog 中的 `vibekits.device.ui_inspect` / `ui_action`，不要持续截图轮询。Android `uiautomator dump` 可能只返回默认/另一屏，不能据此断言指定屏无界面。

```sh
"$ADB_BIN" -P "$ADB_SERVER_PORT" -s "$ADB_SERIAL" shell dumpsys display
"$ADB_BIN" -P "$ADB_SERVER_PORT" -s "$ADB_SERIAL" shell dumpsys activity activities
"$ADB_BIN" -P "$ADB_SERVER_PORT" -s "$ADB_SERIAL" shell am start --display 0 -n com.vibekits.vibekits/.SingleScreenActivity
"$ADB_BIN" -P "$ADB_SERVER_PORT" -s "$ADB_SERIAL" shell input -d 0 tap <核实过的X> <核实过的Y>
"$ADB_BIN" -P "$ADB_SERVER_PORT" -s "$ADB_SERIAL" exec-out screencap -d 0 -p > /tmp/pad-display0.png
```

`input -d 0` 与 `screencap -d 0` 必须对应实际目标显示屏；先检查屏幕尺寸和控件位置，再点击。截图只作必要证据，不要用密集截图代替状态接口。对话框、安装器、系统权限提示要按实际画面与用户授权处理；不能自动同意未授权的系统确认。

## 4. 远程安装/升级 APK 的闭环

只有用户授权安装时执行。先在 Mac 核对候选 APK 的包名、版本、SHA-256 和 Android 签名；若是 VibeKits 自身，使用已批准的签名产物，避免覆盖成另一证书/版本。普通覆盖用 `install -r` 保留用户数据，不加 `-d`、不清除数据、不卸载。

```sh
shasum -a 256 /absolute/path/to/candidate.apk
"$ADB_BIN" -P "$ADB_SERVER_PORT" -s "$ADB_SERIAL" install -r /absolute/path/to/candidate.apk
```

**重要：升级承载隧道的 VibeKits 主 APK 会杀掉旧进程/旧 ADB 流。** `adb install -r` 可能显示空的安装失败或超时，但设备已装成功。不要凭命令退出码立刻重复安装。先调用：

```sh
ruby "$INVOKE" vibekits.simulator.connection_status "{\"routingId\":\"$PAD_ID\"}"
ruby "$INVOKE" vibekits.simulator.connect "{\"routingId\":\"$PAD_ID\"}"
```

从新响应重新取 `adbSerial`；动态端口可能改变。以新串口重新 `adb connect`，然后在 PAD 上读取 `dumpsys package <包名>` 的 `versionCode`/`versionName`、`pm path <包名>` 和已安装 `base.apk` 的 SHA-256，与本机候选比对，再真实打开应用并观察目标功能。只有包管理器、文件哈希和运行行为吻合才算装机验证通过。主应用更新后如果 Mac 本机工具桥连接文件残留但 loopback 拒绝连接，只检查/重启 **Mac 上对应的 VibeKits 控制端 App**；先确认没有运行中的控制任务，不要杀掉其他 app 或 `adb` server。

## 5. 失败时按真实状态分流

| 现象 | 下一步 |
|---|---|
| Mac 报工具桥配置缺失或 `127.0.0.1` 连接拒绝 | 检查 Mac 上 VibeKits 是否运行、是否是正确版本；正常启动对应 App 后重试一次。不要打印桥配置或 token。 |
| `remote_disabled` / 首次授权未完成 | PAD 使用者须在本机打开仿真并完成授权；只有 ID 无法绕过。不要改走 RustDesk/SSH 或猜 PAD 的 LAN IP。 |
| `connected=true` 但 `adbReady=false` | MCP/诊断通道可能仍可用；读 `connection_status` 和当前 catalog/目标状态，记录 adbd/辅助组件错误。不要无证据循环 `adb connect`。若系统 UID 辅助组件被禁用，现有 PAD 没有可保证自救的 SSH 服务，需要设备端处理。 |
| `mcpReady=true` 但目录只有少数恢复工具 | 目标完整 Harness 可能尚未起来；恢复工具不是完整目录。有限等待后重新读 catalog/建立新连接；ADB 若独立就绪可先做只读检查。 |
| ADB `offline` / 端口连接断开 | 查仿真状态、重新连接并取新的 `adbSerial`；不要继续使用上一次的本机端口，也不要 `adb kill-server` 影响其他任务。 |
| SSH 显示 `sshReady=false` | PAD 正常不依赖 SSH；远程 ADB 经仿真 P2P/中继。不要把 Mac 的 SSH 客户端误当 PAD 上的 SSH 服务端。 |

PAD 的系统 UID 辅助组件能在已正确安装并已启用仿真的设备上恢复部分 adbd 故障；**不能保证全新 PAD、辅助组件缺失/禁用、系统拒绝共享 UID 时仅凭 ID 就能远程启动 ADB**。此时如实给出 `adbReady=false` 的状态与设备端所需动作。不要远程执行 `adb root`、`su`、`setprop service.adb.tcp.port` 或重启 `adbd` 作为常规排障；这些会断开唯一通道，只有明确授权且有恢复方案时才可做。

## 6. 结束和交付

```sh
"$ADB_BIN" -P "$ADB_SERVER_PORT" disconnect "$ADB_SERIAL"
ruby "$INVOKE" vibekits.simulator.disconnect "{\"routingId\":\"$PAD_ID\"}"
```

只断开本次串口和仿真会话，不运行全局 `adb kill-server`。交付时列出目标 ID、连接 `p2p_or_relay`、真实 PAD 型号/Android 版本、目标 APK 版本、实际执行的操作与结果、ADB 是否就绪及未验证的边界；不泄漏桥 token、密钥、临时签名 URL 或个人数据。

历史验收中的设备 ID、临时串口和构建路径都只是实例，不能复制成其他 PAD 的默认值；每次以本次 `connect` 的返回和目标设备实际状态为准。
