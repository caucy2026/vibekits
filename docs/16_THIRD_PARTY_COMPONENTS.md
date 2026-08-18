# 第三方组件、模型与供应链记录

更新日期：2026-08-19

适用版本：`1.9.0-dev.19+29`

## 发布时直接使用的关键组件

| 组件 | 固定版本 | 用途 | 许可证 | 来源与完整性 |
|---|---|---|---|---|
| 7-Zip Windows x64 | 26.02 | RAR/7z/ZIP/ISO/ZSTD/CAB/WIM/DMG 等列表与解压 | LGPL-2.1-or-later；RAR 解码另受 unRAR 限制 | 官方安装器；安装器 SHA-256 `6745fa76...2ef0`；`native/7zip` 保留原始许可证、历史和二进制哈希 |
| ONNX Runtime C API | 随 sherpa-onnx Windows 运行时 | PP-OCRv6 tiny CPU 推理 | MIT | 官方头文件；Release 运行库由已锁定依赖提供，Vibekits 桥接只调用公开 C API |
| `sherpa_onnx` | 1.13.5 | Silero VAD 与 Windows ONNX Runtime 分发 | Apache-2.0 | pub.dev 锁文件 SHA-256 `94f9fc85...d31b` |
| `sqlite3` | 3.5.1 | SQLite 只读数据库管理和 Windows/macOS 原生资产 | MIT | pub.dev 锁文件 SHA-256 `64b2c63c...478a`；使用 Dart native-asset hooks |
| `image` | 4.9.1 | 图片格式探测、首帧解码、方向固化和 PNG 预览 | MIT | pub.dev 锁文件 SHA-256 `6300175e...c52` |
| `postgres` | 3.5.12 | PostgreSQL TLS 连接、对象浏览、分页和只读查询 | BSD-3-Clause | pub.dev SHA-256 `123de5cb...299b`；普通设置只保存脱敏连接资料 |
| `mysql_dart` | 3.0.0 | MySQL/MariaDB TLS、对象浏览、分页和只读查询 | MIT | pub.dev 锁文件 SHA-256 `7796f958...464ba`；每次操作在可终止 Isolate 中建立短连接 |
| `libserialport_plus` | 1.0.1 | Windows/macOS 串口枚举、帧参数、读写和关闭 | Dart 封装 MIT；原生 `libserialport` LGPL-3.0-or-later | pub.dev 锁文件 SHA-256 `b6e55f52...31902`；原生动态库由 native-assets 构建并随 Release 分发 |
| `dartssh2` | 2.22.5 | SSH 密码/私钥认证、主机指纹、远程 PTY、SFTP 与三类端口转发 | MIT | pub.dev 锁文件；固定在 `pubspec.lock`，Vibekits 强制提供主机密钥验证回调且不关闭验证 |
| `xterm` | 4.0.0 | Windows/macOS 交互终端渲染、键盘、选择与缩放 | MIT | pub.dev 锁文件；纯 Flutter 终端视图，不携带 SSH 密码学 |

数据库密码不依赖额外原生插件：Windows 直接调用系统 Credential Manager，macOS 调用系统 Keychain；Windows 已完成临时凭据写入、读取、删除真实闭环。这样避免 `flutter_secure_storage_windows` 对 Visual Studio ATL 的额外构建依赖。串口封装使用 MIT 许可证，但发布 NOTICE 必须同时保留底层 `libserialport` 的 LGPL-3.0-or-later 声明和对应源代码获取方式。

远程桌面不打包第三方协议实现：Windows 调用系统 `mstsc.exe`，macOS 调用 `/usr/bin/open` 打开系统 VNC/屏幕共享 URL。Vibekits 只传脱敏的主机和端口参数，不读取或传递桌面密码。

ADB 不随当前 Release 打包或静默下载：只检测用户已安装的 Google Android SDK Platform-Tools。当前 Windows 实机发现 `adb.exe` 版本 `1.0.41`（Platform-Tools `31.0.3-7562133`）；正式发布若改为内置，必须先补 Google 许可证、固定版本、来源与完整 SHA-256。

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

