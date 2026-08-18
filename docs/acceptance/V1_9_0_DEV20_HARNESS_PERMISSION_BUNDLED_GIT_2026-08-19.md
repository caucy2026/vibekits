# Vibekits 1.9.0-dev.20 Harness 原生权限与自包含 Git 验收

版本：`1.9.0-dev.20+30`

## 本轮验收合同

- 权限菜单必须改变官方 Harness 原生工具的真实执行策略，不得只控制 Vibekits MCP 工具。
- “请求批准”进入 App 审批；“帮我批准”对普通请求自动通过；“完全访问权限”映射官方不重复询问模式。
- Windows Git 工作区、GitHub 诊断和 Harness Git 工具不得调用用户 PATH 中的 Git。
- Harness 能对比两个 Git 版本，并能在审批后创建本地安全分支；创建分支不得切换或修改当前工作区文件。
- Windows Release 缺少 Harness 或 Git 内置运行时必须在构建阶段失败。

## 实现证据

- `HarnessAgentRequest.permissionMode` 映射 `workspace-write` / `danger-full-access`，启动官方 dsh 时写入 `DSH_PERMISSION_MODE`。
- `vibekits-approval.mjs` 监听官方 `approval/request`，使用随机 Bearer token 回送 App 的 `/native-approval`，网络或桥失败时拒绝执行。
- 官方 MinGit `2.55.0.windows.3` 下载后核对 SHA-256 `f48e2d2dc74a24454adc6d8fd0ac25bf9c2386f19cfb06202b9465aaad4f9f05`，验证 `cmd/git.exe --version` 后才进入运行时目录。
- Git 运行时只解析安装目录 `tools/git` 或开发准备目录；不存在时明确报告安装包损坏，不回退系统 PATH。
- SSH 本地端口转发改用 `dartssh2` 的 forward channel 与回环监听，不再启动系统 `ssh`。

## 自动验收

- `flutter analyze`：0 问题。
- 官方 dsh 全栈测试在同一轮同时调用 Vibekits SHA-256 与官方 `pwsh`；扩大权限请求真实进入 App 回调，批准后在临时工作区真实写入验证文件并正常结束。
- Harness 回环审批、MCP、权限映射、设置持久化、会话切换保留、内置 Git 仓库检查、两版本 Diff、本地分支不切换、SSH 参数和远程工作区定向测试均通过。
- Windows Debug 与 Release 均构建成功；Release `FileVersion` / `ProductVersion` 均为 `1.9.0-dev.20+30`。
- `tool/verify_windows_bundle.ps1` 从 Release 目录验证 17 项必需运行时/模型资产存在，内置 Git 报告 `2.55.0.windows.3`，Harness 审批插件通过内置 Node 语法检查。

## 未宣称完成

- macOS 自包含 Git、Harness 和 OCR 原生运行时仍需在 macOS 实机准备与验收。
- Windows/macOS 自带的远程桌面、文件定位、凭据库和截图入口属于操作系统能力，不作为第三方安装依赖打包。
