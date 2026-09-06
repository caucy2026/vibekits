# VibeKits 1.9.0-dev.158 双平台商城发布验收

## 发布结论

VibeKits `1.9.0-dev.158+2158` 已更新到 KEMI 应用商场既有的 macOS 与 Windows 记录，没有创建重复应用。macOS 为 Developer ID 签名、Apple 公证并装订票据的正式 Universal 包；Windows 为 CI Release 与 Windows 10 真机验证通过、但未做 Authenticode 签名的测试包。Windows 的签名边界按负责人此前明确接受的范围保留，不能描述为已签名正式包。

- 包名：`com.caucy.vibekits`
- macOS：`app_id=53`
- Windows：`app_id=54`
- 版本：`1.9.0-dev.158`，`version_code=2158`
- 产品构建源码提交：`370bb5ed23affc0c6c52e7c403030b7e8a0fc961`
- 发布时仓库主线：`1ed16febec74d095f67c6b312a59a6c2c5570171`
- 商城状态：两端均上架，非强制更新

## GitHub 构建来源

- macOS run `34028402765` 成功；artifact `9987938014`，265,954,640 bytes，SHA-256 `2a3cf6630f613df423ab26e010b2d4c62224089806e66574c6ae1f08492c9861`。
- Windows run `34028402857` 成功；artifact `9987941419`，292,107,517 bytes，SHA-256 `d9f683ce2f2db1e07ef15b5b9bf79704de755d0e11d4a765f7e0225b2a45365e`。
- 下载后的两个外层 artifact 摘要均与 GitHub Actions 记录一致；内层 ZIP 完整性和工作流生成的摘要再次通过。

## macOS 正式认证

- 最终包：`bin/release/Vibekits-1.9.0-dev.158+2158-macos-universal-notarized.zip`
- 大小：289,335,310 bytes
- SHA-256：`39a57c120ad1a5a6026a0dfe4e3037f5c69d4091d8fcc6f1d90c485891e37e09`
- 架构：`x86_64 arm64`
- 最低系统：macOS 12.0
- 签名：`Developer ID Application: zhen ji (26T5WV4GLP)`
- Apple 公证：`Accepted`
- Submission ID：`75b32bad-5ab5-4781-9402-95a51f3c2291`
- `stapler staple`、`stapler validate`、深度严格验签和 Gatekeeper 均通过；Gatekeeper 来源为 `Notarized Developer ID`。
- 签名候选和商城 CDN 回下载包均真实启动，并成功发布、验证本地 Harness 工具桥后正常退出。未启用外部模型 smoke，未向外部模型发送 LAN MCP 元数据。

## Windows 真机验收

- 最终包：`bin/release/Vibekits-1.9.0-dev.158+2158-windows-x64.zip`
- 大小：299,209,367 bytes
- SHA-256：`a3600a4329072b6cdc2623257aec92c83bd3ef21b5208b2a21e68410387b06dc`
- 真机：`192.168.3.58`，固定 ED25519 指纹 `SHA256:ikZ6NXAH3VFBGooSCeKW0JY9+h0cIcQOzib4fxmvz6M` 与项目可信文档一致。
- 传输、缓存、解包和隔离运行均位于 `D:\KEMI-Test`；真机复算大小与 SHA-256 和 Mac 完全一致。
- 项目 `verify_windows_bundle.ps1` 通过 33 项必需运行时检查，版本为 `1.9.0-dev.158+2158`，内置 Git 为 `2.55.0.windows.3`，GitHub CLI 为 `2.100.0`。
- 三次隔离启动均在 5 秒检查点存活，工作集约 90.2 MB、82.9 MB、100.8 MB；每次仅停止精确测试 PID。
- SSH 会话属于 Session 0，因此本轮不把可见 UI 点击伪报为通过。
- Authenticode 为 `NotSigned`；本包只满足负责人已接受的未签名 Windows 测试包发布范围。

## KEMI 商场闭环

### macOS

- CDN：`https://cdn.newlink-sz.com/kemiAppStore/macpkg/2026/09/1788698841166_32cb452c_Vibekits-1_9_0-dev_158_2158-macos-univer.zip`
- 管理员记录、公开平台列表和更新接口均返回 dev.158/2158、289,335,310 bytes 和上述 SHA-256。
- CDN 全量回下载后大小、SHA-256、Developer ID、票据、Gatekeeper、双架构和真实启动全部通过。

### Windows

- CDN：`https://cdn.newlink-sz.com/kemiAppStore/winpkg/2026/09/1788698842306_e9a26404_Vibekits-1_9_0-dev_158_2158-windows-x64.zip`
- 管理员记录、公开平台列表和更新接口均返回 dev.158/2158、299,209,367 bytes 和上述 SHA-256。
- CDN 全量回下载后大小、SHA-256 和 ZIP 完整性通过；其字节与已在 Windows 真机运行的包完全一致。

## 更新检查与平台隔离

- macOS 与 Windows 使用旧版本码 `2157` 查询均返回 `has_update=true`，目标为各自平台的 dev.158 CDN 地址。
- 两端使用当前版本码 `2158` 查询均返回 `has_update=false`，没有重复更新循环。
- 两个平台的管理员查重均为 1 条，公开列表分别只返回对应平台条目。

## 本版用户可见变化

- 新增专业网络测速，展示延迟、抖动、上行/下行带宽、实时阶段和进度，并支持随时停止。
- “关于我们”由真实格式注册表和开发工具注册表生成完整能力清单。
- 内置 GitHub CLI 2.100.0，并补齐 GitHub 与统一智能体 CLI 的 Harness/MCP 工程调用能力。

