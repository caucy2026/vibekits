# VibeKits dev.166 外部分发状态（2026-09-10）

## 结论

- Uptodown：VibeKits 当前为 `REJECTED`，不是已发布状态。
- Mac App Store：尚未上传，也未进入 App Review。
- 新候选：`1.9.0-dev.166+2166` Universal macOS 12+ 包已完成 Developer ID 签名、Apple 公证、staple 与 Gatekeeper 验证，可用于 Uptodown 等站外分发；它不是 Mac App Store 安装包。
- KEMI传书：本轮未取得可重复读取的实时页面正文，不以旧记录冒充当前状态。

## Uptodown 实时证据

应用记录：VibeKits，Uptodown app ID `1000852511`。

通知中心显示两次拒绝：

- 2026-09-09 16:27：`VibeKits - has been rejected`
- 2026-09-08 14:30：`VibeKits - has been rejected`
- 两次理由一致：`We're sorry, but your app doesn't meet the minimum quality standards to be published on Uptodown.`

被拒文件信息：

- Version：`1.9.0-dev.162`
- Version Code：`1788869922`
- 类型：Final Release
- 最低系统：macOS 12 Monterey
- 大小：277.21 MB
- MD5：`da670c883602056e9edcc9e8c62abcaf`
- SHA256：`d3522b62354dfaa6da2f28918313fa39f51a7fb64d062e752cf1f1239d606820`

商店资料已包含名称、分类、官网、年龄分级、英文短描述和完整描述。现有三张英文截图仍处于 `Pending approval`，且画面分别存在空白/失败态、设置弹窗、密集日志等问题，不适合作为最终商店素材。

结合 Uptodown 公布的发布标准，最可能的拒绝触发项是旧 dev.162 的启动/异常退出质量问题和截图质量，而不是缺少基本元数据。该判断属于证据推断，最终拒绝细项仍以 Uptodown 审核方为准。

## dev.166 修复候选

文件：`bin/release/Vibekits-1.9.0-dev.166+2166-macos-universal-notarized.zip`

- 架构：`arm64 + x86_64`
- 最低目标：macOS 12+
- 大小：299,242,321 bytes
- SHA256：`bbe009418e3ae58f0818b295bfc967cb99919397a57d4586c46e4abd47b60192`
- 签名：`Developer ID Application: zhen ji (26T5WV4GLP)`
- Apple 公证：Accepted
- Submission ID：`d5d8170c-85e7-47c0-87be-fa7cce41d0e2`
- Staple：通过
- Gatekeeper：Accepted，来源 `Notarized Developer ID`
- 内置 Harness：Node 22.19.0，ARM/Intel 启动验证通过

重新提交 Uptodown 前还需要：替换三张高质量、与 dev.166 一致的真实截图；上传 dev.166；复核描述；最后点击 `SUBMIT FOR REVIEW`。

## Mac App Store 门禁

本机已有 App Store provisioning profile：

- App ID：`26T5WV4GLP.com.caucy.vibekits`
- Team：`26T5WV4GLP` / `zhen ji`
- 有效期：2026-09-08 至 2027-09-08
- Profile 引用证书：`Apple Distribution: zhen ji (26T5WV4GLP)`

当前仍不能构建可上传商店的归档，原因：

1. 本机钥匙串没有带私钥且可用于 codesign 的 `Apple Distribution` identity；只有 Developer ID 与本地开发 identity。
2. 当前 Release 工程仍是站外分发配置：`CODE_SIGN_IDENTITY=-`、`DEVELOPMENT_TEAM` 为空、Hardened Runtime 未在该构建设置中启用。
3. Release entitlements 未启用 `com.apple.security.app-sandbox`。Mac App Store 分发需要单独的沙盒/商店 target，并逐项处理文件、进程、网络和内置工具权限，不能把 Developer ID 包直接上传。
4. App Store Connect 当前停在登录页，尚无可核验的应用版本、构建上传或审核记录。

因此准确状态是“开发者资料已开始准备，但 VibeKits 尚未提交 Mac App Store”，不能表述为等待审核。

## 两个产品的状态边界

| 产品 | Uptodown | Mac App Store |
|---|---|---|
| VibeKits | 已实时证实为 `REJECTED`；dev.166 已准备重新提交 | 未上传、未审核；商店签名私钥和 Sandbox target 仍缺 |
| KEMI传书 | 本轮实时页面读取受浏览器会话占用，状态待独立复核 | 本轮无已验证的上传/审核证据 |

## 后续动作

1. 为 VibeKits dev.166 生成并核验三张干净、可读、无失败态的英文商店截图。
2. 将 dev.166 ZIP 和新截图上传 Uptodown，提交复审。
3. 单独复核 KEMI传书 app ID `1000852583` 的实时文件、素材和审核状态。
4. 获取 Apple Distribution 私钥后建立独立 Mac App Store target，完成 Sandbox 兼容改造、Archive/Validate，再创建 App Store Connect 记录并上传审核。
