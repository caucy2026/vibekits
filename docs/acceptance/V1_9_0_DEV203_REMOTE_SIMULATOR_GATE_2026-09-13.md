# VibeKits 1.9.0-dev.203 远程仿真发布门禁

日期：2026-09-13

## 本轮必须证明的用户合同

1. 被控设备打开一次“远程仿真”后，控制端只输入统一设备 ID，即可通过 RustDesk P2P 或 HBBR 访问目标机。
2. 控制端可读取目标系统、进程、应用和日志；可经严格主机指纹校验的 SSH/SFTP 执行命令与传输文件。
3. 在被控端持续授权范围内，可安装、启动、停止和安全卸载测试软件；同一已认证控制端不逐项重复请求 VibeKits 授权。
4. 关闭连接必须结束 MCP/SSH 隧道并清理临时文件；关闭目标开关还必须撤销 VibeKits 管理的 SSH 公钥。
5. 远程协助与远程仿真使用独立固定端口和生命周期；macOS 与 Windows 共用协议与状态逻辑，不影响本地 Harness、插件和工作区。

## dev.202 首次真实机失败与修复

目标 `4456560334` 安装 dev.202 后，原生连接和 204 项工具目录成功，第一条只读 `vibekits.device.processes` 在 `tools/call` 阶段超时。根因是原生连接身份查询被错误放到每一次工具调用前，导致只读工具也等待敏感授权判定。

dev.203 把身份查询严格收窄到安装、卸载、SSH 公钥授权和撤销四类敏感操作。永久回归 `只读工具绝不等待敏感授权身份查询` 使用一个永不完成的身份查询器证明只读调用仍能立即结束，且查询次数保持为零。dev.202 已撤回。

## 自动门禁

- 版本：`1.9.0-dev.203+2203`；Info.plist：`1.9.0.203 / 2203`。
- 静态分析：0 issue。
- 全量 Flutter：865 passed、21 个真实设备/联网条件 skipped、0 failed。
- 远程协助、仿真、首次证书配对、mTLS、项目/会话同步、历史、反馈、停止、P2P/HBBR 生命周期、macOS/Windows 共用逻辑专项：170 passed、4 个显式真实环境门禁 skipped、0 failed。
- 远程仿真授权专项：6 passed、1 个显式真实机门禁 skipped、0 failed。
- 75 Pad 真机：ADB 在线，型号 `huanglong`，`com.vibekits.vibekits` dev.188 可真实启动并取得运行进程；63 当前不在 ADB 在线列表，不能用 75 的结果冒充 63。

## 可重复的完整真实机验收

`test/manual_real_harness_simulator_test.dart` 现覆盖：

1. 只输入设备 ID 建立原生载体并读取超过 100 项工具目录；
2. 读取进程；
3. 自动 SSH 公钥交换、主机 Ed25519 指纹比对和命令执行；
4. SCP 上传与远端 SHA-256 回读；
5. 上传独立公证测试 App，安装、应用清单确认、启动、进程确认、Unified Log 读取、停止和安全卸载；
6. 完整应用生命周期连续执行两遍，验证相同已认证控制端不会再次请求 VibeKits 授权；
7. 可选 ADB 设备、shell、logcat、文件往返和 APK 安装；
8. finally 关闭所有受管隧道并清理远端临时文件。

测试 App 为 `com.caucy.vibekits.simulatorprobe`，Universal `x86_64 + arm64`、macOS 12+、Developer ID、Apple 公证 `Accepted`（Submission ID `f7347fb1-c99d-4705-8836-9c1917439ed1`）并已 staple。最终 ZIP SHA-256 为 `65bbc531a91f4d445897ab92ab19d5eaa7a9929359e2e57fa174a0d4dc6e9c44`。它只用于验收，卸载采用目标用户废纸篓，可恢复。

## macOS 候选

- ZIP：`/Volumes/ORICO/kemi-build-cache/vibekits-dev203/run-20260913-real-target-fix/delivery/Vibekits-1.9.0-dev.203+2203-macOS-universal-notarized.zip`
- 大小：311,506,268 bytes。
- SHA-256：`7e381a3feb09601859e9568656607146c33e45430ab2c40c32719486373dff6b`。
- 架构与系统：`x86_64 arm64`，两个 slice 的最低系统均为 macOS 12.0。
- 签名：`Developer ID Application: zhen ji (26T5WV4GLP)`；深度严格验签通过。
- Apple 公证：`Accepted`，Submission ID `7bf62275-26d3-4f77-bff1-46e7637542e6`；staple/validate 与 Gatekeeper `Notarized Developer ID` 通过。
- 最终 ZIP 解包后真实启动，精确进程发布当前 MCP 桥，目录返回 204 项工具；Harness/ADB/7-Zip RAR/Git/GitHub CLI 完整兼容门禁通过。

## 当前真实机结论

截至本记录，目标 `4456560334` 仍表现为 dev.202：P2P 可建立，但第一条只读 `tools/call` 仍在 10 秒超时，与撤回缺陷一致，说明 dev.203 尚未覆盖生效。目标升级 dev.203 后必须重新执行以下门禁，未全部通过前不得声称远程仿真完成：

- 默认 P2P/自动回退完整生命周期；
- 强制 HBBR 完整生命周期；
- 连续两轮安装/启动/日志/停止/卸载且无第二次 VibeKits 授权；
- 断开后连接表与本机监听端口清零；
- 若目标带 Android 设备，再执行 ADB shell/logcat/文件往返/APK 安装。

远程协助真实项目/会话门禁也没有被自动测试替代：本控制端当前没有 `4456560334` 的完整证书配对记录，现有只读会话测试正确失败为 `No element`。需要目标端首次明确批准配对后，继续验证项目、会话、历史、发送、反馈、独立停止和断开。
