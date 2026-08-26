# v1.9.0-dev.114 SSH 密码认证验收

## 现场根因

旧页面只有“私钥（可选）”输入框。用户按常见 SSH 使用习惯输入密码后，值被写入 `RemoteConnectionProfile.identityFile`，本地文件校验随即失败，连接没有到达服务器。

## 修复

- 默认认证方式为“密码”，另可切换“私钥”。
- 密码框掩码显示、支持粘贴和回车连接。
- 密码只传入内存 `secret`；私钥模式才写入和验证 `identityFile`。
- 已保存密码仍来自 Windows 凭据管理器/macOS 钥匙串。
- SSH 成功后 SFTP 复用同一会话，不重复索要密码。

## 验收

- 专项 Widget 测试：密码 `not-a-private-key-path` 被传入 `secret`，`identityFile` 为 `null`，未弹二次密码框，未出现私钥路径错误；1/1 通过。
- 目标网络层：`119.96.24.110:39281` TCP 连接成功，耗时 53 ms。
- `flutter analyze remote_workspace.dart`：0 问题。
- Windows Release：`v1.9.0-dev.114+124` 构建成功并已打开前台。
- 界面证据：`.tmp/dev114-ssh-auth.png`。
