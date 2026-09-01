# 第三方组件、模型与供应链记录

更新日期：2026-09-02

适用版本：`1.9.0-dev.146+2146`

## 发布时直接使用的关键组件

| 组件 | 固定版本 | 用途 | 许可证 | 来源与完整性 |
|---|---|---|---|---|
| 7-Zip Windows x64 | 26.02 | RAR/7z/ZIP/ISO/ZSTD/CAB/WIM/DMG 等列表与解压 | LGPL-2.1-or-later；RAR 解码另受 unRAR 限制 | 官方安装器；安装器 SHA-256 `6745fa76...2ef0`；`native/7zip` 保留原始许可证、历史和二进制哈希 |
| 7-Zip macOS Universal | 25.01 | RAR/7z/ZIP/ISO/ZSTD/CAB/WIM/DMG 等列表与解压 | LGPL-2.1-or-later；RAR 解码另受 unRAR 限制 | 官方 `7z2501-mac.tar.xz`，SHA-256 `26aa75bc262bb10bf0805617b95569c3035c2c590a99f7db55c7e9607b2685e0`；固定 `7zz`、许可证和 `RUNTIME-INFO.txt` 已纳入 Git，二进制 SHA-256 `5c2fd36f00a66f7787dcf1badd977d44a02b50063fe5678e1f19ff64797432ed`；`x86_64/arm64` 均 `minos=12.0`；26.02 因官方二进制最低系统过高不进入 dev.146 |
| ONNX Runtime C API | 随 sherpa-onnx Windows 运行时 | PP-OCRv6 tiny CPU 推理 | MIT | 官方头文件；Release 运行库由已锁定依赖提供，Vibekits 桥接只调用公开 C API |
| `sherpa_onnx` | 1.13.6 | Silero VAD 与 Windows/macOS ONNX Runtime 分发 | Apache-2.0 | pub.dev 锁文件 SHA-256 `5d6cd57eca94caf4b3ce3b07d9affb11ad68d14c37e1e7aa3f60e63b59aee361` |
| `sqlite3` | 3.5.2 | SQLite 只读数据库管理和原生资产 | MIT | 审计副本位于 `third_party/dart/sqlite3`；macOS 使用系统 `libsqlite3` 以满足官方支持和 macOS 12 部署门禁，其他平台保留上游默认 native-asset 行为；上游 pub.dev SHA-256 `4c7fe79840389aaeaf05fd093f795b631b5a98e2bd28d54e555c100f4a9c7a1c` |
| `image` | 4.9.2 | 图片格式探测、首帧解码、方向固化和 PNG 预览 | MIT | pub.dev 锁文件 SHA-256 `1976370a4df3091bb0f72409c187ad1f9132a818bc6b95ca59c0bae1c75c688e` |
| `postgres` | 3.5.12 | PostgreSQL TLS 连接、对象浏览、分页和只读查询 | BSD-3-Clause | pub.dev SHA-256 `123de5cb...299b`；普通设置只保存脱敏连接资料 |
| `mysql_dart` | 3.0.0 | MySQL/MariaDB TLS、对象浏览、分页和只读查询 | MIT | pub.dev 锁文件 SHA-256 `7796f958...464ba`；每次操作在可终止 Isolate 中建立短连接 |
| `libserialport_plus` | 1.0.4 | Windows/macOS 串口枚举、帧参数、读写和关闭 | Dart 封装 MIT；原生 `libserialport` LGPL-3.0-or-later | 审计副本位于 `third_party/dart/libserialport_plus`，仅在 macOS hook 增加 `-mmacos-version-min=12.0`；上游 pub.dev SHA-256 `90609c55b05668fd33d4aeea22cc795037adc67891b032fba7ff42f93a29e678` |
| `dartssh2` | 2.22.5 | SSH 密码/私钥认证、主机指纹、远程 PTY、SFTP 与三类端口转发 | MIT | pub.dev 锁文件；固定在 `pubspec.lock`，Vibekits 强制提供主机密钥验证回调且不关闭验证 |
| `xterm` | 4.0.0 | Windows/macOS 交互终端渲染、键盘、选择与缩放 | MIT | pub.dev 锁文件；纯 Flutter 终端视图，不携带 SSH 密码学 |
| `audioplayers` | 6.5.1 | 音频调试工作区本地 PCM/WAV 播放 | MIT | pub.dev 锁文件 SHA-256 `5441fa0ceb8807a5ad701199806510e56afde2b4913d9d17c2f19f2902cf0ae4`；Windows/macOS/Android 平台实现随 Flutter Release 打包，不要求外部播放器，不用于联网流媒体 |
| `objective_c` | 9.5.0 | Flutter macOS 原生资产桥 | BSD-3-Clause | 审计副本位于 `third_party/dart/objective_c`，仅把 native-asset macOS target clamp 为 12；上游 pub.dev SHA-256 `b7fb95a6d9a4f009edd63dc5ac69f07420b23a16161c6dd8660290b59c602e8e` |
| Git for Windows MinGit x64 | 2.55.0.windows.3 | Git 状态、Diff、日志、版本对比、本地安全分支与代理诊断 | GPL-2.0-only；归档内各组件按各自许可证 | 官方发布资产 `MinGit-2.55.0.3-64-bit.zip`；SHA-256 `f48e2d2dc74a24454adc6d8fd0ac25bf9c2386f19cfb06202b9465aaad4f9f05`；`tool/prepare_git_runtime.ps1` 校验后事务解压 |
| Git macOS Universal | 2.53.0 | Git 状态、Diff、日志、安全分支、clone/fetch/push 与 HTTPS 远程 | GPL-2.0-only；依赖按上游许可证 | kernel.org 官方 `git-2.53.0.tar.xz`，SHA-256 `5818bd7d80b061bbbdfec8a433d609dc8818a05991f731ffc4a561e2ca18c653`；分别以 `MACOSX_DEPLOYMENT_TARGET=12.0` 构建 x86_64/arm64 后 lipo；10 个唯一 Mach-O 逐项门禁，159 个命令别名使用包内相对 symlink，避免 hardlink 重签破坏；原生/Rosetta init/commit/status/log 和 GitHub HTTPS `ls-remote` 均通过 |

