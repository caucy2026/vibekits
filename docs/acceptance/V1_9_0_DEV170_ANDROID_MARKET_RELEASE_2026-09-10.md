# VibeKits 1.9.0-dev.170 Android 应用中心与 KEMI 商城发布验收

日期：2026-09-10
商城记录：`app_id=71`
包名：`com.vibekits.vibekits`
版本：`1.9.0-dev.170 (2170)`

## 1. 修复范围

- 接受 KEMI Android 目录实际使用的 `platforms=android|pad2|all`，不再把服务端返回的 Android/PAD 商品全部过滤为空。
- macOS 与 Windows 仍只接受各自平台或 `all`，保持跨平台隔离。
- 恢复“探索”分类筛选入口。
- Android 用真实 applicationId 识别当前 VibeKits；市场版本不高于本机时显示“当前已是最新版本”并禁用下载。

## 2. 自动检查

- `flutter test test/app_center_test.dart test/harness_remote_read_only_panel_test.dart test/harness_remote_share_dialog_test.dart`：22/22 通过。
- `flutter analyze --no-pub`：零问题。
- 完整 `flutter test --no-pub`：789 通过、18 个需显式真实环境的用例跳过；2 个既有 macOS Keychain 用例在固定 10 秒超时，单独重跑仍超时。本轮涉及的应用中心与远程协助测试均通过。

## 3. 候选包与签名

- 文件：`build/app/outputs/flutter-apk/Vibekits-1.9.0-dev.170+2170-android-pad75.apk`
- 大小：`148111921` 字节。
- SHA-256：`fed50f8725a7a88f6f586474ff90612b47b26db232226781f311c8084321345f`。
- Android：minSdk 24、targetSdk 36、ARM64。
- APK 签名：v2=true、v3=true。
- 证书 SHA-256：`c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8`。

## 4. PAD75 真机

- 设备：`192.168.3.75:5555`。
- 标准流式覆盖安装成功，冷启动 Activity 为 `SingleScreenActivity`，实际 PackageManager 版本为 2170。
- 应用中心成功加载 Android 商品网格和“探索”分类。
- 搜索 `VibeKits` 返回 app_id 71；发布 dev.170 前，已安装 2170 对商场 dev.169 正确显示“当前已是最新版本，无需重复下载”，按钮“已是最新版”为禁用状态。
- 证据截图：`/private/tmp/vibekits-dev170-market-loaded.png`、`/private/tmp/vibekits-dev170-search.png`、`/private/tmp/vibekits-dev170-current-gate.png`。

## 5. KEMI 商城与 CDN 反向验收

- 更新接口返回：`已直接更新线上版本（免审）`，线上记录为 dev.170/2170、`list_in_store=true`、`force_update=false`。
- 公共 Android 列表按 `VibeKits` 查询唯一命中 app_id 71。
- 版本 2169 检查：`has_update=true`，返回 dev.170 URL、大小、SHA-256 和 deeplink。
- 版本 2170 检查：`has_update=false`，下载 URL 为空，不反复提示。
- CDN：HTTP 200，Content-Type 为 Android APK，Content-Length `148111921`。
- CDN 回下载 SHA-256、v2/v3 签名、证书、包名和版本与本地候选完全一致。
- CDN 原包已再次覆盖安装到 PAD75 并冷启动成功。

## 6. 结论

dev.170 已正式覆盖 KEMI 商城 Android 记录。应用中心可见、当前版本下载禁用、旧/新版本更新判断、CDN 完整性、签名和真机安装启动均完成闭环。
