# VibeKits 正式 APP 产物目录

本项目今后的桌面正式/验收 APP 统一释放到本目录，不再要求用户从 Flutter 的
`build/` 中寻找产物。

- macOS 固定可运行路径：`bin/Vibekits.app`
- 对外 ZIP、安装包和校验文件也放在 `bin/`，文件名必须包含版本与平台。
- 每次复制前必须完成版本、架构、签名和 SHA-256 检查；Developer ID 正式包还必须
  验证 Apple 公证票据。
- 二进制产物由 `.gitignore` 排除，Git 只保存本说明和构建源码；发布记录必须写明
  产物路径、版本、Git commit 和 SHA-256。

当前正式基线为 `Vibekits.app` / `1.9.0-dev.150+2150`，以及归档
`Vibekits-1.9.0-dev.150+2150-macos-universal-notarized.zip`。对应源码 commit 为
`e5c50010313d8c3b4b452e58f62b20681af6a25f`。Apple 公证状态为 Accepted
（Submission ID `525138ba-cd62-4b0c-ab57-e362e88b6b32`），ZIP SHA-256 为
`743e5c94362a94e47c36b475acbdb3a0719eb8b2a3d3751de2a3434f6e88af1d`。

签名并 staple 后的主可执行文件 SHA-256 为
`987d616177622e152be81bafdde728b86197db2d39412933aa196291babb4e04`，
`App.framework` 二进制 SHA-256 为
`9fac6b9b4ba796bf3beeb47520d87f8fe21bcc923f3f5fd540941061ca42a818`。

该版本除签名、公证和 Gatekeeper 外，还必须通过内置 Node JIT entitlement、DSH
启动及真实 Harness MCP 目录调用门禁。若签名显示 `adhoc`，只能作为本机测试包，
不能标记为已完成 Developer ID 公证的外发正式包。
