# DeepSeek Harness 官方 Web 行为对齐规范

更新日期：2026-08-19

适用版本：`1.9.0-dev.30+40`

## 1. 唯一行为基线

- 上游仓库：<https://github.com/deepseek-ai/deepseek-harness>
- 官方 Web 指南：<https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/user/guide/index.md>
- Windows 当前固定产物：`@deepseek-ai/dsh@0.1.0-rc.7`
- 精确行为以 Release 中该版本的 `@deepseek-ai/dsh-web-app` 及 Client UI 包为准；仓库 `master` 只用于跟踪后续变更。

Harness 仍在 Developer Preview，上游明确会有破坏性变更。每次升级固定版本时，必须重跑本文档全部验收项。

## 2. 官方的项目与会话关系

| 官方行为 | Vibekits 移植合同 |
|---|---|
| 启动 `dsh web` 后进入完整 Web UI | Windows 用 WebView2 直接嵌入官方生产 Web 产物，不再仿制对话界面 |
| 新 profile 没有已选工作区 | 保留官方空状态和 `Choose workspace`，不用 Flutter 假选中 |
| 未选工作区时 composer 不可用 | 由官方 Client/Host 状态决定，App 不绕过 |
| 工作区可添加、重命名、排序、移除 | 操作全部使用官方侧边栏和 Host API |
| 移除工作区不删目录和会话日志 | 不由 Vibekits 删项目；原会话进入官方 `Ungrouped` |
| 一个工作区持有有序的多会话 | 不限定“40 会话/80 消息”，不另存 Flutter 副本 |
| 会话可重命名、拖动排序、Fork、Archive | 直接使用官方菜单与事件存储 |
| Archive 保留原工作区位置，取消归档后恢复 | 不另做“删除会话”替代归档 |
| 侧边栏可按工作区分组或平铺 | 保留官方分组、折叠、状态点和列表密度 |
| 搜索支持会话名，可选历史内容 | 使用官方搜索投影，不另做搜索索引 |

## 3. 官方会话工作台

当前会话由官方事件和投影管理，同时关联：

- 有序对话流、输入器、执行中状态和 Enter 偏好；
- 当前模型与模型设置；
- 当前权限预设与需要审批的原生操作；
- 工具调用及 trajectory/详情；
- goal、plan、jobs、subagent、todo、用户问题和交付物；
- session state 状态点和侧边栏投影。

Vibekits 禁止再拼接“最后 12000 字符”伪造续话，也不再自己生成推理中间态。用户看到的消息、工具、计划和任务状态必须是官方事件的真实投影。

## 4. 模型与权限

- 官方流程是 Settings → Models 录入 API Key，保存后立即可用，无需重启 Web server。
- 官方流程使用 `$DSH_HOME/.credentials.yaml` 作为可写凭据源；Vibekits Web 进程不得注入 `DEEPSEEK_API_KEY`，否则官方设置页会按设计显示为只读。
- 旧版 Windows Credential Manager 中已有 Key 时，仅做一次迁移：若官方凭据尚未配置则写入官方存储，若已有配置则保留官方值；迁移成功后删除旧凭据。Key 不进入源码、安装包、普通设置或日志。
- Web 进程不得用 `DEEPSEEK_BASE_URL`、`DEEPSEEK_MODEL` 覆盖官方模型设置；API 地址、模型目录与默认模型全部由官方 Models/Settings 链路持久化和热更新。
- 设置中的默认权限影响新会话；当前会话的权限切换由官方会话命令/控件管理。
- Vibekits 只在首次启动时创建默认模型设置；后续启动不得覆写官方 Web UI 保存的模型和权限选择。
- 官方原生文件/命令工具使用官方审批 UI；Vibekits MCP 扩展工具在进入 App 领域服务前仍做目标锁定、参数验证、风险审批和审计。

## 5. App 集成边界

