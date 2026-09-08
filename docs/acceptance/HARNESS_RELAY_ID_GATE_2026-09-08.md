# Harness 独立中继 ID 阶段验收（2026-09-08）

## 结论

Harness 远程协助不再使用 `VH-...` 证书标签或 KEMI 远程办公 ID 作为路由 ID。RustDesk 配套网络引擎已增加独立 `VibekitsHarness` 配置/IPC 命名空间以及 service/get-id/status 三个控制命令。只有 HBBS 在线、注册公钥已确认且服务端 ID 为 6～16 位纯数字时，VibeKits 才将本机 ID 标记为可呼叫。

2026-09-08 用户明确授权注册后，真实候选先暴露出“仅隔离配置仍会按同一网卡 MAC 生成相同初始 ID”的缺陷：第一次服务端确认结果错误复用了远程办公 ID `260262802`。该结果已拒收，服务随即停止。随后补充一次性身份迁移：Harness 命名空间首次启动生成并持久化独立 10 位候选 ID、清除旧注册确认，再交给 HBBS 做冲突处理和最终确认。

修复后首次注册以及停止、重启后的两次只读状态均为：

```json
{"routingId":"1554650784","callable":true,"rendezvousOnline":true,"registrationKeyConfirmed":true,"state":"registered"}
```

因此当前服务器确认的 Harness 独立路由 ID 为 `1554650784`，与远程办公 ID `260262802` 不同；重启后 ID 保持不变。专用服务在本次验收结束时继续运行。

后续网络引擎增量验证同时返回：

```json
{"ok":true,"state":"idle","connections":[]}
```

这证明 HBBS 注册 IPC 与首次连接授权 IPC 可以同时运行。对不存在的 `connectionId=999999` 执行允许操作得到 `connection_not_found`，没有误授权。授权列表只暴露目标为 Harness 本机回环服务的端口转发请求；其他连接类型不进入列表且在服务端拒绝。

## 服务器与数据边界

- 内置 HBBS：`kemi-chat.newlinksz.com:21116`；
- HBBS 接收 RustDesk 原生注册字段：候选数字 ID、独立 UUID、独立注册公钥和旧 ID（仅发生换号时）；
- HBBS 负责注册、寻址与打洞；HBBR 仅在直连失败时原样中继端到端加密字节；
- 注册阶段不发送 Harness 项目、会话、提示词、工具参数、文件正文、API Key 或桌面画面；
- Harness TLS 证书指纹在端到端配对中核验，不作为服务端路由 ID。

## 自动验证

- RustDesk `cargo check --lib --no-default-features`：通过；
- RustDesk `vibekits_harness_relay` 单元测试：2/2 通过；
- VibeKits 远程模块与中继 UI/状态解析回归：42/42 通过；
- VibeKits 定向静态分析：无问题；
- macOS ARM64 App：构建成功，57.2 MB；
- 独立身份修复后的 Rust Release 全量编译：通过；
- 真实 HBBS 注册：首次与重启复查均为 `registered/callable/keyConfirmed`；
- Rust 首次授权控制 IPC、无桌面连接管理器、回环隧道范围限制：编译检查通过；
- Flutter hello/心跳、mTLS、项目状态、断线保留、授权解析和 UI 定向回归：15/15 通过；
- Flutter 定向静态分析：7 个改动模块无问题；
- 控制端已增加 `--vibekits-harness-tunnel <routingId> <localPort> 127.0.0.1 32146` 参数数组启动器，默认直连失败自动 HBBR，也支持显式 `--relay` 强制中继；数字 ID、端口和回环目标均在启动前约束。相关中继、mTLS、心跳、断线保留和只读项目 UI 定向测试 13/13 通过，静态分析无问题；
- 正式远程分享面板已显示对端数字 ID 输入、连接按钮和强制中继验收开关；执行端仍显示实时等待授权调用方并提供拒绝/允许本次连接。仅启动端口转发不会把 UI 标记为已连接，必须继续通过证书、授权、hello、快照门禁；
- 中间 macOS dev.160 候选在补齐固定版本 Harness/7-Zip Runtime 后构建成功，但发现并行快照已使用 dev.162，因此该版本按防回退规则作废；当前源码已统一提升为 `1.9.0-dev.163+2163`。锁文件漂移已拒收并恢复到 Git 基线哈希，随后使用锁定依赖重新构建成功（769.6 MB）；Info.plist 为 `1.9.0.163 / 2163`，LMCP revision 为 `2163`，主程序 `x86_64 arm64`、两切片 `minos 12.0`，完整 Harness/ADB/7-Zip/GitHub CLI/Git 兼容门禁与 ad-hoc 深度验签通过。当前仍不是 Developer ID 正式包；
- 以本机 `1554650784` 对自身发起强制中继预检时，授权队列保持 `idle`；HBBS 不把同一注册身份路由给自身。这一结果只说明“单机自呼不能替代双端验收”，不能证明真实双机隧道成功或失败。配套服务日志同时显示 21114 业务心跳端点拒绝连接，但 21116 原生注册状态仍为 `registered/callable`，两者不得混淆；
- 该时点本地签名身份曾不可用，因此当时没有生成正式签名包；后续恢复结果见“2026-09-09 续跑结果”。
- 该时点 Apple 时间戳服务不可用，按规则没有把候选冒充正式外发包；后续已完成 Developer ID 与时间戳签名，但尚未完成公证。

