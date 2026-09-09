# VibeKits dev.164 Android Harness 远程协助阶段验收

状态：真实配对与隧道分层验证已取得进展，但“实际工作区命令/反馈/停止”仍未闭环，正式发布门禁未通过。

## 构建与端点

- VibeKits：`1.9.0-dev.164+2164`；本轮 Android arm64 包仅为 `/private/tmp/Vibekits-dev164-remote-final-diagnostic.apk`，SHA-256 `bd726f23fa0370fa8d74ce88c46a43f822093e57eca24ec60a71564a8e43fbc1`，没有进入 `bin`。
- 63：ADB `192.168.3.63:5555`；Harness routing ID `2414198129`；真实 workspaceId `/data/user/0/com.vibekits.vibekits/files/Vibekits/workspace`。
- Mac：Harness routing ID `1554650784`；重建后的 helper 为 `/Users/newlink/kemi/RustDesk/client/target/release/vibekits-harness-relay`。
- 固定回环协议端口：`32145` 仅首次证书配对；`32146` 仅配对后 mTLS 状态/命令会话。其他回环端口、非回环地址和 LAN 目标一律拒绝。
- 诊断 APK 使用 63 已接受的平台测试证书签名，SHA-256 `c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8`；它不是商场发布签名。

## 已完成并有证据

1. Mac helper 的 HBBS 状态返回 `routingId=1554650784`、`callable=true`、`rendezvousOnline=true`、`registrationKeyConfirmed=true`。
2. 真实 RustDesk/HBBR `32145` 首次配对曾完成，63 明确确认并持久化调用方 `1554650784`，双方比较码 `400846`。截图：`/private/tmp/run7-success.png`。
3. 63 真实显示已配对设备 `1554650784`；不是用静态假连接生成。截图：`/private/tmp/session-native.png`。
4. 真实 `32146` 隧道完成过 mTLS/hello；当时授权范围误为占位 `workspace`，所以快照返回空 workspace。此结果只证明隧道和认证可达，不算业务闭环通过。
5. 已配对且证书仍有效的调用方，其原生连接会自动授权；窗口持续展示“正在使用 Harness”、调用方 ID、connectionId 和“强制断开”。未知/未配对证书仍由 mTLS/peer store 在协议层拒绝。
6. 远程协助窗口每两秒同时刷新中继注册与连接快照，支持“提供方先启动、VibeKits 后打开”的晚发现；关闭/停止会依次关闭控制会话、配对监听、远程 Host、受管 tunnel 和 Android 独立中继。
7. 修复紧凑/旋转 Android 屏上对话框超过可触控安全区的问题：内容高度限制为屏幕的 72%，统一滚动；首次证书授权卡置于连接历史与设备列表之前，确认/拒绝不再埋在不可触控区域。
8. VibeKits 定向回归 30/30：紧凑屏布局、首次批准/拒绝、持久 peer、mTLS、权限范围、状态同步、历史命令、取消、撤权、并发幂等、断开生命周期全部通过。
9. 本轮 5 个改动/验收文件 `flutter analyze --no-pub`：`No issues found`。
10. RustDesk 精确端口测试：`1 passed; 0 failed`，并已重新编译 Release helper。测试覆盖允许 `127.0.0.1:32145`、`localhost:32146`，拒绝 `32147`、SSH 22、`0.0.0.0` 和 LAN 地址。
11. 63 安装和启动成功；最新真机 UI 截图：`/private/tmp/63-pairing-safearea-fixed.png`。
12. 2026-09-09 后续修复取消了“本地 worker/listener 等于远端可用”的错误假设：桌面 helper 只有在 RustDesk `ConnectionRoundState=Connected` 后才开放回环转发并输出 `transport_connected`；25 秒未连接输出 `transport_connect_timeout`、退出码 2。Flutter 受管进程必须读到该结构化成功状态才返回 lease，原生错误会直接上抛，旧 helper 的 `listening` 不再被接受。
13. 新增构建防回归：Cargo target `vibekits-harness-relay` 强制 `required-features=["flutter"]`；macOS 发布脚本在复制 helper 前检查 `transport_connected` 与 `transport_connect_timeout`，杜绝无 Flutter 功能的空壳二进制静默退出 0 后进入正式包。
14. 后续定向验证：Rust 状态机 3/3；Flutter share/controller/pairing 15/15；6 个核心实现/测试文件 `flutter analyze --no-pub` 为 `No issues found`。最终正确 feature 的 ARM64 Release helper 已重新构建。

## 当前未通过

- 首次成功配对授予的是占位 scope `workspace`，不是 63 的真实 workspaceId；因此不能把那次配对用于最终项目/会话命令验收。
- 本轮尝试重新授权真实 workspace 时，63 原生连接 `1076` 确实从 `authorized=false` 变为 `authorized=true` 并保持约 30 秒，但配对正文没有经强制 HBBR 数据面到达 `127.0.0.1:32145`。旧实现最终为 `PAIRING_CHANNEL_CLOSED`；新 helper 已把故障提前并准确收敛为 `transport_connect_timeout`，不再制造本地 listener 假成功。
- 63 本机 `32145/32146` 均在监听；直接在 63 回环向 `32145` 发送 `{}` 可立即得到标准 `PAIRING_BAD_REQUEST`，证明应用监听端正常。受控 RustDesk tunnel 探针能建立本机 listener，却收不到远端响应，故故障边界在当前强制中继数据面而非 JSON/证书 UI。
- Mac Harness 服务日志同时持续记录 `kemi-chat.newlinksz.com:21114` 的 heartbeat/sysinfo `Connection refused` 及 TCP fallback timeout；在此之后没有新的 63 `connection changed` 事件。TCP 21116/21117 当前可达、21114 拒绝。最终 helper 对 routing ID `2414198129` 的强制 HBBR 实测为 25.93 秒、退出码 2、`transport_connect_timeout`，63 入站连接快照持续为空。
- 尚未取得真实 workspace 的 `state → session.history → session.cancel → heartbeat → close` 全链路输出，也未完成真实“强制断开”点击后的调用方错误码验证。
- 本轮没有 Windows 真机构建；共享 Dart 状态/命令逻辑通过不等于 Windows 真机通过。
- 没有 Developer ID、公证或正式发布包；不得复制到 `bin`、上传商场或声称 dev.164 已发布。

## 下一门禁

1. 强制 HBBR 服务恢复后，以真实 workspaceId 重新配对并记录新的比较码。
2. 运行 `manual_real_harness_remote_session_test.dart`，保存脱敏 workspace/session、history/cancel 结果键、RTT、事件数和关闭状态。
3. 连接存活时在 63 验证“正在使用 Harness/强制断开”；断开后原生 connections 必须为空，调用方得到明确终止结果。
4. 再做 LAN 直连、断线恢复、Mac/Windows 真机、签名/公证和正式包门禁。
