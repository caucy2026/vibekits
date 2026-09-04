# VibeKits dev.153 KEMI 市场与自升级验收

版本：`1.9.0-dev.153+2153`

## 发布合同

- 逻辑包名固定为 `com.caucy.vibekits`。
- 更新检查使用 `https://kemi.newlinksz.com/kd-api/api/store/update/check`。
- Windows 请求必须带 `os=windows`，macOS 请求必须带 `os=macos`；版本只比较整数 `version_code=2153`。
- 只有 `status=200`、`has_update=true` 且远端整数版本更高时才显示更新。
- 下载地址必须是 HTTPS；Windows 只接受 `.exe/.msi/.zip`，macOS 只接受 `.dmg/.pkg/.zip`。
- 下载后必须同时核对服务端声明的精确字节数与 64 位 SHA-256；任一缺失或不一致即删除临时文件，禁止安装。
- macOS 由系统打开已校验的安装包；Windows 的 MSI 交给 `msiexec`、EXE 直接启动、ZIP 交给资源管理器。客户端不使用商城 DeepLink。
- 历史实现曾在“关于我们”放置状态、手动检查及下载入口；该界面合同已由 dev.156 纠正，不能再作为新 APP 的参考。现行规则是“关于我们”和“应用中心”均不放本 APP 更新卡片，后台失败静默，只有确认存在更高版本时才弹出独立全局提示。

## 已执行自动门禁

- `flutter analyze --no-pub`：0 问题。
- `flutter test --no-pub test/app_update_service_test.dart test/widget_test.dart`：23/23。
- 协议测试确认 `package_name/version_code/os` 完整并拒绝 HTTP 安装包。
- macOS Release 构建：通过，App 669.9 MB。
- `verify_macos_release_compat.sh`：App、Harness、ADB、7-Zip、Git 均满足 Universal 与 macOS 12+ 门禁。
- Developer ID：34 个 Mach-O 完成时间戳签名和严格验证；内置 Node 的 JIT entitlement 保持有效。
- Apple 公证：`Accepted`，Submission ID `4e9ef05e-5817-402c-b0a0-0c12e016141a`；staple/validate 与 Gatekeeper `Notarized Developer ID` 通过。
- 最终 macOS ZIP：263,093,194 bytes；SHA-256 `f50fdaecb3f70a316681eff5f61692668781a5a648ec6fefd9845c41d716606c`。

## Windows 假成功复盘与修复

首轮 CI `33719086936` 虽然为绿色，但其 ZIP 只验证了 EXE 和 Harness 两个文件，解包审计发现缺少内置 Git；该包已明确作废，禁止上架。根因是 Visual Studio 多配置生成器下 `CMAKE_BUILD_TYPE` 为空，使 CMake 中按该变量判断的 Release 缺件分支没有触发，同时工作流没有调用仓库已有的完整 `verify_windows_bundle.ps1`。

提交 `a5ccea83cf10c22aa3642e8095ecf7d60a067cc0` 修复发布门禁：构建前准备固定 Harness、MinGit、Mihomo 和 QEMU；增加自更新测试；构建后调用完整验证脚本检查 30 项必需文件、版本、Git HTTPS helpers 和 Harness JS 语法。只有新工作流全部通过并重新取得产物哈希后，Windows 包才可上架。

该提交触发的 CI `33725694793` 又正确暴露了第二个环境耦合：`prepare_mihomo_runtime.ps1` 默认从 runner 并不存在的 `C:\Program Files\Clash Verge\verge-mihomo.exe` 复制内核。现已改为下载 Mihomo 官方 `v1.19.29` Windows amd64 Release ZIP，并在解压前核对固定 SHA-256；三个 GeoData 文件也逐一执行固定 SHA-256 校验。外部已安装 Clash Verge 仍可作为显式参数输入，但不再是 CI 或正式构建的隐含依赖。

## Windows 最终门禁

- 修复提交 `cb162e032dacaf5e019d00c99eb0c064c544c5f0` 触发 GitHub Actions run `33726440489`，完整成功。
- CI 已依次通过 Harness、MinGit、Mihomo、QEMU 准备，Flutter analyze、共享与 Harness/LMCP/自更新测试、Windows Release 编译和 30 项完整运行时验证。
- 最终 Windows ZIP：283,281,459 bytes；SHA-256 `eac7044e0e085c950e5d65f50ec8a2fc803a3ae39f9b698b39c603cbbc0578f9`。
- 下载 Artifact 后再次执行 `unzip -t`，并实查 `vibekits.exe`、Harness Node、ADB、Git HTTPS helper、7-Zip、Mihomo、QEMU 均存在。

## KEMI 市场正式发布闭环

用户核对精确字段并明确确认后，使用 KEMI 管理员 API 上传并免审上架；未使用作废的首轮 Windows ZIP。

| 系统 | app_id | 市场版本 | 大小 | SHA-256 |
|---|---:|---|---:|---|
| macOS | 53 | `1.9.0-dev.153` / 2153 | 263,093,194 | `f50fdaecb3f70a316681eff5f61692668781a5a648ec6fefd9845c41d716606c` |
| Windows | 54 | `1.9.0-dev.153` / 2153 | 283,281,459 | `eac7044e0e085c950e5d65f50ec8a2fc803a3ae39f9b698b39c603cbbc0578f9` |

- 两端逻辑包名均为 `com.caucy.vibekits`，分类为“开发工具”，`list_in_store=1`、`force_update=0`，状态均为 `1`（已上架）。
- 公开更新接口以 `version_code=0` 查询，两端均返回 `has_update=true`，且 URL、大小、SHA-256 与上传结果完全一致。
- 同一接口以当前 `version_code=2153` 查询，两端均返回 `has_update=false`，没有自更新循环。
- 上传使用的临时管理员令牌仅存于受限临时文件，发布完成后立即删除；账号、密码和令牌均未进入源码、文档、Git 或命令输出。