## 未完成门禁

1. 首次证书交换、持久授权、受管 PORT_FORWARD 生命周期、mTLS/hello/快照、项目/会话状态、发送/反馈/独立停止及断开已完成代码接线；自动回环服务、真实 mTLS 和共享 UI 回归共 `46/46` 通过。仍需两台不同 Harness routingId 做真实直连与强制 HBBR 现场验收；同一 ID 自呼不能替代此门禁。
2. 当前远程面板显示官方项目/会话状态并通过白名单调用官方 API，但尚未把完整官方聊天历史和逐步工具事件注入同款 DSH Web UI；当前不得宣称“远程与本地视觉/交互完全一致”。
3. Android/63 尚未打包独立 Harness RustDesk 网络引擎，不能执行本机↔63 真机闭环；需完成 Android native 入口、签名 APK 和 63 在线后再验收。
4. Developer ID 与 Apple 时间戳签名已于后续续跑完成；仍需公证、装订与 Gatekeeper/真实下载闭环，当前候选不可进入正式 `bin` 或商场。

未通过上述门禁前不得声称远程协助或中继交付完成。

## 2026-09-08 20:42 增量结果

- Flutter 低并发组合回归 `46/46` 通过：首次回环配对、证书/身份/范围校验、v1→v2 授权存储、受管隧道关闭、真实 mTLS、hello/心跳、项目/会话快照、断线 stale、发送反馈、独立停止和主界面均覆盖；定向 analyze 为 0 issue。
- RustDesk `cargo test --lib vibekits_harness_relay --no-default-features` 为 `2 passed / 0 failed`，确认独立命令映射和 HBBS 注册确认门禁。
- 最新 dev.163 源码已重新增量构建 macOS Release，产物 `build/macos/Build/Products/Release/Vibekits.app` 为 770.0 MB；版本 `1.9.0.163 (2163)`，主程序 `x86_64 arm64`，完整 Harness/ADB/7-Zip/GitHub CLI/Git macOS 12+ 兼容脚本通过，深度验签通过。签名仍为 `adhoc / TeamIdentifier not set`，所以不复制到 `bin`、不公证、不发布。
- 候选内置 ADB 在解除沙箱后真实列出 `192.168.3.63:5555 device`。63 当前安装 `com.vibekits.vibekits` 为 `1.9.0-dev.160 (2160)`、`arm64-v8a`，不是本轮 dev.163，且未证明含独立 Harness RustDesk 网络引擎；因此只记录“设备在线与旧包可读”，不冒充真双机闭环。
- Windows 节点 `192.168.3.58` 的 ED25519 指纹与受信文档 `SHA256:ikZ6NXAH3VFBGooSCeKW0JY9+h0cIcQOzib4fxmvz6M` 精确一致，公钥登录及 PowerShell 7.6.5 通过；系统为 Windows 10.0.19045.6466。但 D 盘只余 `31,780,134,912` bytes（约 29.6 GiB），低于节点合同的 30 GiB 门禁，且复核时仍有两个 Dart 构建进程。未删除远端数据、未并发启动 VibeKits 构建，Windows Release 状态保持 `blocked_by_node_capacity`，不能以共享 Dart analyze 代替真机构建。

