# 第三方组件、模型与供应链记录

更新日期：2026-08-19

适用版本：`1.9.0-dev.23+33`

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
| Git for Windows MinGit x64 | 2.55.0.windows.3 | Git 状态、Diff、日志、版本对比、本地安全分支与代理诊断 | GPL-2.0-only；归档内各组件按各自许可证 | 官方发布资产 `MinGit-2.55.0.3-64-bit.zip`；SHA-256 `f48e2d2dc74a24454adc6d8fd0ac25bf9c2386f19cfb06202b9465aaad4f9f05`；`tool/prepare_git_runtime.ps1` 校验后事务解压 |

数据库密码不依赖额外原生插件：Windows 直接调用系统 Credential Manager，macOS 调用系统 Keychain；Windows 已完成临时凭据写入、读取、删除真实闭环。这样避免 `flutter_secure_storage_windows` 对 Visual Studio ATL 的额外构建依赖。串口封装使用 MIT 许可证，但发布 NOTICE 必须同时保留底层 `libserialport` 的 LGPL-3.0-or-later 声明和对应源代码获取方式。

远程桌面不打包第三方协议实现：Windows 调用系统 `mstsc.exe`，macOS 调用 `/usr/bin/open` 打开系统 VNC/屏幕共享 URL。Vibekits 只传脱敏的主机和端口参数，不读取或传递桌面密码。

ADB 已将 Google Android SDK Platform-Tools 的 `adb.exe`、两个必需 DLL、NOTICE 和版本来源随 Windows 包复制；运行时只解析 App 私有 `tools/adb`，不依赖 `ANDROID_HOME` 或 PATH。

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
- 状态：官方仍是 Developer Preview，存在破坏性变更风险；Vibekits 保留可替换进程适配层，并将固定的 Node、CLI 与生产依赖打入安装包。
- 发布前由 `tool/prepare_harness_runtime.ps1` 固定安装 `@deepseek-ai/dsh@0.1.0-rc.7`，解析官方 package 的 CLI 入口，并把 Node、完整生产依赖、manifest、profile 和 `@deepseek-ai/dsh-web-app` 打入安装包。Windows 通过内置 `node` 启动内置 `dsh web`，再用 WebView2 嵌入其官方生产界面；不调用 npm/npx、不联网安装，也不依赖用户 PATH。
- DeepSeek API Key 由官方 Harness 的 Settings → Models 页面录入，写入 `$DSH_HOME/.credentials.yaml`；Web 子进程不注入 `DEEPSEEK_API_KEY`、`DEEPSEEK_MODEL` 或 `DEEPSEEK_BASE_URL`，避免把官方字段锁成只读并确保设置热更新。旧版系统凭据只做一次迁移，密钥不进入源码、安装包、普通设置或日志。
- Windows Release 内置官方包已实启 `dsh web`，本机 URL 返回 HTTP 200 且可正常 Ctrl+C 停止。macOS 真启动、WebView 容器和停止后无残留进程仍待验收。

## 开源借鉴边界

- Windows 清理规则研究参考 Microsoft Known Folders、Storage Sense、Disk Cleanup、WER 与 Delivery Optimization 官方文档，并审阅 Winapp2 与 BleachBit。Vibekits 使用独立编写的版本化规则库：未复制 Winapp2 规则（仓库基础规则许可不明确），未移植 GPL-3.0 的 BleachBit 源码/cleaner definitions。
- 2026-08-18 继续审阅 [Kudu](https://github.com/AdventDevInc/kudu)（MIT）、[constUP Garbage Cleaner](https://github.com/constup-foss/garbage-cleaner-powershell)（MPL-2.0）与 [BitCleanerX](https://github.com/paulocoutinhox/bitcleanerx)（MIT）。Vibekits 没有嵌入上游源码或规则文件；独立实现了最小年龄、最大扫描深度、直接文件名白名单和 dry-run 候选模型，并根据公开路径语义增加 JetBrains/WSLg/Gradio/.NET/Scoop 等受限规则。MPL 上游实现未复制，因此不引入其文件级许可证传播要求。
- 2026-08-19 再次复核 [BleachBit CleanerML](https://github.com/bleachbit/cleanerml)（GPL-3.0-or-later）、[Winapp2](https://github.com/MoscaDotTo/Winapp2)（仓库当前标注 CC-BY-SA-4.0）与 [Czkawka](https://github.com/qarmin/czkawka)（MIT）。仅吸收声明式规则、Detect/Exclude/Warning、发布前验证、dry-run、排除路径、停止标记和进度等通用设计；未复制 CleanerML/Winapp2 规则、源码或文本。Vibekits 独立实现系统盘 `.log` 高风险清单、Harness 调试产物保留期和 v2 本地审计日志。
- 2026-08-19 将上述安全模型扩展到 macOS 明确缓存/日志目录，并新增 Windows 系统盘只读空间审计。空间审计只统计元数据和容量，不复制第三方源码、不读取文件正文，也不把未知根目录自动变为删除规则。
- Harness 工作台直接嵌入官方 `@deepseek-ai/dsh-web-app` 生产产物，不再由 Flutter 仿制项目、会话、对话、工具、目标/计划、任务、模型、权限、插件与设置。Vibekits 的 ADB/串口/Git 等以官方 MCP client 插件扩展接入。
- Zed、Geany、OpenSSH 和 GitHub 文档只用于工作流与操作习惯研究。Git 执行采用官方 MinGit 二进制分发，按 GPL-2.0-only 及归档组件许可证履行随附义务，不复制修改其源码。
- SSH 交互终端、SFTP 和端口转发使用 `dartssh2`，终端渲染使用 `xterm`；主机密钥必须经用户确认或与已绑定指纹一致。转发连接和数据泵运行在后台 Isolate；不自行实现密码学。
- GitHub 网络诊断只读取 DNS/TLS/HTTPS/代理/hosts/SSH 状态，不移植 FastGithub 的 hosts、代理、证书或系统修改逻辑。
- 不直接嵌入 GPL/AGPL 工具源码；新增组件必须先记录版本、许可证、上游、产物方式和哈希。

## 当前供应链缺口

- macOS ONNX Runtime arm64/x64 原生库和桥接尚未固定版本与哈希，因此 macOS OCR 不得标记完成。
- macOS 自包含 Git 与 Harness 运行时尚未生成和实机验收，因此本轮“无外部依赖”只对 Windows 发布路径闭环。
- 正式安装器还需汇总完整 NOTICE/SBOM，并在安装目录提供所有必须随附的许可证文本。
- HEIF/AVIF/JXL/RAW 解码器尚未选型；许可证和二进制供应链评审前不得只注册扩展名假装支持。