```text
Flutter 桌面壳
  └─ WebView2
      └─ 官方 dsh web（工作区/会话/模型/权限/对话）
          ├─ 官方 Native tools
          └─ 官方 MCP client
              └─ Vibekits MCP 服务器
                  └─ ADB/串口/Git/文件/哈希/数据库等 App 领域服务
```

Flutter 只负责运行时、WebView 生命周期、调试目录、旧 Key 初值与 Vibekits MCP 边界；不拥有官方的项目、会话和对话数据。

Windows 运行器为每个 Harness 子进程创建 `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` Job Object。正常停止先由 Dart 取消并回收；如 Windows 在 Flutter `dispose` 完成前终止界面，运行器关闭 Job 作为最后保障，不得留下 `node.exe`。

## 6. 当前移植状态

| 平台/项 | 状态 |
|---|---|
| Windows 官方 Web 生产产物嵌入 | 已实现 |
| 官方 Web server 本机 HTTP 200 启停 | 已验收 |
| 项目/会话/侧边栏/设置改为官方单一数据源 | 已切换 |
| Vibekits MCP 服务器随官方 Web profile 启动 | 已接入，继续做真 Key/ADB 实机回归 |
| Settings → Models 填写/修改 Key | 已恢复官方可写凭据链路；Windows Release 已验证 Ctrl+V 写入受控测试值且未保存 |
| macOS 官方 WebView 容器与运行时 | 未完成，不宣称双平台已闭环 |

## 7. 逐项差异审计

| 检查项 | `@deepseek-ai/dsh@0.1.0-rc.7` 官方行为 | Vibekits 当前处理 |
|---|---|---|
| API Key | Models 页写入官方可写凭据文件；环境提供时只读 | 已纠偏为官方链路；仅保留一次旧凭据迁移 |
| API 地址/模型 | Models 页配置并热更新；内置 Flash/Pro 目录 | Web 启动不再用环境变量覆盖 |
| 工作区—会话 | 一个工作区管理有序多会话；移除工作区不删文件或会话日志 | 直接使用官方 Web/Host 状态，无 Flutter 副本 |
| 重启恢复 | 官方存储恢复工作区、会话、设置 | Windows 实机已验证恢复 |
| 会话归档 | 隐藏会话但保留日志、工作区槽位和取消归档恢复能力 | 保持官方语义，不用假删除替代 |
| 永久删除会话 | 当前 RC.7 没有 `workspace.deleteSession` Host API 和官方菜单 | 作为明确 Vibekits 扩展：独立“删除会话”菜单、二次确认、停止运行态后精确删除会话目录，并同步工作区索引与投影缓存；重连期间保留原界面并显示底部进度，瞬态失败自动重试一次；不把归档改名伪装成删除 |
| 权限预设 | `read-only`、`workspace-write`、`danger-full-access`；官方动态显示名含英文 | 内部标识和审批行为保持官方；中文界面显示为“只读 / 工作区读写 / 完全访问” |
| 模型二级菜单 | 根菜单进入模型目录或推理等级目录 | 保留官方两级结构；WebView2 返回空焦点时不再误判为外部点击 |
| API Key 粘贴 | 浏览器输入框支持系统粘贴 | WebView 内增加 Ctrl+V/Cmd+V 安全转发，只写入当前可编辑字段，不记录剪贴板内容 |
| 推理/工具/计划中间态 | 由官方会话事件投影 | 直接显示官方 UI，不由 Flutter 伪造 |
| Vibekits 工具 | 官方通过 MCP 扩展第三方工具 | 仅增加 `vibekits` MCP 服务；参数校验、风险审批和真实日志留在 App 领域层 |
| 外层 Harness/OCR 标签 | 非官方 Web 内容 | 仅是 Vibekits 工具分类容器，不接管官方工作台行为 |
| 遥测 | 官方默认关闭，可由环境启用 | 按 Vibekits 隐私策略固定关闭，属于部署策略差异 |
