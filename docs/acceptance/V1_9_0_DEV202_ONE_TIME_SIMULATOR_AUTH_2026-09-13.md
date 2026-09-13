# VibeKits 1.9.0-dev.202 远程仿真一次授权验收记录

日期：2026-09-13

## 用户合同

1. 被控设备只需第一次打开“远程仿真”并完成系统要求的授权；开关保持开启时不再为每次安装、卸载或受管 SSH 操作重复询问。
2. 授权只属于同一条已认证的 VibeKits 原生连接和同一控制端 ID，不能用伪造请求头继承。
3. 关闭开关立即撤销入口和 VibeKits 管理的 SSH 公钥；设备身份变化、扩大权限、用户撤销或操作系统强制要求时重新授权。
4. 不绕过 macOS 自身的隐私、管理员和安全提示。

## 实现与安全边界

- 固定 MCP 服务仍只监听 `127.0.0.1:32147`，公网和局域网不能直接访问。
- 敏感调用在执行前实时核对 RustDesk Harness 原生连接表：控制端 `peerId` 必须与请求 ID 一致，连接必须 `authorized=true`、`disconnected=false`，目标必须是固定 `32147` 回环端点。
- 原生连接消失、身份不一致或查询失败时不继承授权，回到目标端批准流程并最终失败关闭。
- 普通 LAN MCP 与远程协助通道不能借用远程仿真授权。

## 自动验收

- `flutter analyze --no-pub`：0 issue。
- 全量 Flutter：864 passed，21 个真实设备/联网门禁按条件 skipped，0 failed。
- 远程仿真授权、目标生命周期、控制器与工具桥组合：56 passed，1 个真实系统资源探针 skipped，0 failed。
- 专项覆盖：同一已认证控制端连续安装/卸载不重复批准；SSH 公钥交换继承一次授权；缺少 ID 拒绝；伪造有效格式 ID 但没有匹配原生连接时拒绝。

## macOS 交付状态

- 精确版本：`1.9.0-dev.202+2202`；Info.plist 为 `1.9.0.202 / 2202`。
- Universal：`x86_64 arm64`；最低系统：macOS 12.0。
- 完整运行时门禁通过：Harness、ADB、7-Zip/RAR、Git、GitHub CLI 及 App/Framework 均满足双架构和最低系统要求。
- 36 个 Mach-O 使用 `Developer ID Application: zhen ji (26T5WV4GLP)`、Hardened Runtime 和 Apple 安全时间戳签名，深度严格验签通过。
- 签名后及最终 ZIP 解包后均真实启动精确候选，本地 Harness 工具桥响应成功并正常退出。
- Apple 公证：`Accepted`，Submission ID `56900286-5ce7-4e37-9762-5ce784a867b9`；App 已 staple/validate，Gatekeeper 为 `Notarized Developer ID`。
- 最终 ZIP：`/Volumes/ORICO/kemi-build-cache/vibekits-dev202/run-20260913-one-time-auth/delivery/Vibekits-1.9.0-dev.202+2202-macOS-universal-notarized.zip`
- 大小：311,506,250 bytes。
- SHA-256：`fb0ffc4f46ab9d238df2356d861ccad8db686298d620a46c38c07e4a323b6406`。

## 目标机安装后结论：撤回

目标 Mac `4456560334` 安装后，控制端真实连接和 204 项工具目录成功，但首个只读进程调用在 8 秒内超时。根因是一次授权身份查询被错误放在所有 `tools/call` 前，导致只读工具也等待原生连接查询。dev.202 因此撤回，不得作为最终验收包；修复和永久回归进入 dev.203。