数据库密码不依赖额外原生插件：Windows 直接调用系统 Credential Manager，macOS 调用系统 Keychain；Windows 已完成临时凭据写入、读取、删除真实闭环。这样避免 `flutter_secure_storage_windows` 对 Visual Studio ATL 的额外构建依赖。串口封装使用 MIT 许可证，但发布 NOTICE 必须同时保留底层 `libserialport` 的 LGPL-3.0-or-later 声明和对应源代码获取方式。

音频波形交互参考 `SimformSolutionsPvtLtd/audio_waveforms`（MIT）和 `ryanheise/just_waveform`（MIT）；频谱与信号健康工作流参考 Spek（GPL-3.0）与 mscope。Vibekits 未复制这些项目源码或品牌界面，PCM/WAV 解析、降采样波形、DFT、RMS/峰值/削波/静音/DC 分析为独立纯 Dart 实现。

远程桌面不打包第三方协议实现：Windows 调用系统 `mstsc.exe`，macOS 调用 `/usr/bin/open` 打开系统 VNC/屏幕共享 URL。Vibekits 只传脱敏的主机和端口参数，不读取或传递桌面密码。

ADB 已将 Google Android SDK Platform-Tools 的 `adb.exe`、两个必需 DLL、NOTICE 和版本来源随 Windows 包复制；运行时只解析 App 私有 `tools/adb`，不依赖 `ANDROID_HOME` 或 PATH。

完整 Dart/Flutter 直接与传递依赖版本、来源和包哈希以 `pubspec.lock` 为准；发布前不得绕过锁文件临时升级。

## PP-OCRv6 tiny 官方模型包

上游：PaddlePaddle/PaddleOCR；许可证：Apache-2.0；模型由用户主动安装，不随应用静默下载。

### PP-OCRv6 精度档策略

- 桌面高精度档：`PP-OCRv6_medium_det`（15.5M）+ `PP-OCRv6_medium_rec`（19M），合计 34.5M 参数，是 PP-OCRv6 当前最大参数组合。官方 ONNX 文件约 62 MB + 76.6 MB，必须显式安装、SHA-256 校验后使用，不能阻塞 APP/Harness 首屏。
- Windows/macOS 自动档：已安装 Medium 时优先 Medium；未安装时立即使用内置 Tiny，不联网等待。
- Android 自动档：默认 Tiny。Medium 只允许用户主动下载，不能塞入基础 APK，也不能在低内存设备上自动启用。
- Harness 获得的 OCR 结果必须同时包含像素框、0..1 相对框、九宫格区域和阅读顺序；无多模态能力时以这些结构化字段理解截图，不伪称看到了 OCR 未识别的内容。

