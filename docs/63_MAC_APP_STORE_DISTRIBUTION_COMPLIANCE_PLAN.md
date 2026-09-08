# VibeKits Mac App Store 发行合规方案

## 1. 结论

VibeKits 当前正式版是面向官网、KEMI 商场和第三方分发站的 Developer ID 版，不能把同一个二进制直接上传 Mac App Store。当前包含以下与 Mac App Store 规则直接冲突或需要单独权利申请的能力：

- KEMI 应用中心可下载并启动其他 App 安装包。
- 自有更新服务可下载并启动新版本；Mac App Store 版必须只经 App Store 更新。
- Harness、Node、Shell、ADB、Git、GitHub CLI、Mihomo/QEMU 等会执行子进程、操作用户工作区或连接外部设备。
- Release entitlements 当前没有 `com.apple.security.app-sandbox=true`，且需要网络服务端和串口权限。
- 系统清理、卸载辅助、任意路径读写等功能与 App Sandbox 容器边界冲突。

因此，只隐藏“应用中心”不足以通过审核。

## 2. 禁止审核规避

不实现“首次安装隐藏，使用三次后再显示应用中心”。这属于隐藏、休眠或未向 App Review 披露的功能，与 Apple App Review Guidelines 2.3.1(a) 直接冲突，也会使审核包与用户实际获得的行为不一致。

## 3. 双渠道产品架构

### Direct 版（现有产品）

- 用于官网、KEMI 商场、Uptodown 等站外分发。
- 保留 Harness/MCP、ADB、Shell、Git、设备调试、系统清理、应用中心。
- 使用 Developer ID Application 签名、Apple notarization 和 staple。
- 可保留手动站外更新，但不强制、不在启动时自动执行。

### Mac App Store 版（需新建合规产品变体）

- 使用显式构建渠道 `VIBEKITS_DISTRIBUTION=mac_app_store`，不使用运行次数、日期、远程开关或审核账号判断功能可见性。
- 从二进制及路由注册中永久移除应用中心、站外更新、下载安装其他 App 的能力，而不是只隐藏按钮。
- 启用 App Sandbox，通过用户选择文件和 security-scoped bookmarks 获得最小工作区访问。
- 只保留经证明可在 sandbox 内工作的阅读、OCR、压缩预览和非执行型开发工具。
- Harness/MCP 如果无法在 App Sandbox 内通过公开 API 完成，必须从 Mac App Store 版移除；不以下载外部 runtime 或调用未审核 helper 恢复。
- 使用 Mac App Distribution 证书、Mac Installer Distribution 证书和 Mac App Store Connect provisioning profile，以 Xcode Archive/Transporter 上传。

## 4. 当前机器证书门禁

2026-09-08 实查：

- 受限沙箱中的 `security find-identity` 曾误报 `0 valid identities found`；按项目签名手册改在正常 macOS 安全上下文复验后，实际可见 3 个有效 identity，包含 `Developer ID Application: zhen ji (26T5WV4GLP)`。
- `KEMI_NOTARY` 凭据可访问 Apple Notary Service，历史中有 VibeKits 和 KEMI 的 `Accepted` 记录。这些只证明 Developer ID 站外公证通道可用。
- `~/Library/MobileDevice/Provisioning Profiles` 中没有可用 profile，有效 identity 中也没有 Mac App Distribution/Mac Installer Distribution 发行证书。
- 现有 Release entitlements 没有 App Sandbox。

在上述三项未满足前，不得声称 Mac App Store 包可上传。Developer ID Application 只适用站外签名和公证，不等于 Mac App Store 发行证书。

## 5. 实施顺序与验收

1. 在 Apple Developer 后台确认 `com.caucy.vibekits` App ID，创建 macOS App Store 记录。
2. 接受 App Store Connect Business 中当前协议，确认账号具有 Account Holder/Admin/App Manager 权限。
3. 安装 Mac App Distribution、Mac Installer Distribution 证书和 Mac App Store Connect profile。
4. 完成 `mac_app_store` 变体，进行代码扫描，确认禁止能力不在包内，而不只是 UI 不可见。
5. 在新建用户和无开发环境的 macOS 机器上验证 sandbox、文件选择、网络、语言、升级方式和退出语义。
6. 在 App Store Connect 填写真实功能、隐私、审核说明、截图、支持 URL 和隐私政策 URL；不隐瞒 Direct 版的存在和差异。
7. 上传后只以 App Store Connect 显示的 build processing、Waiting for Review、In Review 或审核消息作为状态证据。

## 6. 权威依据

- Apple App Review Guidelines 2.3.1(a)、2.4.5、2.5.2：<https://developer.apple.com/app-store/review/guidelines/>
- Add a new app：<https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app>
- Upload builds：<https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds>
- Create a Mac App Store provisioning profile：<https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile>

## 7. Uptodown 与 Apple 审核不得混淆

Uptodown 的拒绝原因必须从 Uptodown 后台或通知邮件原文取证。Apple 规则可用于设计 Mac App Store 变体，但不能倒推 Uptodown 的实际拒绝理由。修改安装包前必须保留平台原始拒绝文本、应用 ID、版本和时间。
