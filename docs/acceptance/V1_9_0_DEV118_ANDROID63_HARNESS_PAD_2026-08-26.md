# v1.9.0-dev.118 Android 63 真机、Pad 触控与 Harness 全接口验收

## 验收结论

本轮完成 Android ARM64 Release 构建并安装到 `192.168.3.63:5555`。Pad 五个一级入口、1920×2560 连续双屏画布、局域网扫码输入 Key、开发工具触控布局和“一键交给 Harness”流程均已在真机操作。自动化共通过 118 项：Harness/接口/双屏 32 项、本地业务能力 65 项、主界面与文件路由 21 项。

“可调用”按真实平台边界验收：移动 Harness 现在获得全部 130 个公开可执行接口的 Schema；文件、计算、HTTP、SSH/SFTP、远程数据库等跨平台能力在 Android 直接执行，ADB host、串口、抓包、代理、虚拟机和 Git 等桌面能力返回结构化 `requiresDesktopNode`，不会伪装成 Android 已执行。当前版本尚未实现 Android 到已登记桌面节点的远程执行传输，因此这部分为“可发现、可规划、可形成交接任务”，不是“已在手机本地执行”。

## 构建与真机

- 设备：`huanglong`，Android 12，arm64，双显示器均为 1920×1280。
- 目标：`192.168.3.63:5555`。
- 包名：`com.vibekits.vibekits`。
- 安装版本：`versionName=1.9.0-dev.118`，`versionCode=2128`。
- APK：`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`。
- APK 大小：64,990,036 B。
- SHA-256：`3B78EA49EFD31790B6A409D50C33CD0ECAAB14354AB485FAC37074819F6F94B9`。
- Release 构建：通过；`adb install -r`：`Success`。
- 真冷启动：首轮 `MainActivity` 584 ms；最终覆盖安装后双屏入口调度 131 ms；启动后 PSS 约 75.9 MiB、RSS 约 214.7 MiB、Swap 0。
- 致命日志审计：未发现 `FATAL EXCEPTION`、`Fatal signal`、`ANR in`、`E/flutter` 或 `Unhandled Exception`。

## Harness 接口闭环

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| 定义接口 | 152 | `docs/37_HARNESS_CAPABILITY_CATALOG.md` |
| 当前公开可执行接口 | 130 | 运行时 `executableCatalog` 与能力 Markdown 一致 |
| 未公开接口 | 22 | 没有执行器或尚未达到公开条件，不注入模型 |
| 每个开发工具入口存在适配器 | 通过 | 合同测试遍历 `devToolRegistry` |
| 所有公开工具存在处理器 | 通过 | `capability_check.missingHandlers` 为空 |
| 移动端可见完整公开 Schema | 通过 | 移除移动端目录过滤；130 个接口均注入模型 |
| 桌面专属工具不在手机伪执行 | 通过 | ADB/串口断言 `requiresDesktopNode=true` |
| 移动本地工具保持本地执行 | 通过 | 文件 Diff 断言 `requiresDesktopNode=false` |
| 远程开发能力在 Pad 直接执行 | 通过 | SSH 与远程数据库查询断言 `requiresDesktopNode=false` |
| 工具真实调用与审计 | 通过 | 资源、SQLite、HTTP、计算器、SSH/SFTP mock session、OCR、远程 DB mock、Diff/Hash/重复扫描专项 |

本轮针对移动端增加统一平台门禁。Harness 调用桌面专属接口时得到 `available=false`、`executed=false`、`requiresDesktopNode=true`、原因和下一步动作；调用仍进入 Harness 工具记录，便于定位没有执行的原因。

## Pad 触控与少输入验证

| 场景 | 结果 |
| --- | --- |
| 五个底部入口 | 智能体、解压缩、系统清理、文档阅读、开发工具 5/5 可点击 |
| 连续双屏 | 单 Activity/单 Flutter 状态树；D2 上半屏、D0 下半屏 |
| 触控尺寸 | 底部导航 76 px；开发工具列表项至少 56 px；不依赖鼠标悬停 |
| 开发工具列表 | 280 px 触控侧栏，中文用途 + 标准英文缩写 |
| 桌面能力入口 | 说明页提供 56 px“一键让 Harness 连接桌面节点”和 52 px“复制任务” |
| 少输入 | 点一次即返回 Harness 并预填所选工具、节点检查、执行和日志要求，只需确认发送 |
| Key 输入 | 真机弹出二维码并提示手机与 Pad 在同一局域网；手机网页确认后写入安全存储 |
| 文件路由 | Widget 回归覆盖多文件、未知类型、ONNX、图片 OCR 自动选工具 |

## 自动测试

- Harness 能力、工具桥、Android 双屏合同：32/32 通过。
- 清理平台策略、清理决策、压缩、文档、文件类型、PP-OCRv6、音频分析、程序员计算器、系统资源、SQLite、Diff/Hash、微工具、局域网 Key：65/65 通过。
- 主界面、五个 Tab、拖入/系统传入文件自动路由、Harness/OCR 状态保持：21/21 通过。
- 合计：118/118 通过。

## 真机证据

证据目录：`build/acceptance/dev118-android63/`

- `d2-home.png` / `d0-home.png`：连续画布、Pad 导航和退出入口。
- `devtools-d2.png`：触控开发工具侧栏与计算器。
- `desktop-node-gate.png` / `desktop-node-gate-d0.png`：桌面能力的平台说明和一键交给 Harness。
- `harness-prefill-d2.png` / `harness-prefill-d0.png`：一键生成并预填任务。
- `qr-key-flow.png`：局域网扫码输入 DeepSeek 授权码。
- `archive-ui.xml`、`cleaner-ui.xml`、`documents-ui.xml`、`devtools-ui.xml`：五入口触控遍历结果。

## 未伪造的门禁与下一步

1. 当前 Windows 凭据管理器没有保存 `deepseek-api-key`，真实模型→ADB 自动用例明确返回 `HARNESS_ADB_NO_SAVED_KEY`。因此本报告不声称本轮取得了 DeepSeek 在线回答；扫码输入流程和缺 Key 边界已通过。
2. Android 到 Windows/macOS 节点的远程工具传输尚未实现。当前全部工具对 Harness 可发现，但桌面专属工具只形成明确节点任务，不能算远程执行闭环。
3. 远程数据库、真实 SSH 服务器、串口硬件、抓包驱动、代理订阅和虚拟机镜像需要对应外部目标；本轮验证接口、参数、处理器、平台门禁与审计，未把缺少外部环境的项目写成真机执行通过。
4. APK 为未签名商店发行版；正式分发仍需签名、渠道包和升级验证。
