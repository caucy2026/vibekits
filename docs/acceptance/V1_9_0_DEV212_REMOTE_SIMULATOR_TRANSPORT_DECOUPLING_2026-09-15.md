# VibeKits 1.9.0-dev.212 远程仿真传输解耦与 macOS 候选验收

日期：2026-09-15

## 本轮目标

- 控制端只输入统一设备 ID，通过内置 P2P 或 HBBR 中继静默连接目标设备，不打开远程桌面界面。
- SSH/SFTP 属于远程仿真运行时，不依赖 Harness 启动状态、MCP 工具目录或模型调用。
- 普通 LAN MCP 继续只在同一局域网发现；跨网 MCP 必须经远程仿真隧道映射目标回环端口，不把 MCP 服务直接暴露到公网。

## 修复

1. 新增独立 `/simulator/ssh-bootstrap` 控制端点，使用原生隧道登记的真实 peer ID 校验调用方并完成系统 SSH 公钥授权，不调用 Harness MCP。
2. 桌面控制端先完成传输和 SSH，再尝试 MCP 初始化；MCP 初始化失败时仍保留 SSH/SFTP 会话和远程调试能力。
3. 远程调用授权只接受当前原生连接，不再以历史 SSH peer 标记代替实时连接身份。
4. 内置载体发现陈旧离线实例时，仅接管 VibeKits 自己的受管进程并重新启动当前包内载体，不操作外部 RustDesk 应用。
5. 需求文档明确加入不同局域网/公网的 P2P 优先、中继回退门禁，以及 MCP 故障下 SSH、文件、日志与应用生命周期仍可用的验收要求。

## 自动门禁

- 定向回归：41/41 通过，覆盖 SSH bootstrap、伪造 peer 拒绝、真实 peer 授权、MCP 故障降级和陈旧载体接管。
- 全项目 Flutter 回归：880 项通过、31 项按真机或联网条件跳过、0 项失败。
- 全项目 `flutter analyze`：0 问题。
- Git 差异空白检查：通过。

## macOS 候选

- 版本：`1.9.0-dev.212+2212`。
- Universal：`x86_64 + arm64`；最低系统版本门禁：macOS 12+。
- Harness、Node、ADB、7-Zip、GitHub CLI 与 Git 随包兼容检查：通过。
- Developer ID：36 个 Mach-O 深度严格验签通过；签名后 App 真实启动并通过本地 Harness 工具桥检查。
- Apple 公证：`Accepted`，Submission ID `7a12d8cb-fe45-4e8f-ad81-1e5da3262d93`；ticket staple/validate 通过。
- Apple 发布策略检查：`App passed all pre-distribution checks and is ready for distribution.`
- 最终 ZIP：`/Volumes/ORICO/kemi-build-cache/vibekits-dev212/delivery/Vibekits-1.9.0-dev.212+2212-macOS-universal-notarized.zip`
- 大小：311,671,942 bytes。
- SHA-256：`867f588fdc46ab8768e1018093d812142638d2adc549d7c57f1565a1192dd573`。

## 尚需真机确认

本记录证明代码回归、本机传输合同、签名、公证和最终归档门禁通过。真正的不同局域网/公网闭环仍必须由另一台 Mac 安装这一精确 ZIP，强制走 HBBR 后验证：只输入 ID、SSH 命令、SFTP 双向 SHA-256、日志读取、应用安装/启动/停止/卸载、可选单帧截图，以及 MCP 故障时 SSH 不中断。完成前不得把本机自动测试概括为公网真机已通过。
