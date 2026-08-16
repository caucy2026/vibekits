# 第三方组件、模型与供应链记录

更新日期：2026-08-16

适用版本：`1.7.0+9`

## 发布时直接使用的关键组件

| 组件 | 固定版本 | 用途 | 许可证 | 来源与完整性 |
|---|---|---|---|---|
| 7-Zip Windows x64 | 26.02 | RAR/7z/ZIP/ISO/ZSTD/CAB/WIM/DMG 等列表与解压 | LGPL-2.1-or-later；RAR 解码另受 unRAR 限制 | 官方安装器；安装器 SHA-256 `6745fa76...2ef0`；`native/7zip` 保留原始许可证、历史和二进制哈希 |
| ONNX Runtime C API | 随 sherpa-onnx Windows 运行时 | PP-OCRv6 tiny CPU 推理 | MIT | 官方头文件；Release 运行库由已锁定依赖提供，Vibekits 桥接只调用公开 C API |
| `sherpa_onnx` | 1.13.5 | Silero VAD 与 Windows ONNX Runtime 分发 | Apache-2.0 | pub.dev 锁文件 SHA-256 `94f9fc85...d31b` |
| `sqlite3` | 3.5.1 | SQLite 只读数据库管理和 Windows/macOS 原生资产 | MIT | pub.dev 锁文件 SHA-256 `64b2c63c...478a`；使用 Dart native-asset hooks |
| `image` | 4.9.1 | 图片格式探测、首帧解码、方向固化和 PNG 预览 | MIT | pub.dev 锁文件 SHA-256 `6300175e...c52` |
| `postgres` | 3.5.12 | PostgreSQL TLS 连接、对象浏览、分页和只读查询 | BSD-3-Clause | pub.dev SHA-256 `123de5cb...299b`；普通设置只保存脱敏连接资料 |

数据库密码不依赖额外原生插件：Windows 直接调用系统 Credential Manager，macOS 调用系统 Keychain；Windows 已完成临时凭据写入、读取、删除真实闭环。这样避免 `flutter_secure_storage_windows` 对 Visual Studio ATL 的额外构建依赖。

完整 Dart/Flutter 直接与传递依赖版本、来源和包哈希以 `pubspec.lock` 为准；发布前不得绕过锁文件临时升级。

## PP-OCRv6 tiny 官方模型包

上游：PaddlePaddle/PaddleOCR；许可证：Apache-2.0；模型由用户主动安装，不随应用静默下载。

| 资产 | 字节 | SHA-256 |
|---|---:|---|
| `ppocrv6_tiny_det.onnx` | 1,780,590 | `193bab7a04fca699a6c82e6abb5b81bdb28177f0abd4062552b04908dafb19f8` |
| `ppocrv6_tiny_rec.onnx` | 4,462,639 | `9ef676d6ed3c88256a2d92c640c44f25b0c40947e111b14b8be8f594091563e6` |
| `ppocrv6_tiny_rec.yml` | 55,571 | `66170210bad538e83fff3c4a3867e547d6bf20b50d64b20347c4b913f3034ea1` |

三项作为应用内置资源由用户主动安装；安装服务写入隔离临时目录，逐项核对完整 SHA-256，全部通过后才事务替换，任一失败清理暂存且不替换现有可用包。

## DeepSeek Harness 可选运行时

- 上游：`https://github.com/deepseek-ai/deepseek-harness`；许可证：MIT；当前官方 CLI 版本：`@deepseek-ai/dsh@0.1.0-rc.5`。
- 状态：官方明确标注 Developer Preview，存在破坏性变更风险；Vibekits 只保留可替换进程适配层，不把其源码或依赖打入安装包。
- 用户在模型页选择工作区并提交任务后，Vibekits 以参数数组启动 `npx --yes @deepseek-ai/dsh@0.1.0-rc.5 --profile headless <任务>`；需要 Node.js 22.19+ 或 24+。工作目录限定为用户选定项目，输出仅在当前应用会话流式显示。
- DeepSeek/API 及自定义供应商密钥由 Harness 官方控制台管理，Vibekits 不读取、不复制、不写日志。代理具备文件与命令能力，启动页明确要求 Git 备份和逐项审批。
- 当前机器的官方包帮助探测在下载阶段超过 2 分钟无输出后人工取消；这不是已通过的实启证据。发布前还需记录 npm 包完整性、Windows/macOS 真启动和停止后无残留进程。

## 开源借鉴边界

- Zed、Geany、OpenSSH、Git 和 GitHub 文档只用于工作流与操作习惯研究，没有复制 GPL 项目代码。
- SSH/SFTP、Git 使用用户系统安装的官方命令；参数以列表传递，`runInShell=false`。
- GitHub 网络诊断只读取 DNS/TLS/HTTPS/代理/hosts/SSH 状态，不移植 FastGithub 的 hosts、代理、证书或系统修改逻辑。
- 不直接嵌入 GPL/AGPL 工具源码；新增组件必须先记录版本、许可证、上游、产物方式和哈希。

## 当前供应链缺口

- macOS ONNX Runtime arm64/x64 原生库和桥接尚未固定版本与哈希，因此 macOS OCR 不得标记完成。
- 正式安装器还需汇总完整 NOTICE/SBOM，并在安装目录提供所有必须随附的许可证文本。
- HEIF/AVIF/JXL/RAW 解码器尚未选型；许可证和二进制供应链评审前不得只注册扩展名假装支持。
