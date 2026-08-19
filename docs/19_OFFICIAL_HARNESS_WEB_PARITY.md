# DeepSeek Harness 官方 Web 行为对齐规范

更新日期：2026-08-19

适用版本：`1.9.0-dev.23+33`

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
- 旧版 Windows Credential Manager 中已有 Key 时，Vibekits 只在启动官方进程时作为环境初值注入；没有 Key 也必须允许 Web UI 启动，由官方设置完成配置。
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
| macOS 官方 WebView 容器与运行时 | 未完成，不宣称双平台已闭环 |
