# dev.58～dev.61 GitHub 备份记录

日期：2026-08-21

## 备份范围

| 版本 | 提交 | 内容 |
|---|---|---|
| v1.9.0-dev.58 | `87d4d47` | Windows 节点、GitHub 诊断与受控备份基础 |
| v1.9.0-dev.59 | `d4fcea7` | 系统盘清理缺口与聚合候选 |
| v1.9.0-dev.60 | `84677a7` | 实际释放口径与软件使用建议 |
| v1.9.0-dev.61 | `b2366b6` | 节点 helper/设备/跨设备证据安全底座 |

目标仓库：`ssh://git@ssh.github.com:443/caucy2026/vibekits.git`

目标引用：

- `refs/heads/main`
- `refs/tags/v1.9.0-dev.58`
- `refs/tags/v1.9.0-dev.59`
- `refs/tags/v1.9.0-dev.60`
- `refs/tags/v1.9.0-dev.61`

## 安全边界

- 仅执行普通 fast-forward push，不使用 force/force-with-lease。
- 不删除远端分支或标签，不修改历史标签。
- 不提交未跟踪的调试截图、临时 smoke 脚本、构建目录、API Key、密码、私钥或凭据。
- Release 产物仍保留在本机构建目录；GitHub 保存可重建源码、锁文件、文档和校验脚本。

## 核验方法

推送后使用 `git ls-remote` 读取远端 `main` 和四个标签；`main` 必须等于本次归档提交，标签解引用后的 commit 必须分别对应上表提交。命令输出只包含引用和 SHA，不包含凭据。

## 关联验收

- `V1_9_0_DEV58_WINDOWS_NODE_GITHUB_BACKUP_2026-08-21.md`
- `V1_9_0_DEV60_ACTUAL_RELEASE_AND_APP_USAGE_2026-08-21.md`
- `V1_9_0_DEV61_WINDOWS_NODE_SECURITY_FOUNDATION_2026-08-21.md`
