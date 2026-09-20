# VibeKits dev.224 Windows 商场发布结果

发布时间：2026-09-20（北京时间）。

## 发布结果

- KEMI 商场现有 Windows 应用 `app_id=54` 已免审直接更新。
- 包名：`com.caucy.vibekits`；版本：`1.9.0-dev.224`；VersionCode：`2224`。
- 保持分类“工作”、商城展示开启、可取消更新。
- 正式安装器：`Vibekits-1.9.0-dev.224+2224-windows-x64-setup.exe`。
- 大小：`262801768` bytes。
- SHA-256：`1eda47a2a76b232a675c0851825da63108125687f0264563669feb167c3765df`。
- CDN：`https://cdn.newlink-sz.com/kemiAppStore/winpkg/2026/09/1789904776936_639918c9_Vibekits-dev224-setup.exe`。

## 本次修复

- Windows OpenSSH capability 改为通配查询并使用系统返回的完整 capability 名称，避免版本名写死引发 `0x80070490`。
- 为当前 Windows 用户写入独立 `AuthorizedKeysFile` 规则，避免管理员账户落到 `administrators_authorized_keys` 后公钥认证失败。
- 全新安装 OpenSSH 且 `%ProgramData%\ssh\sshd_config` 尚不存在时，从系统默认配置生成后再写入规则。
- 启用操作在 sshd 已监听时仍执行幂等修复，兼容已安装但配置不完整的机器。

## 验证

- Windows 目标测试通过；Windows Release 增量构建通过。
- 安装器 Authenticode 状态 `Valid`，签名证书指纹 `B82824C01226426C2D2BD423F883DCBC999C7E82`，DigiCert 时间戳存在，SignTool 验证退出码为 `0`。
- 商场公开详情返回 dev.224 / 2224、精确大小与 SHA-256。
- 旧版 2223 查询返回 `has_update=true`，目标为 2224；当前版 2224 返回 `has_update=false`。
- CDN 完整回下载为 `262801768` bytes，SHA-256 与 58 号签名机、本机正式包及商场记录完全一致。

结论：dev.224 Windows 修复版已发布，商场用户可直接更新。
