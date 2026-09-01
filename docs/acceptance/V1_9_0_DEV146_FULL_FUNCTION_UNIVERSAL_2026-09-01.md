# VibeKits 1.9.0-dev.146 全功能 Universal 发布验收

日期：2026-09-01～2026-09-02
目标：把当天用户逐项提出的 Harness、工具、跨平台和发布要求合并为一份可核对门禁。任何一项标记为阻塞时，不得替换 `bin/Vibekits.app`，也不得写成正式完成。

## 1. 当日需求逐项矩阵

| 需求 | 代码/交互验收 | 自动证据 | 发布门禁 |
|---|---|---|---|
| 项目与会话关系 | 项目可添加、改名、折叠；会话可立即拖动或从锚定信息卡移动，移动前重绑工作区权限 | `deepseek_harness_test.dart` 的添加/折叠/拖动/权限用例 | Release 人工复核源/目标路径 |
| 会话永久删除 | 删除聊天、推理、计划、工具时间线、结果和草稿；不删除项目文件；运行中先停止 | `harness_session_store_test.dart` 与 Harness Widget 删除用例 | 取消和确认各做一轮 |
| 项目/会话视觉层级 | 项目字体大于会话；仅选中行显示 `…`，未选中的运行会话显示转圈 | Harness Widget 与截图合同 | 浅色/深色、窄/宽窗口复核 |
| 会话独立草稿与并行 | A 输入 111、B 输入 222，切回保持；一个任务运行不锁死其他会话输入和浏览 | 独立草稿、双会话并行、后台结果回原会话用例 | Release 两会话真实任务 |
| 推理和工具过程 | 展示可核对的理解、规划、工具目标、结果摘要、继续分析和终态；不展示私有逐字思维链 | 生命周期、工具完成回调、时间线合同 | 运行中可随时停止且释放外部资源 |
| 执行时间线可读 | 默认折叠；展开后按步骤分组，长 JSON 为摘要/可展开证据，不铺满页面 | 48 步时间线回归 | 深色主题人工可读性 |
| Harness 状态 | 规划/推理/工具/工具后分析均为 BUSY，真正结束才 READY；按真实项目上报 | work status、publisher、生命周期测试 | RustDesk 远端绿灯→蓝灯三阶段 |
| ADB 内置与调用 | Release 固定 App 私有 ADB；缺失直接构建失败；多属性 getprop 安全拆分 | ADB 工作区/桥接/语义测试 | 精确候选 App 对真实设备只读调用 |
| MCP 首次授权与持续授权 | 首次明确风险和范围；持久授权后不逐次确认，只显示至少 3 秒活动卡；可强制关闭/断开/撤销/拉黑/全局关闭 | LMCP 权限、审计与调用状态测试 | 真实提供方 UI 和调用审计 |
| MCP 指挥官 | `app → local → lan`；同能力多节点按空闲槽、租约和全局评分选择；失败/低完成率降权 | scheduler、reputation、directory 测试 | 目标 LAN 节点真实目录和调用结果 |
| 先启动/后启动发现 | 提供方先运行，VibeKits 后启动仍在公告周期内发现；多 App 共享 UDP 47831 | LAN discovery 跨实例和晚启动测试 | Release 晚启动后发现既有目标节点 |
| Windows/macOS 单 UI | 两端统一使用 `DeepSeekAgentWorkspace`；平台层只处理运行时、凭据和 IPC | analyze + 共享 Harness 合同 | Windows 正式 Release 仍需 Windows 构建机实测 |
| macOS 12+ Intel 全功能 | App、Node/DSH、ADB、7-Zip、Git 和原生依赖均满足架构/最低系统门禁；Rosetta 启动后实际运行 Harness/工具 | `verify_macos_release_compat.sh` | Universal、Developer ID、公证、Gatekeeper 全通过 |
| 正式产物和云端备份 | 只在全部门禁绿后写入 `bin`；版本、SHA、notary submission、commit 可追溯 | `git diff --check`、最终测试报告 | push 后远端 SHA 等于本地 HEAD |

## 2. 已实现的跨平台 Harness 架构

`LocalModelsTab` 不再根据 `Platform.isWindows` 选择另一套官方 WebView 页面。Windows 与 macOS 共用 `DeepSeekAgentWorkspace`、`VibekitsHarnessToolBridge`、项目/会话存储和生命周期模型；`DeepSeekHarnessService` 只保留 Node/DSH 路径、进程终止和平台凭据等运行时差异。官方 Harness 升级只能替换固定 Engine Adapter/runtime，不允许再次复制一套 UI。

