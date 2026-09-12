# VibeKits dev.194 远程协助强制载体与状态闭环

日期：2026-09-12
版本：`1.9.0-dev.194+2194`

## 结论

dev.194 已完成本机精确安装包级闭环：远程协助打开/冷启动恢复时强制拉起 App 内置 Relay，首次尚无证书范围时保持等待而不报启动失败；未完成订阅的握手不再把主界面卡在“协同连接中”。关闭冷启动时不启动 Relay，主界面不显示远程状态。

目标 `4456560334` 仍未完成双机协同验收：P2P 与强制 HBBR 均能抵达目标设备，但目标当前候选没有开放首次配对回环端点 `32145`，返回 `HARNESS_TRANSPORT_transport_connect_failed`。需要在目标安装并启动本文的精确 dev.194 候选后，才能继续比较码批准、项目/会话、发送/反馈/停止的真实闭环。

## 实现边界

- `HarnessRemoteManagementBridge.startHost()` 只把 `REMOTE_PAIRING_SCOPE_NOT_PERSISTED` 视为首次配对等待；其他 Relay、监听或 Harness 后端错误继续向上返回。
- 官方 Harness 和回退 Harness 共用同一管理桥接和状态中心，Windows/macOS 不分叉两套业务逻辑。
- DeepSeek Harness 启动执行宿主前也先强制 `ensureCarrierAvailable`，不再依赖用户先打开额外页面。
- 握手未订阅在 6 秒后清理半连接；即使对端反复 hello，主界面也只显示蓝灯“协同等待连接”。只有证书/协议/订阅/心跳完整通过才显示绿灯“协同已连接”。

## 自动回归

- 完整矩阵 `202/202` 通过。
- 覆盖：默认开启/显式关闭持久化、首次等待、真错误失败关闭、证书固定、mTLS、项目/会话/历史、并发命令幂等、反馈、独立停止、撤权、PAD 仅控制端、紧凑屏滚动、远程仿真、集群安全等待、ADB、应用中心、LMCP、Windows Relay 共享合同以及原 Harness 项目/会话/并行/停止/删除/UI。
- 4 个受影响生产文件 `flutter analyze` 为 0 issue。

## macOS 候选

- DMG：`/Volumes/ORICO/kemi-build-cache/vibekits-dev/run-20260912-remote-fix/package/Vibekits-1.9.0.194+2194-macos-universal.dmg`
- 大小：`385421955` bytes
- SHA-256：`204b359866b9ef08b30383f1788192b14d730143b35388ac54a806318c1c666b`
- 兼容：Universal `x86_64 + arm64`，macOS 12+。
- 签名：`Developer ID Application: zhen ji (26T5WV4GLP)`；36 个 Mach-O 深度严格验签，Node v22.19.0 双架构/JIT/DSH 门禁通过。DMG 签名与 `hdiutil verify` 通过。
- DMG 只读挂载后真实启动；Harness Web 正常渲染，版本显示 `1.9.0-dev.194+2194`。
- 冷启动关闭态：只有 App 进程，无 Relay，无主界面远程状态条。
- 冷启动开启态：App 自动拉起包内 `vibekits-harness-relay --vibekits-harness-service`；状态查询为 `routingId=1554650784` / `callable=true` / `rendezvousOnline=true` / `registrationKeyConfirmed=true` / `state=registered`，连接列表为 `idle` 且空。

## 正式公证制品

> dev.194 虽完成 Apple 公证，但最终启动复核发现本机 KEMI 状态订阅 IPC 会被误显示为“协同已连接”，因此该制品已撤回，不得交付或上传商场。修复后的唯一交付版本为 dev.195。

- 正式 DMG：`/Volumes/ORICO/kemi-build-cache/vibekits-dev/run-20260912-dev194-formal/package/Vibekits-1.9.0.194+2194-macos-universal-notarized.dmg`
- 大小：`387434428` bytes
- SHA-256：`11094c385940c804aa32b780ab47bc462f80ea5f878fbce7679a3ebbd32d8083`
- App 公证：Apple `Accepted`，Submission ID `1a3e3c52-a5a5-48e3-a9a5-70b87715e57e`；App 已 staple/validate，Gatekeeper 为 `source=Notarized Developer ID`。
- DMG 公证：Apple `Accepted`，Submission ID `6cb470f9-0161-47e4-8a6a-8a5a715480c5`；DMG 已签名、staple/validate，`hdiutil verify` 通过。
- 最终 DMG 只读挂载复验：内部 App 深度严格验签、App 票据、Gatekeeper、版本 `1.9.0.194` / build `2194`、`x86_64 + arm64` 与 `minos 12.0` 全部通过。

## 尚未完成的真实门禁

1. 目标 Mac `4456560334` 安装并启动精确 dev.194，开启协同后确认 `32145` 首次配对端点。
2. P2P 与强制 HBBR 各完成比较码、证书范围、项目/会话/历史、发送/流式反馈/停止/断开清理。
3. 63/PAD 恢复在线后完成 PAD 控制端同版闭环。
4. Windows 58 在已核验主机指纹的 D 盘环境完成原生 Release 构建、启动与双机连接。
5. KEMI 商场上传不是本次“交付正式安装包供目标机验证”的范围，尚未执行；不得把本地正式制品误报为商场已更新。
