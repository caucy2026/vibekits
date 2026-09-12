# VibeKits dev.188 PAD75 ↔ macOS 仿真验收（2026-09-12）

## 候选与设备

- macOS 候选：`build/macos/Build/Products/Release/Vibekits.app`
- macOS 版本：`1.9.0.188 (2188)`；主程序 `x86_64 arm64`；最低系统门禁 macOS 12+。
- macOS 签名：`Developer ID Application: zhen ji (26T5WV4GLP)`；36 个 Mach-O、Hardened Runtime、内置 Node/DSH、ADB、7-Zip、Git、GitHub CLI 均通过签名与运行时验证。
- PAD75：`192.168.3.75:5555`；VibeKits `1.9.0-dev.188+2188`。
- 目标统一 ID：`1554650784`。

## 真实闭环

1. 75 使用已保存的证书配对记录，先断开旧通道，再按 ID 重新建立仿真通道。
2. 连接后重新执行 MCP initialize、`tools/list`、`vibekits.device.processes`、
   `vibekits.system.capability_check` 与受控下载目录 `vibekits.files.search`。
3. UI 只有在上述真实调用全部返回后才显示：
   `仿真调试已连接 1554650784 · 195 项工具 · 进程与文件自检通过`。
4. 75 独立进程 `com.vibekits.vibekits:vibekits_harness` 在连接后真实存活；主 UI
   冷启动时仿真按需关闭，不误报异常，也不提前启动独立传输进程。
5. 经相同 ID 隧道调用 Mac 内置 ADB，真实识别 PAD75；此前同一批次已通过
   `vibekits.adb.install_apk` 覆盖安装 KEMI Send，并完成 52 字节文件
   push → pull → SHA-256 一致 → 远端删除闭环，详见
   `V1_9_0_DEV188_PAD75_SIMULATOR_PROCESS_FILE_2026-09-12.md`。

## 两个已安装应用复核

- VibeKits：`com.vibekits.vibekits`，`dev.188+2188`，覆盖后冷启动 374 ms，主进程正常。
- KEMI Send：`org.kemi.send`，`2.0.5+151`，冷启动 590 ms，前台
  `org.kemi.send/.MainActivity`，未发现对应 FATAL/ANR。
- 新 Android APK 最初被 Gradle 默认 debug 证书签署，设备以
  `INSTALL_FAILED_UPDATE_INCOMPATIBLE` 正确拒绝；未卸载、未清数据。随后按 `xtqx.md`
  使用既有测试身份重新签署，证书 SHA-256 与设备现有版本一致，v2/v3 均通过，
  无损覆盖成功。此问题不得通过卸载绕过。

## 本轮架构修正

- 进程内 Harness 工具桥接优先发布；LAN 发现和本地/局域网目录刷新后置且可降级，
  防止新增网络能力拖住原 Harness/MCP。
- macOS 清单事实路径是 app-scoped
  `~/Library/Application Support/com.caucy.vibekits/Vibekits/mcp/tool-bridge.json`。
  旧 `~/Library/Application Support/Vibekits/Mcp/tool-bridge.json` 可能是历史残留，
  不得用于当前进程判断。本轮当前清单 PID 存活，目录返回 195 项。
- macOS 非沙箱 Developer ID 外层 App 不嵌入空 entitlement blob；签名脚本检测到
  `Release.entitlements` 为空时直接省略 `--entitlements`，网络和串口继续依赖非沙箱
  进程权限。内置 Node 仍使用独立、最小化的 JIT entitlement。
- 修复公证前本地 Harness 冒烟脚本：连接清单由候选 `CFBundleIdentifier` 推导为
  app-scoped 路径，不再读取旧目录。重建后深度严格验签通过，未再出现
  `invalid entitlements blob`。

## 自动化与证据

- 静态分析：0 issue。
- 定向回归：`harness_tool_server_test`、`harness_simulator_controller_test`、
  `rustdesk_harness_link_status_test`、`harness_remote_read_only_panel_test`、
  `simulator_app_lifecycle_contract_test` 共 18 项通过。
- 精确候选启动 PID `28327`，当前 app-scoped 回环桥真实返回 195 项工具；75 重新从
  最近设备记录发起仿真后，再次通过进程与文件自检。本机中继进程保持到中继服务
  的已建立连接，75 同时存在主进程与按需 Harness 进程。
- 截图：
  - `/private/tmp/vibekits-mac-dev188-running.png`
  - `/private/tmp/vibekits-pad75-fixed-cold.png`
  - `/private/tmp/vibekits-pad75-final-simulator.png`
  - `/private/tmp/vibekits-pad75-dev188-simulator-verified.png`

## 尚未冒充完成的门禁

- 本轮没有重新执行“清空配对后的首次证书批准”，使用的是已经真实批准并保存的配对。
- macOS 当前是 Developer ID 已签候选，尚未对本次代码提交 Apple 公证/staple；不得作为正式商城包发布。
- 63 当前不在线；Windows 真机回归不以 75 或 macOS 结果替代。
