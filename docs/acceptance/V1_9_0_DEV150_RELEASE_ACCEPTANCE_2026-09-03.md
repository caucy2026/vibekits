# VibeKits 1.9.0-dev.150 全功能发布验收

日期：2026-09-03  
候选：`1.9.0-dev.150+2150`  
状态：正式发布完成；Universal、双平台 CI、Developer ID、Apple 公证、Gatekeeper、Intel/Rosetta 和最终 Harness 桥门禁全部通过，精确产物已放入 `bin`。

## 1. 兼容边界

- 官方 Harness/DSH 是可升级执行内核。工作区、会话、对话、模型、权限、Skills、设置和插件清单继续由官方状态管理。
- VibeKits 增强通过 `tool/patch_harness_runtime.mjs` 的固定、幂等、可失败关闭补丁以及 macOS/Windows 共用 Host 消息合同接入；不得直接维护一份分叉 UI。
- macOS 使用 WKWebView，Windows 使用 WebView2。两端统一支持 `window.VibekitsHost` 与 `window.chrome.webview`，新增行为必须同时有源码合同和打包门禁。
- macOS 正式支持 12.0+、arm64 与 x86_64；所有嵌入 Mach-O、ADB、Node/DSH、7-Zip 和 Git 都必须满足双架构与签名门禁。

## 2. 真实 UI 验收

与 dev.150 应用代码一致的 Developer ID 签名候选已用原生鼠标事件逐项操作；其后提交仅涉及 CI、测试脚本和 Windows CMake 兼容，不改变下列界面行为：

| 功能 | 结果 | 证据 |
|---|---|---|
| 打开官方左侧栏 | 通过 | `/private/tmp/dev150-sidebar-open.png` |
| 会话菜单 | 通过；含重命名、分叉、归档、删除 | `/private/tmp/dev150-session-menu.png` |
| 永久删除确认与取消 | 通过；取消后原会话仍存在且无点击穿透 | `/private/tmp/dev150-delete-confirm-fixed.png`、`/private/tmp/dev150-delete-cancelled.png` |
| 项目菜单与改名取消 | 通过；原名称保持 | `/private/tmp/dev150-project-menu2.png`、`/private/tmp/dev150-project-rename.png` |
| 添加工作区 | 通过；打开系统目录选择器，取消无副作用 | `/private/tmp/dev150-add-workspace.png` |
| 跨项目拖动 | 通过；弹出工作区权限切换确认，取消无数据变化 | `/private/tmp/dev150-cross-project-confirm2.png` |
| 官方设置与插件 | 通过；插件页面可达并列出 167 项官方插件 | `/private/tmp/dev150-settings.png`、`/private/tmp/dev150-plugins.png`、`/private/tmp/dev150-plugin-list.png` |
| MCP 首次授权 | 通过；展示调用方、设备、实例证书、工具数和风险，用户明确允许 | `/private/tmp/dev150-mcp-dialog.png` |
| 本 APP MCP 工具 | 通过；170 个接口、评分标记和可调用状态可见 | `/private/tmp/dev150-quick-actions.png` |
| LAN MCP 目录 | 通过；62 节点 9 个接口、证书、端点、目录版本与评分可见 | `/private/tmp/dev150-lan-mcp.png`、`/private/tmp/dev150-lan-mcp-tools.png` |

最终重建后二次复测通过：权限确认精确显示 `harness → untitled folder`，不再显示“原项目/目标项目”占位符；证据为 `/private/tmp/dev150-final-cross-project.png`。最终候选的插件清单、选中会话菜单、删除取消、项目菜单与添加工作区证据分别为 `/private/tmp/dev150-final-plugin-list.png`、`/private/tmp/dev150-final-session-menu2.png`、`/private/tmp/dev150-final-delete-confirm.png`、`/private/tmp/dev150-final-project-menu2.png`、`/private/tmp/dev150-final-add-workspace.png`。