## 3. macOS 12 Universal 供应链门禁

- 7-Zip macOS 固定为官方 25.01，源码资产 SHA-256：`26aa75bc262bb10bf0805617b95569c3035c2c590a99f7db55c7e9607b2685e0`。
- 官方 `7zz` 同时包含 `x86_64`、`arm64`，两个切片 `minos=12.0`。26.02 官方二进制的最低系统版本过高，禁止进入 dev.146。
- Git macOS 必须由固定上游源码构建 Universal 运行时并随 App 打包；禁止把 `/usr/bin/git` 回退当作“自包含已完成”。
- Release 兼容脚本必须逐项检查 App、ADB、Node、7-Zip、Git、Flutter frameworks 和 Harness 原生模块，任何单架构或最低版本越界均失败。

## 4. 最终证据（完成后填写）

- Flutter analyze：2026-09-02 最终源码执行，`No issues found`。
- 完整串行 Flutter tests：最终源码 653 passed、15 skipped、0 failed。15 项均为需要显式外部环境或授权的门控测试：QEMU/Mihomo live、真实系统盘、真实 ADB、一次性 KEMI 文件发送、Windows 注册表、真实模型联网、真实 LMCP 和 UI 截图等；跳过不计作通过。真实 LMCP 项另带目标参数单独执行 1/1 通过。
- Universal Release：干净 `flutter clean → pub get --offline → flutter build macos --release --no-pub` 成功；App 实际占用约 714 MiB。`verify_macos_release_compat.sh` 扫描 App、frameworks、ADB、Node/DSH、7-Zip、Git 和 Harness 原生模块全部通过，App 最低版本固定为 macOS 12.0。
- GitHub `macOS Release` 门禁明确标记为 macOS 12+，并监听 `third_party/**` 与 `tool/**`；运行时或验证脚本单独变化也必须重新构建、验证 Universal 双架构并生成校验和，避免漏验。
- Rosetta：Developer ID 精确候选以 `arch -x86_64` 启动，`vmmap` 报告 `Code Type: X86-64 (translated)`；同一包内 Node 22.19.0、DSH 0.1.1-rc.2、ADB 37.0.0、7-Zip 25.01、Git 2.53.0 的 Intel 切片均实际启动成功，ADB 明确报告 `Darwin x86_64`。Intel/Rosetta Node 固定带 `--jitless`，真实执行 DSH JS 入口而非只跑 `node --version`；不授予 `allow-unsigned-executable-memory`。
- Developer ID：33 个可执行/原生 Mach-O 逐项验证 Authority、Team ID 与 Hardened Runtime，并通过 `codesign --verify --deep --strict`；Authority=`Developer ID Application: zhen ji (26T5WV4GLP)`、TeamIdentifier=`26T5WV4GLP`、Apple timestamp 均已取得；Node JIT/DSH 启动复验通过。
- Apple Notarization / Gatekeeper：`KEMI_NOTARY` 凭据已只读验证可访问 Apple；新 dev.146 payload 尚未提交，不能复用 dev.145 票据，也不能提前标记已公证。
- 目标 LAN 基准节点：VibeKits 生产 LMCP 客户端在提供方先启动、候选后启动的条件下发现 2.4.1/revision 9，完成 TLS 指纹固定、目录摘要校验并得到 `callable=true`。真实调用 `kemi.benchmark.last_result` 返回 `final=true`、`state=succeeded`、`verification=verified`、评分 99.51107080350508、等级 S 和匹配的报告 SHA-256；`response_identity_mismatch` 与 `AUTH_SCOPE_REQUIRED` 均未复现。可重复门禁为 `lmcp_readonly_live_test.dart`，执行 1/1 通过。模型驱动 Harness 仍需用户明确同意把实时 LAN 实例/目录信息发送给已配置的 DeepSeek 服务；生产客户端直调通过不冒充模型驱动验收。
- UI 人工巡检：自动辅助功能巡检被 macOS 锁屏阻止；需用户解锁后完成浅/深色、项目/会话菜单、独立输入、并行切换、时间线和永久删除的非破坏性检查。
- Windows：共享源码入口已完成；本机没有 Windows 构建环境，正式 Windows Release/真机结果必须由 Windows 构建任务补证，未补证前保持为门禁项。
- Git commit / GitHub SHA：待全部门禁通过后填写。

## 5. 本轮发现并阻止进入发布的真实问题

