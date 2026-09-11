# Harness 运行中消息与待执行队列设计

## 目标

Harness 推理、调用工具或执行长任务时，输入框仍然可用。新消息不能丢失，也不能在用户不知情时终止当前任务。每条消息必须明确处于当前任务补充、待执行或立即打断三种语义之一。

## 交互规则

- 空闲时点击发送：立即创建新回合。
- 忙碌时默认发送：加入当前任务，供智能体在下一个安全消息边界读取；界面显示“已补充当前任务”。
- 用户选择“排队下一条”：加入当前会话的待执行队列，当前回合结束后按顺序自动提交。
- 用户选择“立即打断”：先显示确认，确认后取消当前回合；收到终止确认后再提交新消息。
- 输入框上方显示紧凑的“待执行 N”入口，不长期占用会话正文空间。
- 展开后每项显示摘要、来源、创建时间和状态，并支持编辑、上移、下移、删除和立即执行。
- 鼠标悬停显示完整文本；删除待执行项不影响已经完成或正在运行的对话。

## 状态模型

每个会话独立保存队列，不允许跨项目误投：

```text
draft -> queued -> dispatching -> running -> completed
                 |              |          -> failed
                 |              -> cancelled
                 -> deleted
```

队列项至少包含：`id`、`sessionId`、`workspaceId`、`text`、`mode`、`source`、`createdAt`、`status`、`attempt`。`source` 区分本机用户、本 APP MCP、本机 MCP 和局域网 MCP；远程来源同时记录已批准的调用身份，但不得保存令牌。

## 调度约束

1. 以 Harness 原生会话事件作为忙闲事实源，不通过按钮文字或 DOM 外观猜测。
2. 当前回合完成、失败或取消并收到最终事件后，才允许调度下一项。
3. 正在等待工具审批时视为忙碌，不自动启动队列下一项。
4. 每个会话同一时刻最多一个 `dispatching/running` 项；应用重启后把遗留的 `dispatching` 恢复为 `queued`，避免消息丢失。
5. 提交使用幂等键 `sessionId:itemId`。未得到服务端接受确认不得从队列移除，重试不得产生重复回合。
6. 删除只允许作用于 `queued` 项；正在运行的项必须走取消流程。
7. 远程 Harness 调用仍需审批；批准后进入同一队列，不允许绕过本机调度器直接抢占。

## 智能体语义

- “补充当前任务”是 steering：智能体结合当前上下文处理，并可调整未完成计划。
- “排队下一条”是独立回合：不自动把它解释成当前任务的约束。
- 若自动分类置信度不足，默认排队，避免意外改变正在执行的设备、文件或网络操作。
- 涉及删除、安装、重启、发布或远程控制的消息不得由自动分类直接变成“立即打断”。

## 实现边界

- 队列状态由 VibeKits 持有并持久化；官方 DSH 页面只负责展示和提交，不能成为唯一数据源。
- Windows WebView2 与 macOS WKWebView 使用同一桥接事件：`turn.started`、`turn.completed`、`turn.failed`、`turn.cancelled`、`approval.waiting` 和 `message.accepted`。
- Android 原生 Harness 使用同一仓储和状态机，保持跨平台行为一致。
- 外部任务注入不得仅把文本写入输入框；必须调用队列 API 并等待 `message.accepted`。

## 与官方 Harness/DSH 的兼容原则

本功能是官方 Harness 上方的增量协调层，不替代或复制官方产品。项目、会话、消息历史、模型选择、权限审批、Skills、插件、MCP 和工具执行仍以官方 DSH 为事实源；VibeKits 只保存尚未被官方 Harness 接受的待执行消息及其调度状态。

1. 优先使用当前固定 DSH 版本已经公开的会话提交、取消和状态接口；不得修改官方会话数据文件或直接写入其数据库。
2. `turn.*`、`approval.waiting`、`message.accepted` 是 VibeKits 桥接层统一事件名，不代表 DSH 必然原生使用这些名称。适配器负责把当前 DSH 的真实事件映射成该契约。
3. 如果当前 DSH 没有公开某个事件，只允许通过现有 WebView 桥接观察稳定的官方状态；DOM 选择器只能作为带版本校验的兼容降级，不能成为持久队列的事实源。
4. 若 DSH 版本或页面结构不匹配，关闭自动调度并保留队列，提示“等待 Harness 兼容”，不得猜测忙闲后强行发送。
5. VibeKits 不覆盖官方输入组件。空闲提交应调用官方原生发送动作；忙碌时用户仍在官方编辑器输入，VibeKits 只增加发送方式选择和待执行队列入口。
6. 已被 DSH 接受的消息立即从 VibeKits 待执行存储转交给官方会话历史，之后不在两处保存正文，避免双份历史和状态漂移。
7. Release 固定并验证一个 DSH 版本。升级 DSH 时先跑兼容契约测试；测试失败则构建失败，不能把未经验证的新版本交给用户。
8. Windows、macOS 共用同一 Flutter 队列仓储和桥接协议，只分别适配 WebView2/WKWebView；不能形成两套行为不同的 Harness。

