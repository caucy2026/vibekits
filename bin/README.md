# VibeKits 正式 APP 产物目录

本项目今后的桌面正式/验收 APP 统一释放到本目录，不再要求用户从 Flutter 的
`build/` 中寻找产物。

- macOS 固定可运行路径：`bin/Vibekits.app`
- 对外 ZIP、安装包和校验文件也放在 `bin/`，文件名必须包含版本与平台。
- 每次复制前必须完成版本、架构、签名和 SHA-256 检查；Developer ID 正式包还必须
  验证 Apple 公证票据。
- 二进制产物由 `.gitignore` 排除，Git 只保存本说明和构建源码；发布记录必须写明
  产物路径、版本、Git commit 和 SHA-256。

当前正式基线为 `Vibekits.app` / `1.9.0-dev.145+2145`，以及归档
`Vibekits-1.9.0-dev.145+2145-macos-universal-notarized.zip`。Apple 公证状态为
Accepted（Submission ID `9a0cddb1-41ce-4fe5-a231-7feb209fc128`），ZIP SHA-256 为
`60dff7aec1ec2a4887d2f9d2819c5b3b043cc90c89570697389945918352392b`。

该版本除签名、公证和 Gatekeeper 外，还必须通过内置 Node JIT entitlement、DSH
启动及真实 Harness MCP 目录调用门禁。若签名显示 `adhoc`，只能作为本机测试包，
不能标记为已完成 Developer ID 公证的外发正式包。
