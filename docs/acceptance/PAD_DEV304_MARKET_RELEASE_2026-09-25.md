# VibeKits Android PAD dev.304 商城发布验收

日期：2026-09-25。用户明确要求将 PAD 版正式签名后发布到 KEMI 商城，以便全新 Mac/PAD 安装文档使用同一已上架版本。

## 冻结产物

- 现有 Android 商城记录：`app_id=71`，包名 `com.vibekits.vibekits`，`os=android`，平台 `pad2`，分类“探索”，在商城展示、非强制更新。沿用同一条目从 `1.9.0-dev.170 / 2170` 更新，不创建重复应用。
- 签名 APK：`bin/candidates/VibeKits-1.9.0-dev.304+2304-android-pad-arm64.apk`，`85,648,552` 字节，SHA-256 `98dadcab19cabf67fbda14424d718ad1d48bc0e51e018220fd0b75c616c12131`。`aapt` 为 `1.9.0-dev.304 / 2304`、arm64；`apksigner verify` 通过 APK v2 验签，证书 SHA-256 `c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8`。
- 包内 `assets/vibekits-adb-helper.apk` 的包名 `com.vibekits.vibekits.component.adb`、版本码 5，APK 验签证书与宿主一致。PAD63 候选包的真机安装、版本、应用中心功能此前见 `PAD63_DEV304_MARKET_SIZE_ICON_2026-09-25.md`。

## 商城与 CDN 结果

- 使用已登录 Chrome 的现有 `app_id=71` 更新表单上传签名 APK；服务端解析回报 SHA-256 与本地一致。界面自动填的 `81.7MB` 被改为精确十进制 `85648552` 后保存并发布；商城确认“已直接更新线上版本（免审）”。
- 公开 `GET /kd-api/api/store/apps/71?os=android` 返回 `version_name=1.9.0-dev.304`、`version_code=2304`、`file_size="85648552"`、同 SHA-256 与 HTTPS 下载地址。无分类 Android 列表仅命中一个相同包名条目，平台仍为 `pad2`。
- 更新检查以旧版 `2170` 查询返回 `has_update=true`、目标 `2304`、大小 `85648552`、同哈希和 URL；以新版 `2304` 查询返回 `has_update=false`。更新检查中的 `file_size_bytes` 为 `85648552`。公开详情未返回独立 `file_size_bytes` 字段，但其 `file_size` 是精确十进制字节，按该接口实际返回记录。
- CDN `HEAD` 返回 HTTP 200、`Content-Length=85648552`、APK 内容类型。完整回下载为 `85,648,552` 字节、同 SHA-256，`cmp` 证明与冻结候选逐字节相同；对回下载文件重做 APK 签名与包名/版本检查通过。

## 已安装设备复验与边界

- PAD63 通过设备 ID `6795854383` 建立 `p2p_or_relay` 仿真，返回 `connected=true`、`mcpReady=true`、`adbReady=true`、动态本机串口。Mac 的隔离 ADB server 连接后 `get-state=device`，设备型号 `KEMI Vibe Pads S1`，PackageManager 为 `1.9.0-dev.304 / 2304`。设备内已安装 `base.apk` 的 SHA-256 与商城完整回下载包相同。测试后仅断开本次 ADB 串口和仿真连接。
- 该实测证明已装同字节包的 PAD63 可继续远程 ADB；没有把 PAD63 清空重做首装，也没有测试另一台**全新 PAD** 在原生 ADB 关闭、辅助组件尚未安装时第一次开启仿真的闭环。该场景仍须用现场恢复手段按技能 `vibekits-remote-simulator/references/new-mac-pad-first-run.md` 第 4 节验收，不能把本次发布误报为任意 PAD 无条件远程 ADB 成功。
