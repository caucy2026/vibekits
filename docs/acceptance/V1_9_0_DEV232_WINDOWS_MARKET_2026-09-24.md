# VibeKits Windows dev232 KEMI 商城发布记录（2026-09-24）

- 源码基线：`8a0f4de671fa5a40745a8be4e8a92c3fcb617e9b`；仅发布 Windows，未重建后续 Mac/Pad 改动。
- 安装包：`Vibekits-1.9.0-dev.232+2232-windows-x64-setup.exe`，283237776 字节，SHA-256 `f293ab263f044a0ca4ae006304c89d7a1b76ed9e57bc97411bb7f5eaf920240c`。
- 58 硬件令牌签名：439/439 个 PE 内签有效，安装包外签有效；签名主体指纹 `B82824C01226426C2D2BD423F883DCBC999C7E82`，时间戳及独立 SignTool 验证通过。报告在 `D:\KEMI-Test\results\signing\Vibekits232-inner-20260924-01\summary.json` 和 `D:\KEMI-Test\results\signing\Vibekits232-outer-20260924-01\summary.json`。
- 安装启动验收：58 与 619 均使用此精确安装包隔离安装，安装退出码 0，主程序、`app.so`、Harness 中继的哈希相同；两台均观察到 Windows Session 1 主窗口和同路径中继，远程仿真在候选程序运行时连接成功。58 截图显示 Harness 界面，同时出现新测试路径的 Windows Defender 防火墙提示；未修改防火墙规则。
- KEMI 商城：`app_id=54`，`com.caucy.vibekits`，`windows`，`1.9.0-dev.232+2232`，VersionCode 2232，已上架且免审。CDN：<https://cdn.newlink-sz.com/kemiAppStore/winpkg/2026/09/1790219589391_06184a1d_1790216344590-Vibekits-1_9_0-dev_232_223.exe>。
- 发布后核验：公开详情与默认 Windows 列表均为 dev232；旧版 2227 检查更新返回 `has_update=true`，2232 返回 `false`；CDN HEAD 为 HTTP 200、283237776 字节；完整下载复算 SHA-256 与本地及服务器相同。
- 恢复现场：619 已恢复原 dev227 注册信息、快捷方式和进程，移除一次性任务。58 的验收任务已结束且退出码为 0，一次性任务已移除；用户随后打开已安装的 dev232，远程仿真重新连接，主程序及同目录 Harness 中继均运行。58 当前安装注册版本为 `1.9.0-dev.232+2232`。
- 58 构建目录映射：通过现有 VibeKits 仿真 SSH 隧道、rclone SFTP 和本机只读 WebDAV，将 `D:\KEMI-Test\source\vibekits-9a6ed30-dev228-win-20260923\build` 挂载到 `/Users/newlink/VibeKits-4567540178-build`。本机挂载文件与远端 `vibekits.exe` SHA-256 均为 `81fffb911abc3432f69aa6e2c9d9dbf8d1ce8f6847209667a7f822992962a8cf`。此挂载依赖当前仿真连接与本机服务，未设置开机自动恢复。