1. `pub get` 的构建环境曾把 lockfile registry URL 机械改为镜像地址；已恢复 `pub.dev`，只保留有意的三项本地审计包 override 和 `jni_flutter` 求解升级。
2. Git 上游用 hardlink 复用命令入口；逐文件签名会让同 inode 的别名签名失效。准备脚本改为相对 symlink，保留 54 MiB 自包含运行时并使全部入口继承同一已签目标。
3. ad-hoc 签名没有 Team ID，若把整个 App 都强制 Hardened Runtime 会触发 library validation。仅本机联调链使用独立 Node ad-hoc JIT entitlement；正式 Developer ID 链仍保持全组件 Hardened Runtime、同 Team ID 和时间戳。
4. LMCP 标准工程信封使用 `toolName`，旧 VibeKits 客户端却只读取 `tool`，导致 62 节点目录可见但结果身份拒绝。客户端现把 `tool` 仅作为旧别名，收集顶层和 `structuredContent` 的全部 `instanceId/toolName|tool/catalogRevision`，缺失或任何冲突都拒绝，不能用优先级覆盖攻击值。
5. 第一版 Intel 门禁只执行 `node --version`，漏掉 Rosetta 中 DSH 初始化 V8 baseline compiler 时的可执行内存失败。正式门禁现必须执行真实 DSH JS 入口；x86_64 运行时使用 `--jitless`，保持最小 `allow-jit`，拒绝以更宽的未签名可执行内存权限掩盖问题。
6. 首轮云端 `c476e4c` 在干净 checkout 的 Release 打包阶段失败：本机生成并忽略的 Harness、7-Zip、Git macOS runtime 不存在于 Git，旧工作流却直接构建。工作流现先按准备脚本和固定上游校验和生成/恢复缓存，逐项验证完整性，再把 runner 的官方 ADB 显式传给打包脚本；冷缓存超时提高到 90 分钟。第二轮又暴露 npm 会按构建主机架构选择可选原生包；准备脚本现不论运行在 Intel 或 Apple Silicon 都显式物化 arm64/x64 的 Sharp、libvips、Koffi 和 ripgrep。临时冷生成验证两套包和 Universal Node 完整；新云端 run 未通过前，本项仍保持阻塞。
7. 拆分门禁确认 Harness 冷生成成功，而 7-Zip 下载/准备步骤在云端失败。25.01 Universal `7zz` 及上游 License/readme/History 总计约 5.6 MiB，现作为固定、可审计的 Release 输入纳入 Git；准备脚本及上游压缩包 SHA-256 仍保留用于显式升级，构建不再依赖 GitHub runner 临时下载该二进制。兼容验证仍会独立检查两个切片和 `minos=12.0`，不能靠跳过下载绕过架构门禁。
8. 云端完整日志确认下一处失败不是编译器：Xcode 在最终签名时把 `Contents/MacOS/tools/adb/package.xml` 判定为未签名 code object。ADB 可执行文件继续固定在 `Contents/MacOS/tools/adb/adb`，NOTICE/source.properties/package.xml 改放 `Contents/Resources/tools/adb`；兼容门禁同时禁止在 ADB 可执行目录混入任何非 `adb` 文件，避免不同 Xcode 版本出现签名结果分叉。
9. 云端 App 已成功构建后，兼容脚本误把签名前官方 `7zz` SHA-256 用于比较签名后的 Mach-O；ad-hoc/Developer ID 签名会合法改变二进制字节，因此产生假失败。固定 SHA 现于复制和签名前验证 Git 输入；签名后的 App 继续独立验证 25.01 版本、许可证、双架构、两个切片 `minos=12.0` 和代码签名，既不误报，也不放弃供应链校验。
10. 官方 25.01 信息首行实际是 `7-Zip (z) 25.01 (...)`，旧版本断言错误地假定名称与版本连续。准备和兼容脚本现用锚定表达式同时接受官方可选产品标记，但仍严格固定版本 25.01，避免把显示格式差异误判为版本错误。
11. 本机 ADB 路径是指向另一套 SDK 的符号链接；若先解析链接再找 NOTICE/source.properties，会丢失链接所在官方 Platform-Tools 目录的元数据。打包现优先从用户配置路径所在目录取元数据，缺失时再回退真实二进制目录，并把 NOTICE/source.properties 设为强制门禁；既支持链接部署，也不允许只带裸二进制冒充完整官方运行时。

在本节剩余门禁全部变绿前，`bin/Vibekits.app` 继续保留 dev.145 已公证回退基线。
