# dev227 派生会话验收：BLOCK

> 本文保留初始候选的失败证据，不表示后续修复候选的结果。最终需求以 `../69_HARNESS_CONTINUATION_REQUIREMENTS.md` 为准；九段摘要与首次成功回复后消费属于实现方案。

## 范围与需求依据

验收本机正在运行的 dev.227+2227，源码快照为外盘 `dev227-local-20260923/source`。依据 `docs/superpowers/specs/2026-09-19-harness-context-continuation-design.md` 及其中 2026-09-20 交互硬约束。

1. 点击后立即创建、选中同工作区的空白官方派生会话，显示分阶段旋转进度。
2. 名称按“原名称 2、3……”持久化，不复制原聊天时间线。
3. 九部分交接：目标、约束、已完成、关键决定、文件与版本、验证结果、未完成项、已知问题、下一步。
4. 首次模型请求注入交接，首次成功助手回复后消费；用户消息保持原文。
5. 独立保存来源关系和来源卡片，支持返回、受控查阅、重启恢复、删除后的断链提示。
6. 进度、错误、重试只属于来源/派生会话；重试复用子会话；有总超时，不阻塞第三个会话。
7. 菜单仅一个派生入口，官方布局加少量暖黄色；运行中的来源禁用。

文档冲突：用户流程称不依赖模型请求，适配边界又要求临时官方模型会话生成摘要。当前代码使用后者。本次不擅自选择或更改此语义。

## 现场证据

- 用户截图及 CUA 实时窗口均停在“远程仿真只读获取 Mac 信息”的派生菜单，未切换子会话、未显示进度。
- 运行进程 PID 15579 来自已签名 dev227-local 构建；WebContent PID 15614 CPU 约 101.5%。
- harness-work.jsonl：2026-09-23T07:14:58.083602Z 收到 continuation.requested，4 毫秒后 continuation.failed：`FormatException: 未找到会话：《远程仿真只读获取 Mac 信息》`。没有此次 source_resolved 或 completed 记录。
- 源码：来源解析依赖 workspaceSnapshot 的 workspaceId/sessionIds 成员；这次真实目标为何不在可解析清单仍需进一步核对，不能仅凭标题断言根因。
- 前端 progress 渲染无条件设置 label.textContent，childList MutationObserver 又同步调用 progress 渲染。相同值赋值仍会替换文本节点并产生 mutation，形成循环。
- 最小隔离复现：连续 3 次不变状态渲染，产生 3 次文本 childList 变更；错误样式被清除，重试入口每次被移除。错误渲染不稳定。

## 自动测试与限制

- 对正在运行的源码快照执行 continuation coordinator/store/source resolver/source context：16/16 通过。
- Node 上下文注入测试：官方 SystemPrompt 组装、首次成功回复消费、无关会话隔离及删除成员边界通过。
- 日志：`/Volumes/ORICO/kemi-build-cache/app-release-gate/vibekits/macos/dev227-local-20260923/continuation-audit-tests.log`。
- 上述底层测试没有覆盖本次 WebView DOM 循环，不能作为完整交互通过证据。
- 本次没有修改产品代码，没有重启或删除用户会话。

## 结论

BLOCK：点击派生后即时反馈和可恢复失败不符合要求。完整成功链路、名称持久化、来源卡往返、首次真实继续开发、重启恢复均未在此候选完成验收，不得标记通过。需修正来源解析与前端进度/错误渲染后，再做真实 UI 闭环验收。

## 后续修复中发现的回归（保留首轮失败）

- `dev227-continuation-final-20260923`：错误与重试已经稳定显示，切到第三会话隐藏、返回保留；但未分组来源接入失败。官方 `workspace.insertSessionBefore` 只能排序已登记成员，不能 attach 来源。
- `dev227-continuation-r2-20260923`：使用 `session.create` 的已有 ID 接入协议，但适配器只转发 workspaceId、丢弃 sessionId，导致创建另一个空 ID。结果身份校验正确拦截，未冒充接入成功。2026-09-23T08:06:10Z 真实 UI 复现。
- 修复使用官方 `session.create({workspaceId, sessionId})` 幂等接入，并补充真实 HTTP 请求体测试，要求既有 ID 完整转发，不能仅依赖 resolver 的假适配器。
- 摘要辅助会话改用官方 archive 接口隐藏，避免不存在的 session.delete RPC 留下可见内部任务。
- 原始用户会话和历史均未删除。后续候选须重新完成实际派生、摘要交接、来源往返及重启验收。
