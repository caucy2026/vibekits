# VibeKits 1.9.0-dev.157 秒表与双平台商场发布验收

## 1. 发布结论

VibeKits `1.9.0-dev.157+2157` 已完成 macOS Universal 与 Windows x64 Release 构建、平台门禁、商场上传、公开目录反查、更新检查和 CDN 全量文件校验。macOS 包已完成 Developer ID 签名和 Apple 公证；Windows 包已在 Windows 10 真机运行验证，但 Authenticode 状态为 `NotSigned`，本次按负责人明确接受未签名 Windows 测试包的范围发布，不能表述为已签名 Windows 正式包。

生产记录：

- macOS：KEMI 商场 `app_id=53`
- Windows：KEMI 商场 `app_id=54`
- 包名：`com.caucy.vibekits`
- 版本：`1.9.0-dev.157`，`version_code=2157`
- 源码提交：`a5b47ec911f6438d214df1d1dce2702e9f090639`

## 2. 功能改动与缺陷修复

- 开发工具新增秒表：数字读数与表盘同步，1 秒按 100 份显示，可开始、暂停、继续和复位。
- 秒表进入统一工具注册表、Harness Schema、工具用途合同和工具执行路径，Windows 与 macOS 共用同一套 Dart 业务逻辑和界面。
- 正式 Harness smoke 发现并修复 `capability_check` 空值崩溃：新增工具若缺少 `ToolUsageContract`，不再等到 Release 才暴露；回归测试强制每个独立开发工具都有用途合同。
- `vibekits.stopwatch` 增加可执行 Harness 回调和稳定格式化结果，避免只可发现、不可调用。

## 3. macOS 构建、签名与公证

- 包：`bin/release/Vibekits-1.9.0-dev.157+2157-macos-universal-notarized.zip`
- 大小：263,127,341 bytes
- SHA-256：`261c3c942aa25ecd20c8291e0269501ff1cf6fd16dfe5bc872bccbfa02d291d4`
- 主程序架构：`x86_64 arm64`
- 最低系统：`LSMinimumSystemVersion=12.0`
- 签名：`Developer ID Application: zhen ji (26T5WV4GLP)`
- Apple 公证：Accepted，Submission ID `639c1978-0490-43b1-b313-829913c07786`
- staple/validate：通过
- Gatekeeper：accepted，`source=Notarized Developer ID`
- Release 兼容门禁：Harness、ADB、7-Zip、Git 与 34 个 Mach-O 校验通过。

## 4. Windows 真机门禁

- 构建节点：`192.168.3.58`，Windows 10 Home China，build 19045。
- 精确源码目录：`D:\KEMI-Test\source\vibekits-a5b47ec-export`
- 隔离安装目录：`D:\KEMI-Test\app\Vibekits-dev157-isolated`
- 包：`bin/release/Vibekits-1.9.0-dev.157+2157-windows-x64.zip`
- 大小：267,363,553 bytes
- SHA-256：`aa540478629b9c686d66aa87aef6711ca8b5aae42d7ff3d816b696cb614f58de`
- 完整运行时校验：31 项通过，包括 Harness、ADB、Git、7-Zip、Mihomo 与 QEMU。
- 三次隔离冷启动均在 5 秒检查点存活，工作集分别约 81.2 MB、89.1 MB、91.9 MB，随后均正常停止。
- Authenticode：`NotSigned`。这是本次已接受的测试包限制，不得在后续文档或 UI 中标记为签名通过。
- 当前节点没有可用的交互桌面代理，Windows 可见 UI 点击验收标记为 `interactive_required`；自动化、打包完整性和进程级运行门禁已通过。

## 5. 自动化与 Harness 验证

- `flutter analyze --no-pub`：通过，0 issue。
- Windows 关键回归：51/51 通过。
- macOS Harness 与秒表定向测试：40 通过，1 项按环境跳过，0 失败。
- 正式 macOS App 的本地 Harness bridge smoke：通过，输出 `Verified local Harness tool bridge`。
- 回归覆盖新增工具合同完整性，防止以后增加工具时再次破坏 `capability_check`。

## 6. KEMI 商场反向验收

公开详情与平台目录均显示 dev.157：

- Windows `app_id=54`，版本 `1.9.0-dev.157 / 2157`。
- macOS `app_id=53`，版本 `1.9.0-dev.157 / 2157`。
- 以旧版本码 `2156` 请求更新检查：Windows 与 macOS 都返回 `has_update=true`、目标版本码 `2157` 和对应 CDN 地址。
- 以当前版本码 `2157` 请求更新检查：Windows 与 macOS 都不返回更新下载地址，未重复提示当前版本更新。
- 先前服务端 `Unknown column 'a.names'` 故障已不再复现，生产更新检查链路本次真实返回成功。

CDN 全量下载校验：

- Windows：267,363,553 bytes，SHA-256 `aa540478629b9c686d66aa87aef6711ca8b5aae42d7ff3d816b696cb614f58de`，与本地真机测试包完全一致。
- macOS：263,127,341 bytes，SHA-256 `261c3c942aa25ecd20c8291e0269501ff1cf6fd16dfe5bc872bccbfa02d291d4`，与本地已签名、公证包完全一致。

## 7. 已知边界

- Windows 包尚无 Authenticode 签名，只满足负责人本次明确接受的“能运行测试包”发布范围；获得 Windows 代码签名证书后仍应补发签名版本。
- Windows 真机的可见 UI 点击验收需要交互桌面代理恢复后补做；本次没有伪报为通过。
- 截图中约 400% CPU 的进程属于 KEMI 传书后台服务 `KEMI-Send-Remote-Service`，并非 VibeKits。清理了 VibeKits 遗留的三个 Harness Node 测试进程，但未越权终止 KEMI 传书进程。
