# dev219 应用市场全应用版本门禁与远程更新验收

状态：**部分通过（dev219 已安装；远程仿真重连与下载目录实例的 Harness 启动已验证，`/Applications` 实例的 Harness 尚未单独验收）**。相关源码已纳入 `713aea4`，当前 `main` 为 `74a3bad`。

## 已完成

- 市场每个条目以当前 OS 和稳定包名查询本机安装状态及真实整数版本码。macOS 读取 `CFBundleIdentifier` / `CFBundleVersion`，Windows 读取安装登记 `VersionCode`，Android 读取 PackageManager `longVersionCode`。Android 查询使用实际 `applicationId`，不会把跨平台商品包名误作安装包名。
- 卡片和详情显示更新状态；同码、云端较低、版本未知、安装查询失败及不完整包禁止下载；下载入口在创建临时文件和发起 HTTP 请求之前再次读取本机版本。平台字段冲突和格式不符的包也禁止安装。
- 通过 `flutter test test/app_center_test.dart test/app_update_service_test.dart`（27 项）及 `flutter analyze lib/features/app_center test/app_center_test.dart`。macOS Universal Release 编译成功，版本 `1.9.0-dev.219+2219`，macOS 12+ Harness 完整性检查通过。Developer ID `26T5WV4GLP` 签名及深度验签通过，35 个 Mach-O 文件已核验。
- 仿真设备 `1321656264` 通过 VibeKits P2P/relay 连接、身份一致且 SSH/MCP 可用；设备应用清单显示 `/Applications/Vibekits.app` 为 `1.9.0.160+2160`。本次只读核查后已断开。

## 公证与目标机状态

- 候选 App：`/Volumes/ORICO/kemi-build-cache/app-release-gate/vibekits/macos/dev219-market-version/derived/Build/Products/Release/Vibekits.app`
- 公证候选 ZIP：`/Volumes/ORICO/kemi-build-cache/app-release-gate/vibekits/macos/dev219-market-version/Vibekits-dev219-notarization.zip`
- ZIP 长度：`317075991` 字节；SHA-256：`5c7e56187dad29fdfa7322a9679e431c0f1a23ddfbca187ecfdb29c323f2e714`。
- 用户明确允许上述 ZIP 上传 Apple 公证服务后，提交编号 `c7535aea-a036-4687-8e2a-c2a94809a997` 获得 `Accepted`。App 已装订票据；`stapler validate`、深度签名校验和 Gatekeeper `source=Notarized Developer ID` 均通过。
- 装订后第一份最终 ZIP 使用 `ditto --sequesterRsrc`，SHA-256 `446b815d474febec69aabcc392fa4167b234d95c85b8e8e15a75a56a73192d5f`，大小 `317078898` 字节。目标机旧版安装器不接受 ZIP 内的 `__MACOSX` 元数据根目录，因此 Harness 在安装前停止，旧版未被替换。
- 同一已公证 App 已重新打为单根目录 ZIP：`/Volumes/ORICO/kemi-build-cache/app-release-gate/vibekits/macos/dev219-market-version/Vibekits-dev219-clean.zip`；大小 `315470254` 字节，SHA-256 `fe096cb0878a871acd4640d13681e421615f0a9e5d06bff0bf31c3e8fcab00fc`。本机实际解包后 `stapler validate`、深度签名校验与 Gatekeeper 均通过。自动审批曾拒绝新哈希包的提交；用户随后明确同意该精确包与设备后，Harness 可见会话完成上传和远端安装。
- 远端安装调用在客户端超时后仍在目标机继续，Harness 未重复安装。此前观察到解包、Gatekeeper 检查、`/Applications/Vibekits.app` 版本 `1.9.0-dev.219+2219`，并曾启动该路径的进程约 12 秒，未见即时崩溃报告。随后一度连接被重置；这本身不能证明目标应用或 Harness 启动失败。
- 设备所有者重新启动 VibeKits 后，2026-09-17 再次通过 ID `1321656264` 连入，连接返回 `connected=true`、身份 `macdeMac-mini-2.local`、`transport=p2p_or_relay`、SSH/MCP 就绪。应用清单及直接读取目标机文件一致：`/Applications/Vibekits.app` 和 `/Users/mac/Downloads/vibekits-simulator-1321656264/Vibekits.app` 均真实存在，均为 `1.9.0-dev.219+2219`。当前前台 App 进程及 Harness Node/MCP 子进程来自**下载目录实例**；`/Applications` 路径有 `vibekits-harness-relay` 服务进程。这解释了此前只给出 `/Applications` 路径却与设备所有者当前所见不符。核查结束已断开仿真连接。
- 源码中发现升级恢复失败时旧逻辑会把已有仿真授权写为 `false`，dev220 针对此逻辑添加保留授权和自动重试。但本次重连后未取得证据证明它曾是断线根因，也未在目标机部署 dev220，不应把源码假设写成现场故障结论。
- 线上市场规范页面因网络 DNS / Web 安全层不可达，已按本地 2026-09-10 技能标准实施；线上契约一致性尚未复核。Windows 和 Android 原生端未在对应平台完成编译与真机验收。

后续门禁：若要验收 `/Applications` 安装实例，应明确从该路径启动并检查其 Harness；dev220 仍只是候选，需按独立发布门禁验证。下载目录实例已证明 dev219 的 Harness 可启动，但尚未完成长期稳定性验收。
