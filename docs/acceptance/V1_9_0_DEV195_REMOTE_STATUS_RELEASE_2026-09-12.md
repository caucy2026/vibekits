# VibeKits dev.195 远程状态解耦与正式 macOS 发布验收

日期：2026-09-12
版本：`1.9.0-dev.195+2195`

## 发布结论

dev.195 是本轮唯一允许交付测试的 macOS 正式安装包。它保留 dev.194 的远程协助强制载体、等待状态和全功能实现，并修复最终包真实启动时发现的空连接误报绿灯问题。

本机 KEMI 状态订阅 IPC 只负责向观察者发布 Harness 工作快照，不再改变远程协同连接状态。只有经过认证的 Harness 远程数据通道和有效心跳才能显示绿色“协同已连接”；远程协助已打开但没有真实控制端时显示蓝色“协同等待连接”；显式关闭时不显示远程状态。

## 代码与回归

- 删除 App 根层把本机状态 IPC handshake/subscription/heartbeat 投影到 `RustDeskHarnessLinkStatusHub` 的错误耦合。
- Harness 状态发布器、RustDesk/P2P 载体和远程数据协议仍各自独立工作；macOS 与 Windows 共用同一 Dart 状态逻辑。
- dev.188–195 同批归档的实现还包括：统一设备 ID、P2P 优先/HBBR 回退、固定回环配对/协同/仿真端口、首次证书与授权范围固定、远端项目/会话/历史/发送/流式反馈/停止、远程仿真目录与工具调用、旧 Relay 版本接管、打开远程协助强制恢复载体，以及关闭能力时不污染 Harness 主界面。
- 远程层保持独立生命周期，不替换、重载或阻塞官方 Harness WebView；本机项目、会话、推理、插件市场、MCP、ADB 与普通工具仍按原路径运行。
- 定向分析 4 个生产文件：0 issue。
- 状态 IPC、远程状态、Harness/UI 定向回归：68/68 通过。
- 全量 Flutter 测试：851 项通过，19 项需要真实外部设备/显式联网环境的 live test 按条件跳过；无失败。
- Universal macOS 12+ Release 门禁通过：App、Harness、ADB、7-Zip、GitHub CLI、Git 均完整。

## 正式制品

- DMG：`/Volumes/ORICO/kemi-build-cache/vibekits-dev/run-20260912-dev195-formal/package/Vibekits-1.9.0.195+2195-macos-universal-notarized.dmg`
- 大小：`387538488` bytes
- SHA-256：`de3d5e0e848deebd70402ecb60b0f1614f1ab165af6670fcb49df9b4c46c3ea9`
- 兼容：Universal `x86_64 + arm64`，最低 macOS 12.0。
- 签名：`Developer ID Application: zhen ji (26T5WV4GLP)`；36 个 Mach-O 深度严格验签，Hardened Runtime 与安全时间戳有效。
- App 公证：Apple `Accepted`，Submission ID `5b5df8f2-747f-427b-b333-2bf95595ea5e`；App 已 staple/validate，Gatekeeper 为 `source=Notarized Developer ID`。
- DMG 公证：Apple `Accepted`，Submission ID `091d85e8-1d67-4a7f-a783-641e74e37037`；DMG 已签名、staple/validate，`hdiutil verify` 通过。
- 只读挂载后的内部 App 再次通过 Developer ID、staple、Gatekeeper、版本、双架构、macOS 12+ 和完整工具链门禁。

## 最终真实启动

- 从最终 DMG 只读挂载路径启动精确 App，Harness Web 正常进入工作区，版本显示 `v1.9.0-dev.195+2195`。
- App 自动启动包内 Relay；原生状态为 `routingId=1554650784`、`callable=true`、`rendezvousOnline=true`、`registrationKeyConfirmed=true`、`state=registered`。
- 原生连接表为 `state=idle` 且 `connections=[]` 时，主界面准确显示蓝灯“协同等待连接”，不再被本机状态 IPC 误显示为绿色已连接。

## 目标机安装后的剩余双机验收

1. 在目标 Mac `4456560334` 安装并启动本 DMG 内 dev.195，保持远程协助开关打开。
2. 完成首次比较码批准和证书范围固定。
3. 用默认 P2P 与强制 HBBR 各验证项目、会话、历史、发送、流式反馈、停止及断开清理。
4. 63/PAD 和 Windows 真机仍按各自在线条件完成对应平台验收；不得用本机测试替代。

## 发布与备份边界

- 本文“正式发布”指 Developer ID 签名、Apple 公证并完成 Gatekeeper 验收的 macOS 安装制品。
- 本轮没有上传 KEMI 商场，也没有声称 Windows 真机构建、PAD 协同或目标 `4456560334` 的 dev.195 双机闭环已经通过。
- Git 只归档源码、共享 Windows/macOS 逻辑、测试、构建脚本、需求规范和验收证据；`.codex-artifacts/`、`android/build/`、`dist/` 及 ORICO 可再生构建缓存不进入版本库。