官方模型与锁定文件：

- 检测：`PaddlePaddle/PP-OCRv6_medium_det_onnx/inference.onnx`，62,032,837 bytes，SHA-256 `eb13b44b25bb36f89528b68720af8a61d9cf381176107f465db1757b65d086e1`。
- 识别：`PaddlePaddle/PP-OCRv6_medium_rec_onnx/inference.onnx`，76,554,979 bytes，SHA-256 `9c09abf0957f7968c7586464b7397b84ad2387a0497a351af40e9acc71b673ba`。

| 资产 | 字节 | SHA-256 |
|---|---:|---|
| `ppocrv6_tiny_det.onnx` | 1,780,590 | `193bab7a04fca699a6c82e6abb5b81bdb28177f0abd4062552b04908dafb19f8` |
| `ppocrv6_tiny_rec.onnx` | 4,462,639 | `9ef676d6ed3c88256a2d92c640c44f25b0c40947e111b14b8be8f594091563e6` |
| `ppocrv6_tiny_rec.yml` | 55,571 | `66170210bad538e83fff3c4a3867e547d6bf20b50d64b20347c4b913f3034ea1` |

三项作为应用内置资源由用户主动安装；安装服务写入隔离临时目录，逐项核对完整 SHA-256，全部通过后才事务替换，任一失败清理暂存且不替换现有可用包。

## DeepSeek Harness 可选运行时

- 上游：`https://github.com/deepseek-ai/deepseek-harness`；许可证：MIT；2026-08-27 通过官方 npm registry 查询并固定的 CLI 版本：`@deepseek-ai/dsh@0.1.1-rc.2`。
- 状态：官方仍是 Developer Preview，存在破坏性变更风险；Vibekits 保留可替换进程适配层，并将固定的 Node、CLI 与生产依赖打入安装包。
- 发布前 Windows 由 `tool/prepare_harness_runtime.ps1`、macOS 由 `tool/prepare_harness_runtime_macos.sh` 固定安装 `@deepseek-ai/dsh@0.1.1-rc.2`，解析官方 package 的 CLI 入口，并把 Node、完整生产依赖、manifest、profile 和 `@deepseek-ai/dsh-web-app` 打入安装包。macOS 脚本从 nodejs.org 下载最低兼容的 Node 22.19.0 arm64/x64 官方归档并逐项核对官方 `SHASUMS256.txt`，使用 `lipo` 生成 Universal Node，同时显式补齐 sharp、libvips、koffi、ripgrep 和 node-pty 的 x64/arm64 原生包。上游可选 `node-addon-require-builtin` Darwin 二进制要求 macOS 15，故不打包；所有启动固定传 `--expose-internals` 使用 Node 官方能力。运行时不调用 npm/npx、不联网安装，也不依赖用户 PATH。
- DeepSeek API Key 由官方 Harness 的 Settings → Models 页面录入，写入 `$DSH_HOME/.credentials.yaml`；Web 子进程不注入 `DEEPSEEK_API_KEY`、`DEEPSEEK_MODEL` 或 `DEEPSEEK_BASE_URL`，避免把官方字段锁成只读并确保设置热更新。旧版系统凭据只做一次迁移，密钥不进入源码、安装包、普通设置或日志。
- Windows Release 内置官方包已实启 `dsh web`，本机 URL 返回 HTTP 200 且可正常 Ctrl+C 停止。2026-08-31 macOS Universal Release 也已完成真实启动：界面显示“Harness 就绪”，官方 DSH 实际调用 `vibekits.system.capability_check` 成功并以 `exitCode=0` 结束；详见 `56_MACOS_SELF_CONTAINED_HARNESS_ACCEPTANCE_2026-08-31.md`。正式 Developer ID 签名、公证及 Intel 实机仍是发布门槛。

## 开源借鉴边界

