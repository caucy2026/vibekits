# VibeKits dev.222 Harness 会话快捷键与 KEMI 商场发布验收

日期：2026-09-19  
版本：`1.9.0-dev.222+2222`  
源码提交：`f86862bb753d04ae17e36da31807db7b513d59b4`

## 功能与本机门禁

- F1–F12 切换当前可见 Harness 会话并聚焦输入框；macOS 原生窗口与 WebView 焦点路径均接入快捷键路由。
- 加入会话续接关系存储和官方空白会话 API 适配基础；本版未把完整“整理上下文后继续开发”界面描述为已完成。
- Harness、应用中心与更新专项 45 项通过，静态分析 0 issue；正式候选真实启动并通过本地 Harness 工具桥。

## macOS 正式认证

- Developer ID：`Developer ID Application: zhen ji (26T5WV4GLP)`。
- Apple 公证：`Accepted`，Submission ID `af99f4f1-4e60-4eff-9c02-8fc5e7326225`。
- staple、深度签名、Gatekeeper、macOS 12+、Universal `x86_64 + arm64` 与内置 Harness 运行时均通过。
- 正式 ZIP：`/Volumes/ORICO/kemi-build-cache/app-release-gate/vibekits/macos/dev222-market/delivery/Vibekits-1.9.0-dev.222+2222-macos-universal-notarized.zip`。
- 字节数：`402628251`。
- SHA-256：`244ade21d5128edce3fcb566853763515feaa692fef9530570158b2c8eaf26a9`。

## KEMI 商场闭环

- 更新现有 macOS 记录 `app_id=53`，包名 `com.caucy.vibekits`；未创建重复记录。
- 线上版本为 `1.9.0-dev.222`，VersionCode `2222`，分类“工作”，保持商城展示且非强制更新。
- CDN：`https://cdn.newlink-sz.com/kemiAppStore/macpkg/2026/09/1789784008486_6cb23f7e_Vibekits-1_9_0-dev_222_2222-macos-univer.zip`。
- 公开详情与默认 macOS 列表均返回 app_id 53、版本 2222、精确大小和 SHA-256。
- 旧版 2221 返回 `has_update=true` 并指向 dev.222；当前版 2222 返回 `has_update=false` 且下载 URL 为空。
- CDN `Content-Length=402628251`；全量回下载 SHA-256 与本地正式包一致。
- CDN 回下载包再次通过单一顶层 App、Developer ID、公证票据、Gatekeeper、双架构、版本 2222、完整运行时和真实 Harness 工具桥启动验证。

## 结论

macOS dev.222 已完成本机测试、正式签名、公证、KEMI 商场更新和公网回下载验收，可以交付。
