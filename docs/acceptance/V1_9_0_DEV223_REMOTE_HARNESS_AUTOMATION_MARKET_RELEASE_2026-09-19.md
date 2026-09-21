# VibeKits dev.223 远程 Harness 自动化与窗口记忆验收

日期：2026-09-19  
版本：`1.9.0-dev.223+2223`

## 设计目标

控制端只需连接目标 VibeKits 设备 ID，即可把任务直接交给目标电脑自己的官方 Harness。目标 Harness 在自己的聊天中显示命令与过程，并调用目标电脑本机公开的工具完成操作。控制端通过结构化接口读取状态、增量历史、等待变化和停止任务，不依赖截图、OCR、坐标点击、外部 SSH 或私有 DSH 凭据。

命令提交必须在 3 秒内返回 `workspaceId`、`sessionId`、`requestId`、状态和游标。状态覆盖 `accepted/queued/running/waiting_approval/completed/failed/stop_requested/stopped`；等待超时返回 `changed=false`，不能误报任务失败。

macOS 窗口退出前由系统保存 frame；下一次启动恢复用户最后的位置、大小和最大化状态。

## 自动化测试

| 用例 | 断言 | 当前结果 |
|---|---|---|
| 命令代理无活动工作区 | 三秒内明确失败，不悬挂 | PASS |
| 命令发送 | 返回接受状态及唯一请求/会话标识 | PASS |
| 状态读取 | 返回运行阶段、审批状态、游标与更新时间 | PASS |
| 增量历史 | 按 cursor 返回官方会话记录 | PASS |
| 状态等待 | 变化时返回新游标；超时返回 `changed=false` | PASS |
| 停止 | 返回 `stop_requested` 并允许继续查询终态 | PASS |
| MCP 目录 | 五个 `vibekits.harness.session_*` 工具均公开且有执行器 | PASS |
| macOS 窗口恢复合同 | 设置固定 autosave 名称并恢复保存 frame | PASS |

## 正式发布证据

- KEMI 商场现有 macOS 应用 `app_id=53` 已更新为 `1.9.0-dev.223 / 2223`，保持商城展示、非强制更新；未启用启动弹窗或后台自动更新。
- 最终 Apple 公证 Submission ID：`7cf1b828-c163-4f33-a961-41b3b398d1b5`，状态 `Accepted`。
- 最终商城 CDN 包：`420443201` bytes；SHA-256 `e1d921b218e1aa15076331ac7334b360c04469fbfd043d87c50a45b4cc00a50b`。
- CDN 地址：`https://cdn.newlink-sz.com/kemiAppStore/macpkg/2026/09/1789873441145_c14dedb7_Vibekits-1_9_0-dev_223_2223-macos-univer.zip`。
- 对 CDN 回下载包执行全局商城发布技能验包脚本：唯一顶层 `Vibekits.app`、`x86_64 + arm64`、Developer ID、staple、Gatekeeper 均通过，结果 `PASS`。
- 更新接口：本地 `2222` 返回 `has_update=true` 并指向上述 CDN 包；本地 `2223` 返回 `has_update=false`。
- 精确签名候选真实启动并发布本机 Harness tool bridge，通过只读目录调用；远程 Harness 命令工具 `session_prompt/status/history/wait/cancel` 已进入发布包。
- 设备 `4456560334` 需先从商城更新到本版本后再执行跨机 Harness KOffice 闭环；本次不以旧版远端结果冒充新版验收。

## 发布流程修复

- `tool/sign_and_notarize_macos_release.sh` 改为直接启动参数指定的精确 App 主程序，避免 LaunchServices 在同 Bundle ID 下启动其他已登记候选。
- 签名验收结束时按精确 App 路径清理 Harness Relay，防止旧候选残留并持续占用 CPU。
- macOS 签名最终结论只在正常 Security/trustd 上下文执行；受限沙箱中的 `codesign` 假阴性不得作为发布阻断证据。
