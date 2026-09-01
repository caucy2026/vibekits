# VibeKits 正式 APP 产物目录

本项目今后的桌面正式/验收 APP 统一释放到本目录，不再要求用户从 Flutter 的
`build/` 中寻找产物。

- macOS 固定可运行路径：`bin/Vibekits.app`
- 对外 ZIP、安装包和校验文件也放在 `bin/`，文件名必须包含版本与平台。
- 每次复制前必须完成版本、架构、签名和 SHA-256 检查；Developer ID 正式包还必须
  验证 Apple 公证票据。
- 二进制产物由 `.gitignore` 排除，Git 只保存本说明和构建源码；发布记录必须写明
  产物路径、版本、Git commit 和 SHA-256。

当前 `bin/Vibekits.app` 是供本机验收的 macOS Release。若签名显示 `adhoc`，只能
作为本机测试包，不能标记为已完成 Developer ID 公证的外发正式包。