- 2026-08-22 复核 [DevToys](https://github.com/DevToys-app/DevToys)（MIT）、[CyberChef](https://github.com/gchq/CyberChef)（Apache-2.0）和 [Hexkit](https://github.com/trinvh/hexkit)（MIT）的公开能力分类、离线操作和组合式任务模型。Vibekits 未复制它们的源码、资源或 UI，也未增加其二进制；30 项补充工具为独立 Dart 实现，复用项目已有 `xml`/Dart 标准库和统一 ToolSpec/Harness/日志合同，因此本轮没有新增发布依赖。

- Windows 清理规则研究参考 Microsoft Known Folders、Storage Sense、Disk Cleanup、WER 与 Delivery Optimization 官方文档，并审阅 Winapp2 与 BleachBit。Vibekits 使用独立编写的版本化规则库：未复制 Winapp2 规则（仓库基础规则许可不明确），未移植 GPL-3.0 的 BleachBit 源码/cleaner definitions。
- 2026-08-18 继续审阅 [Kudu](https://github.com/AdventDevInc/kudu)（MIT）、[constUP Garbage Cleaner](https://github.com/constup-foss/garbage-cleaner-powershell)（MPL-2.0）与 [BitCleanerX](https://github.com/paulocoutinhox/bitcleanerx)（MIT）。Vibekits 没有嵌入上游源码或规则文件；独立实现了最小年龄、最大扫描深度、直接文件名白名单和 dry-run 候选模型，并根据公开路径语义增加 JetBrains/WSLg/Gradio/.NET/Scoop 等受限规则。MPL 上游实现未复制，因此不引入其文件级许可证传播要求。
- 2026-08-19 再次复核 [BleachBit CleanerML](https://github.com/bleachbit/cleanerml)（GPL-3.0-or-later）、[Winapp2](https://github.com/MoscaDotTo/Winapp2)（仓库当前标注 CC-BY-SA-4.0）与 [Czkawka](https://github.com/qarmin/czkawka)（MIT）。仅吸收声明式规则、Detect/Exclude/Warning、发布前验证、dry-run、排除路径、停止标记和进度等通用设计；未复制 CleanerML/Winapp2 规则、源码或文本。Vibekits 独立实现系统盘 `.log` 高风险清单、Harness 调试产物保留期和 v2 本地审计日志。
- 2026-08-19 将上述安全模型扩展到 macOS 明确缓存/日志目录，并新增 Windows 系统盘只读空间审计。空间审计只统计元数据和容量，不复制第三方源码、不读取文件正文，也不把未知根目录自动变为删除规则。
- dev.146 起 Windows/macOS 共用 Flutter `DeepSeekAgentWorkspace` 交互层，官方 DSH 是固定版本、可替换的执行内核；项目、会话、时间线、权限和停止使用 VibeKits 稳定模型，不读取或修改上游 Web DOM。ADB/串口/Git 等继续通过稳定 MCP 工具桥接入。
- Zed、Geany、OpenSSH 和 GitHub 文档只用于工作流与操作习惯研究。Git 执行采用官方 MinGit 二进制分发，按 GPL-2.0-only 及归档组件许可证履行随附义务，不复制修改其源码。
- SSH 交互终端、SFTP 和端口转发使用 `dartssh2`，终端渲染使用 `xterm`；主机密钥必须经用户确认或与已绑定指纹一致。转发连接和数据泵运行在后台 Isolate；不自行实现密码学。
- GitHub 网络诊断只读取 DNS/TLS/HTTPS/代理/hosts/SSH 状态，不移植 FastGithub 的 hosts、代理、证书或系统修改逻辑。
- 不直接嵌入 GPL/AGPL 工具源码；新增组件必须先记录版本、许可证、上游、产物方式和哈希。

## 当前供应链缺口

- macOS ONNX Runtime arm64/x64 原生库和桥接尚未固定版本与哈希，因此 macOS OCR 不得标记完成。
- macOS 自包含 Harness/Node、ADB、7-Zip 和 Git 已进入 dev.146 发布链；Developer ID 签名和 Rosetta App/工具门禁已通过，新 payload 的 Apple 公证、精确候选 Harness/LAN MCP、UI 人工巡检和 Windows 构建机回归完成前，仍不能当成正式外发包。
- 正式安装器还需汇总完整 NOTICE/SBOM，并在安装目录提供所有必须随附的许可证文本。
- HEIF/AVIF/JXL/RAW 解码器尚未选型；许可证和二进制供应链评审前不得只注册扩展名假装支持。