- 上游：`https://github.com/deepseek-ai/deepseek-harness`；许可证：MIT；2026-08-18 通过 npm registry 查询的官方 CLI 版本：`@deepseek-ai/dsh@0.1.0-rc.7`。
- 状态：官方明确标注 Developer Preview，存在破坏性变更风险；Vibekits 只保留可替换进程适配层，不把其源码或依赖打入安装包。
- 发布前由 `tool/prepare_harness_runtime.ps1` 固定安装 `@deepseek-ai/dsh@0.1.0-rc.7`，解析官方 package 的 CLI 入口，并把 Node、完整生产依赖、manifest 和 profile 打入安装包。任务阶段通过内置 `node` 直接启动内置 CLI，不调用 npm/npx、不联网安装，也不依赖用户 PATH。工作目录限定为用户选定项目，输出仅在当前应用会话流式显示。
- DeepSeek API Key 由 Harness 页录入并写入 Windows Credential Manager/macOS Keychain，启动官方子进程时仅放入 `DEEPSEEK_API_KEY` 环境变量；参数、普通设置和日志均不包含密钥。模型和兼容端点分别经 `DEEPSEEK_MODEL`、`DEEPSEEK_BASE_URL` 传递，仍需以官方真实任务验证版本支持情况。
- 当前机器的官方包帮助探测在下载阶段超过 2 分钟无输出后人工取消；这不是已通过的实启证据。发布前还需记录 npm 包完整性、Windows/macOS 真启动和停止后无残留进程。

## 开源借鉴边界

- Windows 清理规则研究参考 Microsoft Known Folders、Storage Sense、Disk Cleanup、WER 与 Delivery Optimization 官方文档，并审阅 Winapp2 与 BleachBit。Vibekits 使用独立编写的版本化规则库：未复制 Winapp2 规则（仓库基础规则许可不明确），未移植 GPL-3.0 的 BleachBit 源码/cleaner definitions。
- 2026-08-18 继续审阅 [Kudu](https://github.com/AdventDevInc/kudu)（MIT）、[constUP Garbage Cleaner](https://github.com/constup-foss/garbage-cleaner-powershell)（MPL-2.0）与 [BitCleanerX](https://github.com/paulocoutinhox/bitcleanerx)（MIT）。Vibekits 没有嵌入上游源码或规则文件；独立实现了最小年龄、最大扫描深度、直接文件名白名单和 dry-run 候选模型，并根据公开路径语义增加 JetBrains/WSLg/Gradio/.NET/Scoop 等受限规则。MPL 上游实现未复制，因此不引入其文件级许可证传播要求。
- 2026-08-19 将上述安全模型扩展到 macOS 明确缓存/日志目录，并新增 Windows 系统盘只读空间审计。空间审计只统计元数据和容量，不复制第三方源码、不读取文件正文，也不把未知根目录自动变为删除规则。
- Harness 工作台以 DeepSeek 官方社区 Web UI 的功能模块为基线（工作区、会话、对话、工具、目标/计划、任务、模型、权限、插件与设置），使用 Vibekits 自有 Flutter 信息架构和接近 Codex 的中性色视觉；没有嵌入官方 React 产物或品牌素材。
- Zed、Geany、OpenSSH、Git 和 GitHub 文档只用于工作流与操作习惯研究，没有复制 GPL 项目代码。
- SSH 交互终端、SFTP 和端口转发使用 `dartssh2`，终端渲染使用 `xterm`；主机密钥必须经用户确认或与已绑定指纹一致。转发连接和数据泵运行在后台 Isolate；不自行实现密码学。
- GitHub 网络诊断只读取 DNS/TLS/HTTPS/代理/hosts/SSH 状态，不移植 FastGithub 的 hosts、代理、证书或系统修改逻辑。
- 不直接嵌入 GPL/AGPL 工具源码；新增组件必须先记录版本、许可证、上游、产物方式和哈希。

## 当前供应链缺口

- macOS ONNX Runtime arm64/x64 原生库和桥接尚未固定版本与哈希，因此 macOS OCR 不得标记完成。
- 正式安装器还需汇总完整 NOTICE/SBOM，并在安装目录提供所有必须随附的许可证文本。
- HEIF/AVIF/JXL/RAW 解码器尚未选型；许可证和二进制供应链评审前不得只注册扩展名假装支持。
