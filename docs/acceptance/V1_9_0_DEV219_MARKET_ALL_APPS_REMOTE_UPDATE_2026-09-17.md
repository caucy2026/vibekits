# dev219 应用市场全应用版本门禁与远程更新验收

状态：**BLOCK（2219 已安装，Harness 启动与仿真通道未验收通过）**。源码基线为 `276d971` 加本工作区未提交修改。

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
- 远端安装调用在客户端超时后仍在目标机继续，Harness 未重复安装。远端观察到解包、Gatekeeper 检查、`/Applications/Vibekits.app` 版本 `1.9.0-dev.219+2219`，并曾启动该路径的进程约 12 秒，未见即时崩溃报告。此后仿真通道被设备端拒绝，无法核对 Harness 是否正常启动；不能称为 PASS。目标机原先用于仿真连接的进程来自 `~/Library/Caches/Vibekits.app` dev217，而非 `/Applications` 中旧版。
- 源码中发现升级恢复失败的处理会把已有 `harness-simulator-v1-enabled=true` 写为 `false`。这与本次连接丢失现象吻合，但没有目标机新版本启动日志证明它是唯一原因。dev220 已针对该恢复逻辑添加保留授权和自动重试；见后续候选包。
- 线上市场规范页面因网络 DNS / Web 安全层不可达，已按本地 2026-09-10 技能标准实施；线上契约一致性尚未复核。Windows 和 Android 原生端未在对应平台完成编译与真机验收。

后续完成门禁：先恢复目标设备的仿真入口，然后公证、装订、安装 dev220，并在目标机核对 Harness 启动和仿真通道稳定性。
