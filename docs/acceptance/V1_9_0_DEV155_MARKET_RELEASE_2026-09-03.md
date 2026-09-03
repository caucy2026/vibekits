# VibeKits dev.155 Windows/macOS 正式市场发布验收

## 发布结论

VibeKits `1.9.0-dev.155+2155` 已完成 Windows Release 编译、macOS Universal Release 编译与 Apple 正式认证，并更新 KEMI 应用市场原有 Windows/macOS 记录。没有创建重复应用，两个平台均保持上架、非强制更新。

## 源码与版本一致性

- 发布提交：`457793ec358a0fba71f59037ddb9dfe3cbb0165b`。
- `pubspec.yaml`：`1.9.0-dev.155+2155`。
- UI 语义版本：`1.9.0-dev.155`，build `2155`。
- LMCP 公告版本：`1.9.0-dev.155`。
- LMCP `catalogRevision`：`2155`。
- 本轮发布前发现 dev.154 的 LMCP 公告仍硬编码为 dev.152，因此停止使用旧候选，修复并升版后重新执行全部门禁。

## 自动测试

- `flutter analyze --no-pub`：0 issue。
- 商城、自更新与 LAN MCP 定向测试：7/7 通过。
- 全量 `flutter test --no-pub`：667 项通过，16 项真实设备、真实网络或显式 Release 环境门禁按设计跳过，0 失败。

## Windows Release

- GitHub Actions：Windows Compatibility run `33748949677`，结论 `success`。
- CI 已通过固定 Harness、Git、ADB、7-Zip、Mihomo、QEMU 运行时准备与验证。
- Harness UI、Agent 集成、本地工具桥、LAN MCP、自更新、共享 Widget 测试全部成功。
- Windows Release 编译、EXE 与内置 payload 验证、打包和 artifact 上传全部成功。
- Artifact ID：`9891140281`。
- Artifact 名称：`Vibekits-1.9.0-dev.155-2155-windows-x64`。
- 外层 artifact：275,081,017 bytes，SHA-256 `e0a9b6e04b741ca440dea4445aa496918830e43a7c254e94607615c37789e717`。
- 正式内层 ZIP：`bin/release/Vibekits-1.9.0-dev.155+2155-windows-x64.zip`。
- 正式内层 ZIP：283,303,960 bytes。
- 正式内层 SHA-256：`ec9a9e6f5757f1883d03c883e053539a10551125d2f001f089783dedd85eeb86`。
- 外层和内层 ZIP 完整性检查均无错误；内层再次确认包含 Vibekits EXE、Harness Node、Git、ADB、7-Zip、Mihomo 和 QEMU。

## macOS Release 与 Apple 认证

- GitHub Actions：macOS Release run `33748949670`，结论 `success`。
- CI 的 Harness、7-Zip、Git、Analyze、测试、Release 编译、Intel/Apple Silicon/macOS 12+ 兼容和打包步骤全部成功。
- 本机从同一提交重新构建正式候选：`build/macos/Build/Products/Release/Vibekits.app`。
- 主可执行文件架构：`x86_64 arm64`。
- Developer ID：`Developer ID Application: zhen ji (26T5WV4GLP)`。
- 34 个 Mach-O 逐项签名，Hardened Runtime、Harness Node JIT、DSH 和深度严格验签通过。
- 签名后从精确候选路径真实启动 APP，本机 Harness 工具桥验证成功；没有启用外部模型数据传输冒烟。
- Apple Notary Submission ID：`e9bc35ed-868b-4cf1-9160-be79de5265a9`。
- 公证结果：`Accepted`。
- `stapler staple`、`stapler validate`：通过。
- Gatekeeper：`accepted`，`source=Notarized Developer ID`。
- 最终 ZIP：`bin/release/Vibekits-1.9.0-dev.155+2155-macos-universal-notarized.zip`。
- 最终 ZIP：263,121,804 bytes。
- 最终 SHA-256：`9928a81e4d5d7edf49d02682978afecb4078a91118b4a18a637af2954e9cfb91`。

## KEMI 应用市场更新

生产写操作严格按 `(package_name, os_type)` 查重，两个平台各有且仅有一条记录。先完成两端上传和服务端大小/SHA 校验，再更新市场记录。

### Windows

- `app_id=54`，`package_name=com.caucy.vibekits`。
- 线上版本：`1.9.0-dev.155` / `2155`。
- 平台：`windows`。
- CDN：`https://cdn.newlink-sz.com/kemiAppStore/winpkg/2026/09/1788437755354_d367d0f0_Vibekits-1_9_0-dev_155_2155-windows-x64.zip`。
- 公开大小：283,303,960 bytes，与本地一致。
- 公开 SHA-256：`ec9a9e6f5757f1883d03c883e053539a10551125d2f001f089783dedd85eeb86`，与本地一致。
- CDN HEAD：HTTP 200，`application/zip`，Content-Length 283,303,960。

### macOS

- `app_id=53`，`package_name=com.caucy.vibekits`。
- 线上版本：`1.9.0-dev.155` / `2155`。
- 平台：`macos`。
- CDN：`https://cdn.newlink-sz.com/kemiAppStore/macpkg/2026/09/1788437877020_47698466_Vibekits-1_9_0-dev_155_2155-macos-univer.zip`。
- 公开大小：263,121,804 bytes，与本地一致。
- 公开 SHA-256：`9928a81e4d5d7edf49d02682978afecb4078a91118b4a18a637af2954e9cfb91`，与本地一致。
- CDN HEAD：HTTP 200，`application/zip`，Content-Length 263,121,804。

## 自更新正反向验收

公开 `api/store/update/check` 真实结果：

- Windows `version_code=2153`：`has_update=true`，返回 dev.155 Windows URL、大小和 SHA。
- Windows `version_code=2155`：`has_update=false`。
- macOS `version_code=2153`：`has_update=true`，返回 dev.155 macOS URL、大小和 SHA。
- macOS `version_code=2155`：`has_update=false`。
- Windows/macOS 列表均只返回对应平台条目，`list_in_store=true`、`force_update=false`。

## 边界说明

- Windows 本轮证据是 GitHub Windows 真正编译、自动测试、自包含 bundle 验证和产物解包复核；没有在本轮额外取得用户 Windows 桌面上的人工点击截图。
- macOS 已完成正式 Developer ID、公证、票据和本机签名后启动验证。
- 发布登录和上传临时文件由隔离临时目录保存，并在流程退出时清理；源码、报告和客户端不包含账号、密码、Bearer token 或上传 token。