## 2026-09-09 续跑结果

- 在历史连接与受管断开接线完成后，重新执行远程协助定向组合回归：`39 passed / 0 failed`；随后新增远程会话独立草稿切换测试（`s1=111 → s2=222 → s1/s2` 均恢复）并通过，当前该组累计 `40 passed / 0 failed`。覆盖独立 Harness ID 状态、受管 tunnel 关闭、首次配对等待明确批准、证书与授权范围固定、v1/v2 授权记录、真实回环 mTLS、hello/心跳、项目与会话快照、断线 stale、显式发送、执行反馈和独立停止。8 个生产文件定向 `flutter analyze --no-pub` 为 `No issues found`。
- 按当前源码重新构建精确 macOS Release：`build/macos/Build/Products/Release/Vibekits.app`，版本 `1.9.0.163 (2163)`，大小 770.1 MB，主程序为 `x86_64 arm64`。Harness、ADB、7-Zip、GitHub CLI、Git 与 macOS 12+ 完整兼容脚本通过。
- 兼容脚本会准备包内 Mach-O，因此脚本执行后必须重新签名。独立草稿修复合入后已重新构建，并按“兼容验证在前、最终签名在后”的顺序，从内到外使用 `Developer ID Application: zhen ji (26T5WV4GLP)`、Hardened Runtime 与 Apple 安全时间戳重新签署 35 个 Mach-O；`codesign --verify --deep --strict`、Team ID 一致性和内置 Node/DSH 双架构运行时检查通过。此结论只表示“Developer ID 已签候选”，尚未提交本版本 Apple 公证、staple、Gatekeeper 与真实下载链路，所以仍不进入 `bin`，不称正式包。
- 63 真机只读核对显示 `com.newlinksz.kemi.remote 1.4.118 (225)` 与 `com.vibekits.vibekits 1.9.0-dev.160 (2160)` 的 PackageManager 签名标识同为 `b4addb29`。这使“同签名权限 + 显式 bound service”的 Android 安全桥接方案成立，但现有 KEMI Android Rust 核心把 PORT_FORWARD 主循环编译排除在 Android/iOS 之外，也没有独立 Harness engine 的 Binder API；仅有同签名并不等于隧道已实现。不得降级复用 KEMI 远程办公 ID，也不得用任意 shell/开放 Binder 伪造闭环。
- Windows 58 再次复查时 Dart/MSBuild 均已退出，但 D 盘余量为 `31,637,327,872` bytes（约 29.46 GiB），仍低于真机实验室规定的 30 GiB。没有擅自删除旧源码归档或其他项目资产，因此本轮仍未启动 Windows 构建。

### 当前剩余硬门禁

1. Android 需要在 KEMI/RustDesk 中提供同签名保护、固定方法白名单的独立 Harness 网络服务，并补齐 Android PORT_FORWARD 数据通道；VibeKits 只绑定该服务。完成签名 APK 后才能在 63 验收不同 routingId、首次授权、直连/HBBR、发送/反馈/停止/断开。
2. 控制端目前以原生远程面板显示项目/会话、发送和反馈；完整官方 DSH 对话、推理与工具时间线尚未通过官方 transport adapter 重放，不能宣称与本地视觉和全部操作完全一致。
3. Windows 节点需先由设备维护方安全释放至少约 600 MiB，使 D 盘达到 30 GiB 门禁，再同步精确源码、D 盘增量构建和真机安装回归。
4. 当前 Developer ID 候选仍需 Apple Notary `Accepted`、staple、Gatekeeper 与真实下载哈希闭环。远程协助第 1～3 项未完成前不提前发布。
