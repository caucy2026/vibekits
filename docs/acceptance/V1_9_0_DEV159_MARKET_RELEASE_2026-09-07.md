# VibeKits 1.9.0-dev.159 双平台商城发布验收

## 发布范围

本轮仅更新 KEMI 应用商场既有的 macOS 与 Windows 记录，不发布到 Newlink Common 云端，不创建重复应用。

- 包名：`com.caucy.vibekits`
- macOS：`app_id=53`
- Windows：`app_id=54`
- 版本：`1.9.0-dev.159`，`version_code=2159`
- 产品构建源码提交：`0799c0ebee5129326822bd49ae112eb1032cc66e`
- 商城策略：展示、非强制更新

## GitHub 构建来源

- macOS run `34115703453` 成功；artifact `10016389800`，内层候选 SHA-256 `a9e070848c163c678f84b240924dc366f457bcffb3b03281d8f1c80c9bbe4ef7`。
- Windows run `34115703573` 成功；artifact `10016493551`，外层 artifact 为 292,093,399 bytes，SHA-256 `a25901fbc00bdd72d24d8e354417295b5d3ed12a2032a33a37edf9c097ced4f7`。
- Windows 内层 ZIP 的摘要与流水线 `.sha256` 文件一致：`24928b3741914ddf879df8c3bde3bdb71e9efc8a201cc482cc4c08428f5ea334`。

## macOS 正式认证

- 最终包：`bin/release/Vibekits-1.9.0-dev.159+2159-macos-universal-notarized.zip`
- 大小：289,331,928 bytes
- SHA-256：`93d6a4bc3677f7ec5379597bae2205a086abb50a9162e5b6c1ee0d06cc9e9bfd`
- 架构：Universal `x86_64 + arm64`
- 最低系统：macOS 12.0
- 签名：`Developer ID Application: zhen ji (26T5WV4GLP)`
- Apple 公证：`Accepted`
- Submission ID：`1ba3e8d4-8bcc-4cf8-931a-61e0359158ed`
- 34 个 Mach-O 深度签名通过；候选真实启动并验证本地 Harness 桥；`stapler staple`、`stapler validate`、签名运行时检查和 Gatekeeper 均通过，Gatekeeper 来源为 `Notarized Developer ID`。
- 外部模型 smoke 未启用，没有向外部模型发送 LAN MCP 元数据。

## Windows 真机验收

- 最终包：`bin/release/Vibekits-1.9.0-dev.159+2159-windows-x64.zip`
- 大小：299,191,243 bytes
- SHA-256：`24928b3741914ddf879df8c3bde3bdb71e9efc8a201cc482cc4c08428f5ea334`
- 真机：`192.168.3.58` / Windows 10.0.19045；固定 ED25519 指纹 `SHA256:ikZ6NXAH3VFBGooSCeKW0JY9+h0cIcQOzib4fxmvz6M` 核对一致。
- 传输、解包和运行均位于 `D:\KEMI-Test\vibekits-dev159`；真机复算大小与 SHA-256 和 Mac 端完全一致。
- `verify_windows_bundle.ps1` 通过 33 项必需运行时检查；版本为 `1.9.0-dev.159+2159`，内置 Git `2.55.0.windows.3`，GitHub CLI `2.100.0`。
- 三次隔离启动均在 5 秒检查点存活，工作集分别为 79,163,392、97,943,552、93,007,872 bytes；每次只停止精确测试 PID。
- Authenticode 状态为 `NotSigned`。本包只满足负责人此前明确接受的未签名 Windows 测试包发布范围，不能描述为已签名正式包。

## 本版变化

- 当前客户端版本大于或等于商场版本时，应用中心显示“已是最新版”并禁用重复下载。
- macOS 与 Windows 均关闭启动自动升级检查、升级弹窗和自动下载，避免反复提示和无法完成的升级循环。
- 更新接口严格校验 `has_update` 类型；服务端误报更新但远端版本不高于本地时按“当前版本”处理。
- 更新 Mihomo `latest` 发布中已变化的 `geosite.dat` 固定 SHA-256，继续保持供应链严格校验。

## 商城闭环

- 2026-09-07 已更新既有记录，未创建重复应用：macOS `app_id=53`、Windows `app_id=54` 的管理员详情均显示线上版本 `1.9.0-dev.159`；两端保持 `list_in_store=true`、`force_update=false`。
- macOS 公开详情返回 289,331,928 bytes、SHA-256 `93d6a4bc3677f7ec5379597bae2205a086abb50a9162e5b6c1ee0d06cc9e9bfd`，CDN：`https://cdn.newlink-sz.com/kemiAppStore/macpkg/2026/09/1788782099427_c1a352eb_Vibekits-1_9_0-dev_159_2159-macos-univer.zip`。
- Windows 公开详情返回 299,191,243 bytes、SHA-256 `24928b3741914ddf879df8c3bde3bdb71e9efc8a201cc482cc4c08428f5ea334`，CDN：`https://cdn.newlink-sz.com/kemiAppStore/winpkg/2026/09/1788786506330_b92b8f0c_Vibekits-1_9_0-dev_159_2159-windows-x64.zip`。
- 两个 CDN 包均完成全量回下载；实测字节数与 SHA-256 和公开详情、发布源完全一致。回下载 macOS 包的再次解压验签因系统临时卷仅余约 109 MiB 而失败，此项不计通过；上传前同 SHA 源包的 Developer ID、公证、staple、深度签名和 Gatekeeper 验证已经通过。
- 更新接口正向检查：macOS/Windows 的本地 `version_code=2158` 均返回 `has_update=true`、目标 2159、精确平台 URL/大小/SHA。
- 更新接口负向检查：macOS/Windows 的本地 `version_code=2159` 均返回 `has_update=false`，且 `download_url`/`apk_url` 为空；当前版本不会再次提示或允许重复下载。
- 本轮只更新 KEMI 应用商场，没有发布到 Newlink Common 云端。

## 外部分发状态

### 2026-09-08 后台实时复核

已使用原有独立网站凭据成功登录 Uptodown。`Your Apps 2` 表格实际显示 VibeKits 与 KEMI Send，两项状态均为 `Pending revision`，Publication date 与 Last update 均为 `-`。这证明原有条目存在，但不能声称已正式上架。后续详情操作再次超时，尚未读取编辑意见；不据此推断需要重新提交。以下早前“实时状态待复核”记录已由本次表格证据更新。

- Uptodown 状态更正（2026-09-08）：此前把邮箱授权码误用作网站密码，登录失败不能证明尚未注册或提交。历史会话记录显示原账号已创建并验证，Vibekits 应用 ID 为 `1000852511`，已上传安装包、图标和 3 张截图，历史界面曾显示“待修订”。已从原钥匙串记录找回独立网站凭据；当前浏览器操作超时，实时审核状态仍待复核。KEMI Send 也必须同时核查，不能将历史记录或登录尝试当作当前发布成功证据。凭据不得写入文档。
- 本机现有 Apple 身份只有 `Developer ID Application: zhen ji (26T5WV4GLP)`，足够完成站外公证分发，但没有 Mac App Store 所需的商店分发/安装证书，没有 provisioning profile，也未发现 App Store Connect API `.p8` 密钥。Apple 商店上传尚未开始；需要在有效 Apple Developer/App Store Connect 团队中创建对应 App ID/记录并取得商店分发资产后，才能生成 Mac App Store 沙盒构建并提交审核。
