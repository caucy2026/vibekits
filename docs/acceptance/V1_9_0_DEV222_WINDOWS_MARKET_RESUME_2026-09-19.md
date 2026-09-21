# VibeKits dev.222 Windows 商城发布结果

发布时间：2026-09-19 17:39:30（北京时间）。

用户最新范围：把今天已签名的 Windows 安装器上传商城，确认签名包身份；不继续远程仿真恢复或重做安装验收。

## 发布结果

- 从本机已登录 Chrome 正式更新表单更新现有 `app_id=54`，未新建应用、未改其它平台。
- 服务端明确返回“已直接更新线上版本（免审）”。
- 包名：`com.caucy.vibekits`；平台：Windows x64；版本：`1.9.0-dev.222`；VersionCode：`2222`。
- 本地安装器：`/Volumes/ORICO/kemi-build-cache/app-release-gate/vibekits/windows/dev222-market/Vibekits-1.9.0-dev.222+2222-windows-x64-setup.exe`，本机保存时间为当天 16:17。
- 精确大小：`263309416` bytes。
- SHA-256：`2a475c22485b39b105476ebdef74dffabd5595a72939883dde1277d8c4e982a6`。
- CDN：`https://cdn.newlink-sz.com/kemiAppStore/winpkg/2026/09/1789810602368_5bcf2440_Vibekits-1_9_0-dev_222_2222-windows-x64-.exe`。
- 固定记录：`https://kemi.newlinksz.com/kd/console/apps/54`。
- 公开详情：`https://kemi.newlinksz.com/kd-api/api/store/apps/54?os=windows`。

## 本轮验证

- 本地完整 SHA-256 与今天仿真机签名并验签后的交接安装器身份完全一致；没有重新构建、打包或签名。
- 从本地 EXE 的 PE Security Directory 读取嵌入签名证书，证书指纹确认为 `B82824C01226426C2D2BD423F883DCBC999C7E82`（深圳新智联软件有限公司）。此检查是嵌入证书身份核对，不冒充重新执行 Windows 信任链验证。
- 上传完成后页面计算的 SHA-256 与本地一致；上传自动生成展示大小后，提交前改回精确字节数字符串。
- 后台详情显示 Windows dev.222 / 2222 已上架；公开详情及无 category 过滤的 Windows 默认列表均返回相同版本、下载 URL、字节数与摘要。
- 旧版 2221 返回 `has_update=true`，目标 2222，两个大小字段均为 `263309416`；当前版 2222 返回 `has_update=false`，`pending_review=false`。
- CDN 完整下载流式计算：`263309416` bytes，SHA-256 与本地完全相同，`match=true`。用户实际下载的是同一份已签名安装器。
- 分类“工作”、商城展示开启、非强制更新均保持不变。

## 范围与记录

- GitHub main、本地 HEAD 和 origin/main 本轮只读复核均为 `e117670c219b37529b1e58ae2d88a045a1869250`，包含 Windows Relay 修复 `23ac666`；保留工作区其它未提交开发内容。
- 原交接称线上 dev.217；实际发布前为 dev.221 / 2221。本轮更新至 dev.222 / 2222。
- 本轮未重新运行 Windows SignTool、真实安装/启动或开发测试，按用户收敛后的上传范围复用同一不可变安装器的既有签名证据。
- 曾尝试恢复过期本机仿真桥配置；进程令牌恢复操作被自动审批拒绝，命令未执行。用户随后明确收敛为上传现有签名包，已停止该旁支，未读取或生成相关凭据。

结论：今天已签名的 Windows dev.222 安装器已在现有商城应用 54 生效，公网完整下载身份校验通过。