## 3. 会话数据与权限合同

跨项目拖动不是单纯视觉排序。确认后固定执行：停止当前 Harness → 校验 source/target/session 所属关系 → 复制到暂存目录 → 解压并重写 `session.jsonl.zstd` 首行 `cwd` → 更新 `workspace.json` 与 `session_projcache.json` → 分阶段原子交换 → 清理备份 → 恢复 Harness。

任一步失败必须恢复旧目录和两个旧索引；目标权限不得提前生效。同项目内拖动仍走官方排序。删除则必须单独明确确认，确认后删除完整会话目录和官方索引；取消路径不得删除任何聊天、推理或工具记录。

## 4. MCP 生产闭环

在 KEMI-BM 已先启动、VibeKits 后启动的条件下，生产客户端发现：

- instanceId：`com.newlink.kemiscrollbench:41B8C7FDF4`
- endpoint：`192.168.3.62:9443/mcp`
- appVersion：`2.4.1`
- catalogRevision：`9`
- callable：`true`

真实只读调用 `kemi.benchmark.last_result` 返回：

- taskId：`d40ca49c-0439-4e51-8968-5b97e6ca2a5d`
- traceId：`a850bccb-4ba8-48cb-8d0f-5b50ff30aa5a`
- final/state/verification：`true / succeeded / verified`
- finalScore/grade：`99.51107080350508 / S`
- reportSha256：`sha256:9b87662042c9535da60145b5151c2f2542cd01a920448e5d18dbafcddc2211a5`

本次调用使用 VibeKits 生产 LMCP 客户端、证书固定、目录验签和标准结果信封；没有使用 curl/shell 伪造成功，也没有把 LAN 元数据发送给模型。KEMI-Send 当前未出现在本机层，是其 MCP 未开启时的正确状态，不得伪报为已发现。

## 5. 自动门禁

- `flutter analyze --no-pub`：0 issue。
- `flutter test --no-pub`：659 passed、15 skipped（均为需显式设备/联网/Release 环境的门禁）、0 failed。
- `native/harness/macos/runtime/bin/node tool/test_harness_session_rebind.mjs`：PASS。
- 官方 Harness 本地模型集成：真实 SSE 工具调用、原生审批桥及继续推理通过。
- CI 必须使用内置 Node 22 执行 zstd 迁移测试，不能误用 runner 自带旧 Node。

## 6. 发布门禁结果

1. 依据最终 HEAD 重建 Release，重新 Developer ID 深度签名。
2. 执行 Universal/macOS 12 兼容脚本、签名/硬化运行时检查、arm64 与 Rosetta x86_64 启动。
3. 在最终二进制再次点击插件市场、项目/会话菜单、改名、添加、拖动、取消删除、运行状态与独立草稿。
4. GitHub macOS Release 与 Windows workflow 全绿；Windows 必须包含同一迁移 helper 并通过 `node.exe --check`。
5. Apple 公证 Accepted、staple/validate 通过后，才可把精确候选复制到项目 `bin` 并记录 SHA-256。

macOS CI run `33662742558` 已完整成功，覆盖 Universal/macOS 12、Harness、ADB、7-Zip、Git、签名和构建检查。与应用代码一致的本地候选曾以 Rosetta 启动，`vmmap` 显示 `Code Type: X86-64 (translated)`、版本 `1.9.0.150 (2150)`；当时可执行 SHA-256 为 `e2e8aed25e5568b31fcab474f2d9d750cfd72ee5876137891f41a9ec9f046057`，App.framework SHA-256 为 `bc44b8836940490a60c216f66815867dec64a3082a5bea52f8bfe32dcacfbcf3`。这些哈希仅作为预发布验证证据，不能冒充最终公证包哈希。