### 当前版本落地顺序

1. 先给现有 `_injectPrompt` 增加“已接受”反馈，但保持原来的外部任务填入输入框行为可用。
2. 再接入官方回合忙闲和取消能力；只有真实状态经过固定版本验收后才开启自动发送。
3. 最后增加紧凑的待执行入口、编辑/排序/删除 UI。任一步失败都回退到原 Harness 行为，不阻断对话、Skills 或 MCP。

## 验收流程

1. 运行一个持续至少 60 秒的工具任务，期间连续发送“补充当前任务”和两个“排队下一条”；输入始终可编辑，当前任务不中断。
2. 删除第二个待执行项，确认它没有出现在会话历史，也没有调用工具。
3. 当前任务完成后，第一项自动且只执行一次。
4. 在 `dispatching` 时强制关闭并重启 APP，确认队列恢复且不产生重复回合。
5. 对等待审批、失败、取消和断网恢复分别测试，确认不会并发调度或丢消息。
6. 从局域网 MCP 提交任务，确认显示来源、先审批、批准后进入同一队列。
7. Windows、macOS 和 Android 使用相同用例通过，并保留可审计的状态转换记录。

## Windows 路径兼容性审查（2026-09-11）

### 审查结论

当前代码已经大量使用 `Platform.pathSeparator` 和 `package:path`，Release 运行时也优先从可执行文件旁的 `tools/harness` 定位，因此不依赖开发机 Node/npm，基础方向正确。但路径事实源尚未完全统一：应用数据布局、官方 Harness Home、共享 Skills、MCP 连接文件、调试临时目录和开发态运行时各自有回退规则。若不收口，Windows 上会出现系统盘重新膨胀、同一用户产生两套 Skills、从快捷方式启动时找错资源、空格/中文路径失效以及清理器误删运行中目录的问题。

### 已确认的现状

| 路径类别 | 当前解析方式 | 证据位置 | 结论 |
| --- | --- | --- | --- |
| 官方 Harness Home | Windows 默认 `%LOCALAPPDATA%\\Vibekits\\Harness` | `lib/features/dev_tools/domain/deepseek_harness_service.dart` 的 `officialHarnessHomeDirectory` | 会继续占用 C 盘；没有读取 VibeKits 已解析的数据盘布局 |
| 全局 Skills | 绝对 `CODEX_HOME` 优先，否则 `%USERPROFILE%\\.codex` | 同文件 `sharedAgentHomeDirectory` | 当前设置 `CODEX_HOME=D:\\Codex\\home` 时可正确落 D 盘；未设置时回到 C 盘 |
| DSH Skills 扫描 | 启动进程设置 `DSH_AGENTS_HOME=<sharedAgentHome>` | `_nodeAppLifetimeEnvironment` | 与全局 Skills 设计一致，但必须验证子进程实际继承值 |
| Harness 日志/截图/临时目录 | `HarnessWebRequest.debugDirectory`；为空时由平台存储布局决定，子进程覆盖 `TEMP/TMP/TMPDIR` | `startWebAgent`、`prepareDebugDirectory`、`PlatformStorageLayout` | 方向正确；必须保证默认值在可写数据盘，并避免回落系统 Temp |
| 应用设置、模型、下载、缓存 | Windows 优先 `LOCALAPPDATA`，调试目录优先可执行文件旁 `tmp` | `lib/app/platform_storage_layout.dart` | 模型和缓存可能持续写 C 盘；Release 若装在只读目录，调试目录会回退缓存目录 |
| MCP 连接文件 | Windows 默认 `%LOCALAPPDATA%\\Vibekits\\Mcp\\tool-bridge.json` | `native/harness/vibekits-mcp-server.mjs`、`vibekits-codex-mcp.mjs` | 路径稳定但仍在 C 盘；APP 与 Node 必须使用同一显式连接文件事实源 |
| Harness Release 运行时 | 优先 `<exe>\\tools\\harness`，开发态再看 `<cwd>\\native\\harness\\windows\\runtime` | `_resolveBundledRuntime` | Release 可自包含；开发态依赖当前工作目录，快捷方式/测试启动可能找错 |
| Node 编译缓存 | 优先使用 Release 内置 portable seed，否则写 Harness Home | `_prepareNodeCompileCache` | 内置时不会复制大量小文件；seed 缺失会再次写 C 盘默认 Harness Home |
| 压测报告 | 强制 Windows 目录以 `D:\\` 开头 | `native/harness/vibekits-android-stress-mcp.mjs` | 符合本项目数据盘要求，但属于产品特例，跨机器无 D 盘时必须显式报错而非回退 C 盘 |

### 必须在编码阶段修正的路径架构

