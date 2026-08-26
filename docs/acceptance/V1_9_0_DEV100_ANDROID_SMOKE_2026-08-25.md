# v1.9.0-dev.100 Android 真机全入口冒烟报告

## 验收环境

- 日期：2026-08-25
- 设备：`huanglong`，ADB `192.168.3.62:5555`
- 布局：1920×2560 连续双屏画布
- APK：`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
- 版本：`versionName=1.9.0-dev.100`，`versionCode=2110`
- SHA-256：`2AB261FFFFCBB4E631363CA12B9FE7A86C2E55020AFB20356EBED9D47E38F96A`

## 结论

- 本轮真机实际执行的入口、扫描、采样、二维码监听和退出动作均未产生致命错误。
- 真机日志审计：`FATAL EXCEPTION`、`Fatal signal`、`E/flutter`、未处理异常和 VibeKits ANR 均为 0。
- Android 关键回归 `27/27` 通过；全工具域与 Harness 合同回归 `84/84` 通过；合计 `111/111` 通过。
- 首轮回归发现二维码按钮改名后旧测试仍断言“确认并发送”；已同步为“确认授权并发送到 Pad”，复跑归零。
- 本报告不把桌面节点门禁页、模拟处理器或仅有 UI 的入口冒充 Android 真机端到端能力。
- 针对“缺少用户真机文件”的问题，本轮由验收程序自行生成 13 个标准样本并推送到 `/sdcard/Download/VibekitsAcceptance/`，不再把常规测试文件交给用户准备。

## A. 本轮真机实际执行

| ID | 功能 | 真机动作 | 结果 | 证据或观测 |
|---|---|---|---|---|
| A-01 | APK 安装与版本 | 覆盖安装 arm64 Release，读取 PackageManager | 通过 | `1.9.0-dev.100 / 2110` |
| A-02 | 双屏启动 | 强制停止后从 Launcher 启动 | 通过 | MainActivity 前台，1920×2560 连续画布出现 |
| A-03 | 智能体（Harness） | 打开默认工作区 | 通过 | 显示 `Harness 就绪`，未启动 Windows DSH |
| A-04 | 局域网扫码 Key | 点击“扫码输入 Key” | 通过 | 提示先确认手机与 Pad 同一局域网；一次性 HTTP 接收器监听 `0.0.0.0:43453` |
| A-05 | OCR 页面 | 切换“截图识别（OCR）” | 通过 | PP-OCRv6 状态“已安装”，显示“本机 CPU·不上传” |
| A-06 | 解压缩 | 点击底部“解压缩” | 通过 | “打开压缩包/创建压缩包”立即显示，未闪退 |
| A-07 | Android 安全清理 | 点击清理入口并执行“扫描本应用缓存” | 通过 | `扫描完成：0 项；无法读取 0 个位置`，仅访问 VibeKits 私有 cache/tmp |
| A-08 | 文档阅读 | 点击底部“文档阅读” | 通过 | 查看器、最近记录、文件信息和关闭语义正常显示 |
| A-09 | 开发工具 | 点击底部“开发工具” | 通过 | 工具列表与程序员计算器立即显示 |
| A-10 | 资源诊断 | 点击“资源诊断（CPU/GPU）”并采样本机 | 通过 | CPU 17.1%、8 核、内存 40.5%、可用 3.3/5.5GB、磁盘 64% 已用 |
| A-11 | 桌面能力安全门禁 | 在 Android 点击桌面运行时类工具 | 通过边界 | APP 进程存活、无致命日志；Android 不启动 Windows/macOS 二进制 |
| A-12 | 双屏退出 | 点击 APP 顶部退出按钮 | 通过 | VibeKits Activity 从两个 Display 消失；Android 保留的 sleeping 缓存进程无 Activity、无任务 |
| A-13 | 重新启动 | 退出后再次从 Launcher 启动 | 通过 | APP 恢复到 Harness，供继续人工测试 |
| A-14 | 崩溃/ANR 审计 | 检查本轮 logcat 与 ActivityManager | 通过 | 致命行 0、ANR 0，测试结束前进程正常 |
| A-15 | Markdown 实文件 | 选择生成的 `sample.md` | 通过 | 默认直接渲染预览；中文、表格、代码块均可见；具有预览/源码/编辑/关闭操作 |
| A-16 | BIN 实文件 | 选择 1024 B 的递增字节 `sample.bin` | 通过 | 类型识别为“二进制”，按 16 字节显示地址、HEX 和 ASCII，内容从 `00..FF` 正确重复 |
| A-17 | ZIP 实文件 | 选择生成的 `sample.zip` | 通过 | 显示 2 项/189 B，列出 `archive-note.txt` 与 `sample.json`，解压操作可用 |
| A-18 | OCR 实图片 | 选择标准登机牌 `ocr-sample.png` | 通过 | PP-OCRv6_tiny/ONNX Runtime CPU 真机识别 31 行，5345 ms；包含登机牌、BOARDING PASS、航班、座位号等文字 |
| A-19 | WAV 实音频 | 选择 `audio-sample.wav` | 通过 | 识别 WAV 16000 Hz/1 ch/16 bit、4358370 帧；生成波形、频谱、播放及质量报告 |
| A-20 | 音频谐波/杂讯 | 对同一 WAV 执行质量分析 | 通过 | 主频 132.8 Hz、THD 21.469%、THD+N 228.435%、SNR -7.1 dB、噪声底 -97.4 dBFS，并列出 2~5 次谐波 |

## B. 自动回归清单

| 类别 | 覆盖内容 | 结果 |
|---|---|---|
| Android 双屏 | 默认双屏、单屏入口、真实外接屏枚举、唯一状态树、图表说明、连续画布/统一退出合同 | 通过 |
| 局域网 Key | 二维码不含 Key、一次接收、错误令牌拒绝、网页粘贴与新按钮文案 | 通过 |
| PP-OCRv6 | 字典、CTC 解码、官方图片端到端 ONNX OCR | 通过 |
| 资源诊断 | Android `/proc` 解析、Windows 只读探针、退出终止探针 | 通过 |
| 清理 | 白名单、风险选择、半年未用建议、分批渲染、汇总、持久化、软件缓存/卸载入口、多磁盘 | 通过 |
| 程序员计算器 | 混合进制、位宽、有符号/无符号、移位/异或/取反/除法及错误输入 | 通过 |
| 30 个微工具 | 注册、代表输入输出、Harness 自动发现、执行与审计记录 | 通过 |
| 压缩 | ZIP/TAR/TAR.GZ、格式识别、路径穿越、展开限制、冲突策略、取消与后台 Isolate | 通过 |
| 文档 | 最近记录恢复/清空、支持格式清单、关闭文档 | 通过 |
| API | 本地 HTTP POST、Header、UTF-8 Body、状态与响应 | 通过 |
| 数据库 | SQLite 分页/损坏控制、PostgreSQL/MySQL/SQL Server 资料兼容 | 通过 |
| 文件 | Diff、MD5/SHA 系列、后台哈希进度和取消 | 通过 |
| 音频 | PCM/WAV、波形质量、削波、谐波/噪声热点、Harness 调用 | 通过 |
| SSH/SFTP | 参数安全、主机密钥、SFTP、端口转发、记录不含密码 | 通过 |
| Harness 工具桥 | 每个独立入口有适配器、能力自检、ADB/SQLite/HTTP/SSH/SFTP/OCR/Diff/Hash 审计闭环 | 通过 |

## C. Android 上按设计连接桌面节点的能力

这些能力没有在 Android 内启动桌面二进制，因此不能标记为“Android 本地运行通过”。当前正确行为是显示桌面节点说明，由 Harness 连接已登记的 Vibekits 桌面节点调用。

| 能力 | Android 当前状态 |
|---|---|
| 网络代理（Clash Verge/Mihomo） | 桌面节点门禁 |
| 轻量虚拟机（QEMU） | 桌面节点门禁 |
| 远程连接（SSH/SFTP）桌面运行时 | 桌面节点门禁 |
| 串口调试（Serial） | 桌面节点门禁 |
| 安卓调试（ADB Host） | 桌面节点门禁，Android 设备自身不能充当已打包的桌面 ADB Host |
| 版本控制（Git） | 桌面节点门禁 |
| 网络诊断（GitHub） | 桌面节点门禁 |

## D. 标准文件驱动验收

生成目录：`build/acceptance/dev100/fixtures/`；真机目录：`/sdcard/Download/VibekitsAcceptance/`。

| 类别 | 标准样本 |
|---|---|
| 文档/源码 | `sample.md`、`sample.json`、`sample.dart` |
| 二进制 | `sample.bin`（确定性 `00..FF` 字节序列） |
| 压缩 | `sample.zip`、`sample.tar`、`archive-note.txt` |
| 数据库 | `sample.sqlite`（`tools` 表及 3 行测试数据） |
| OCR | `ocr-sample.png` |
| 音频 | `audio-sample.wav`、`audio-sample.pcm` |
| Diff | `left.txt`、`right.txt` |

已在 dev.100 真机以实际文件完成：Markdown、BIN、ZIP、OCR、WAV/PCM 分析。继续执行 Diff 时设备 `192.168.3.62` 曾从 ADB `device` 变为 `offline`；重启项目自带 ADB 服务后已恢复并重新覆盖安装 dev.100。随后外接上屏被正在运行的 KEMI 远程服务占用，为避免中断用户现有远程服务，没有强停该应用。因此 SQLite、Diff、Hash 的本轮真机点击不伪报通过，保留标准文件待上屏可用时复验。

剩余三项对应的精确服务回归已补跑：Diff `3/3`、SQLite/Hash `9/9`，全部通过；这证明算法和后台 Isolate 合同正常，但不替代上述真机界面点击状态。

## E. 仍需外部凭据或在线目标的端到端项

| 功能 | 本轮状态 | 完整通过条件 |
|---|---|---|
| DeepSeek 真实回答 | 未执行 | 用户通过二维码写入有效 Key 后发起真实问题并收到回答 |
| 真实远程数据库 | 合同回归通过 | 提供可用测试数据库地址和只读账号 |
| 真实 SSH/SFTP/串口/ADB/Git | 桌面节点合同通过 | 连接已登记且在线的桌面节点及对应目标设备 |

## 证据目录

- `build/acceptance/dev100/home-upper.png`
- `build/acceptance/dev100/archive.png`
- `build/acceptance/dev100/cleaner.png`
- `build/acceptance/dev100/cleaner-scan.png`
- `build/acceptance/dev100/documents.png`
- `build/acceptance/dev100/devtools.png`
- `build/acceptance/dev100/ocr.png`
- `build/acceptance/dev100/resources-ui.xml`
- `build/acceptance/dev100/document-md-ui.xml`
- `build/acceptance/dev100/document-bin-ui.xml`
- `build/acceptance/dev100/archive-zip-ui.xml`
- `build/acceptance/dev100/ocr-selected-ui.xml`
- `build/acceptance/dev100/audio-result-ui.xml`
- `build/acceptance/dev100/audio-analyzed.png`