Windows run `33663785345` 中 83 项共享测试全部通过，唯一失败来自 GitHub 新版 MSVC 将 Flutter 上游插件的 `<experimental/coroutine>` 弃用诊断升级为硬错误。提交 `449f675` 已在项目层显式启用微软提供的兼容定义，使其覆盖生成的插件目标且不修改第三方插件源码。

该轮还暴露了一个只存在于测试替身中的顺序假设：官方 Harness 可以先请求生成会话标题，再开始主任务；旧测试错误地把第一条模型请求固定当作工具调用。提交 `f928f0c` 改为按请求语义分别响应标题、工具调用和工具结果，本机真实集成测试连续三次通过。此修复保留官方标题功能，没有绕过或关闭它；最终 Windows run 更新为 `33666463241`。

随后 Windows 真机式工具桥测试发现 `vibekits.system.resources` 会被可选的 `GPU Engine` 性能计数器拖满 25 秒。提交 `6adc1b7` 保留显卡名称和安装显存证据，在性能计数器不可依赖时把实时 GPU 利用率明确标为不可用，避免次要指标阻塞整份物理资源快照。本机工具桥 36 项通过（Windows 专项在 Windows CI 执行）、`flutter analyze` 0 issue。

最终双平台门禁已通过：

- Windows run `33667794795`：固定 Harness runtime、静态分析、24 项 Harness UI、官方 Agent、本地工具桥、LAN MCP、共享界面、Windows EXE 编译和内置 Harness payload 全部成功。
- macOS run `33667794739`：Universal/macOS 12、Harness、ADB、7-Zip、Git、构建、签名检查和打包全部成功。

私有认证指南确认：受限沙箱中的 `security find-identity` 和 `codesign` 结果可能是假阴性，认证必须在正常 Security/trustd 上下文执行。正常上下文识别并使用了 `Developer ID Application: zhen ji (26T5WV4GLP)`，身份指纹为 `CBF5FFD7566900053824789DF3FB4DDDF15F427A`；没有使用 ad-hoc 包冒充正式包。

最终发布闭环：

- 精确源码：`e5c50010313d8c3b4b452e58f62b20681af6a25f`。
- Release 构建：`Vibekits.app`，构建输出约 668.6 MB；兼容检查确认全部嵌入组件为 Universal、最低 macOS 12。
- Developer ID：34 个 Mach-O 完整签名并深度验签；内置 Harness Node 22.19.0、ADB、7-Zip、Git、DSH 均通过门禁。
- Apple 公证：Accepted，Submission ID `525138ba-cd62-4b0c-ab57-e362e88b6b32`；staple/validate 成功；Gatekeeper 返回 `accepted`、`source=Notarized Developer ID`。
- Intel 真机式兼容：对最终解包候选执行 `arch -x86_64`，`vmmap` 返回 `Code Type: X86-64 (translated)`；同一进程真实调用内置 Harness 本地桥并返回 `Verified local Harness tool bridge`，随后可由 TERM 正常结束。
- 正式 App：`bin/Vibekits.app`。
- 正式 ZIP：`bin/Vibekits-1.9.0-dev.150+2150-macos-universal-notarized.zip`，大小 263,002,248 bytes。
- ZIP SHA-256：`743e5c94362a94e47c36b475acbdb3a0719eb8b2a3d3751de2a3434f6e88af1d`。
- 签名并 staple 后主可执行 SHA-256：`987d616177622e152be81bafdde728b86197db2d39412933aa196291babb4e04`。
- 签名并 staple 后 App.framework SHA-256：`9fac6b9b4ba796bf3beeb47520d87f8fe21bcc923f3f5fd540941061ca42a818`。
- 复制到 `bin` 后再次通过 SHA、`codesign --deep --strict`、`stapler validate` 和 `spctl --assess`，排除了复制损坏或票据丢失。

旧 `bin/Vibekits.app` 未直接删除，发布时移动到 `/private/tmp/vibekits-bin-backup.P7BCVJ/Vibekits.app` 作为本机临时回退副本。