1. 以 `PlatformStorageLayout` 作为 APP 数据、缓存、下载、Harness Home、调试和 MCP 运行态文件的唯一入口，禁止各模块再次读取 `LOCALAPPDATA` 或自行拼默认目录。
2. 增加明确的数据根配置（建议 `VIBEKITS_DATA_HOME`），优先级为：用户设置的绝对路径 → 安装时登记的数据盘路径 → 平台原生目录。`CODEX_HOME` 只管理共享智能体/Skills，不能兼任全部 APP 数据目录。
3. Windows 本项目默认建议：
   - `D:\\VibekitsData\\Harness`：DSH Home、会话和配置；
   - `D:\\Codex\\home\\skills`：共享全局 Skills；
   - `D:\\VibekitsData\\cache`：可重建缓存；
   - `D:\\VibekitsData\\debug`：日志、截图、压测证据和临时文件；
   - `<安装目录>\\tools\\harness`：只读、自包含 Release 运行时。
4. APP 启动时解析一次规范化绝对路径并把结果显式传给所有 Dart/Node 子进程。禁止 APP 和 MCP server 分别推导 `tool-bridge.json`；连接文件路径必须通过环境变量显式传递。
5. `Directory.current` 只能用于开发候选路径，不能参与 Release 数据或资源定位。Release 必须从 `Platform.resolvedExecutable` 推导安装资源；开发模式必须有明确标志和路径存在性校验。
6. 所有路径进入 shell 前使用参数数组而非字符串命令；支持盘符大小写、空格、中文、`#`、`&`、括号及超过 260 字符的路径。不得手工去引号后再拼接命令。
7. 比较路径时使用 Windows 不区分大小写的规范化结果；解析 junction/symlink 后再执行删除、安全边界和“是否在工作区内”判断，防止路径逃逸或误拒绝。
8. 网络 UNC 路径可作为只读输入和工作区，但 Harness Home、SQLite、Node 编译缓存、MCP token/连接文件不得默认放 UNC；需要本地可写数据根。
9. 启动前对工作区、Harness Home、Skills、debug、cache、MCP runtime 分别执行写入探针并显示最终路径。任何持久数据回退到系统 Temp 都必须作为显式错误/降级状态展示，不能静默继续。
10. 清理器通过路径类别和活跃租约清理：只清 cache/temp/过期日志；不得扫描 Skills、会话、凭据、当前队列数据库、运行中 DSH Home 或 Release runtime。

### 与消息队列的路径关系

- 待执行队列数据库属于持久应用数据，放在数据根的 `Harness/queue`，不能放 `TEMP`、WebView LocalStorage 或官方 DSH 的内部数据库。
- 每条队列记录保存规范化的 `workspaceId/sessionId`，不把工作区绝对路径当唯一身份；路径移动后由官方 Harness 会话映射恢复。
- 消息正文落盘采用原子写入/事务，Windows Defender 占用或文件锁时退避重试；失败时保留内存队列并显示“尚未持久化”，禁止假装保存成功。
- APP 多开时使用单写者锁或进程间队列服务，避免两个窗口同时调度一条消息。
- 队列文件不得包含 MCP token、API Key、SSH 密码或串口敏感输出；远程来源仅保存审批记录 ID。

### Windows 专项验收矩阵

1. `CODEX_HOME=D:\\Codex\\home`：Harness 能列出内置 `kemi-s1-hardware-debug`，C 盘 `.codex/skills` 不产生第二份。
2. 未设置 `CODEX_HOME`：明确显示最终 Skills 路径；安装内置技能成功且不覆盖用户已有同名自定义内容时必须有版本/所有权策略。
3. APP 安装到 `C:\\Program Files\\Vibekits`：运行时只读，所有可写数据仍进入配置的数据盘。
4. 工作区分别使用 `D:\\项目 空格\\测试`、中文文件名、`#&()` 和 260 字符以上路径，启动、MCP、Git、ADB 文件传输及队列恢复全部通过。
5. 从开始菜单、桌面快捷方式、任意当前目录和命令行启动，均定位同一个 Release runtime，不读取仓库 `native/harness`。
6. C 盘低于 1 GB：只要数据盘可写，Harness 能启动且不会向 C 盘写入大型模型、Node 缓存、日志或压测文件；平台必须保留的微小系统元数据单独列明。
7. D 盘不存在、盘符变化、目录只读：启动前给出可操作错误并允许重新选择数据根，不静默转回 C 盘造成再次爆盘。
8. Junction 指向工作区外、UNC、盘符大小写变化和尾随点/空格：安全校验不被绕过，清理器不误删。
9. Harness 正在运行时执行清理扫描：活跃 Home、当前日志、队列数据库和 MCP 连接文件全部受保护。
10. 升级和卸载：Release runtime 可替换，用户会话/Skills/队列不丢失；卸载是否删除数据必须单独确认。

### 开发完成定义

其他智能体实现时必须同时提交：路径解析单元测试、Windows 真机路径矩阵结果、消息队列状态机测试、官方 DSH 固定版本兼容测试、低磁盘测试及 Release 自包含验证报告。仅在开发目录可运行、仅检查文件存在或仅展示队列 UI，均不算完成。
