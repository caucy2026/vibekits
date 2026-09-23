# dev227 派生会话 Mac 本机试用记录

后续复验发现摘要不可见、空白派生行删除按钮缺失，以及部分派生工作区 ID 导致摘要注入失败；本记录只保留为当时证据，当前结论以 `DEV227_CONTINUATION_SUMMARY_DELETE_2026-09-23.md` 为准。

2026-09-23：按用户“做好后先给我测试”，保留已启动的本机候选供试用；没有发布。

## 候选

- 1.9.0-dev.227+2227；基线 9a6ed3045c144c93c406d8fdc00963510a6cf80d，包含共享工作树修复。
- 应用：`/Volumes/ORICO/kemi-build-cache/app-release-gate/vibekits/macos/dev227-continuation-r3-20260923/source/build/macos/Build/Products/Release/Vibekits.app`。
- AOT SHA-256：`db77adc90b6da03e0a2a858ef642f7218ec843a5273aba2d3fe7e59442d02e7a`。
- Developer ID：zhen ji，Team 26T5WV4GLP；签名验证通过，新旧指定要求及权限一致。未公证、未上架。
- 上述 run 目录保留 candidate.json、signature-continuity.json、source-and-crash-baseline.json 及下列证据。

## 修复范围

1. 进度文字仅在变化时更新，避免 MutationObserver 自激循环；错误与重试保留，第三会话隐藏进度，返回恢复。
2. 未分组来源通过官方 session.list 定位真实 ID/cwd；只对明确选中的来源建立工作区，使用 session.create 的既有 ID 协议接入。
3. 官方请求适配器保留 sessionId，避免幂等接入被误变为新建空会话。排序 API 不再被用于接入未登记来源。
4. 内部摘要辅助会话使用官方 archive API 隐藏。
5. 四端产品需求已写入 docs/69_HARNESS_CONTINUATION_REQUIREMENTS.md，并接入产品需求及需求台账。

## 实测结果

| 范围 | 结果与证据 |
|---|---|
| 自动回归 | 53 项相关测试及 1 项来源受控查询测试通过；tests.log、source-context-tests.log |
| 旧实现负对照 | 新 HTTP 合同测试检测到旧适配器缺失 sessionId；adapter-negative-control.log；新实现正对照通过 |
| DOM 防卡死 | 相同状态重复渲染无重复变更，错误/重试与第三会话往返通过；dom-test.log，包含旧渲染器负对照 |
| 官方上下文注入 | 实际 SystemPrompt 组装、一次性消费、无关来源与删除成员边界通过；context-test.log |
| 三轮真实派生 | 从未分组来源开始，随后从已接入来源连续派生；独立 ID、名称 3/4/5，分别 16.175、15.043、17.223 秒；continuation-events.json |
| 界面行为 | 点击后先进入空白会话显示旋转进度；完成后显示来源卡片；来源往返通过；摘要期间第三会话可使用，完成后没有抢回页面。CUA 实时截图留在本任务记录 |
| 实际交接 | 编号 3 在问题未提供来源事实时正确回答远程 Mac 的 KEMI 设置/应用/关于按钮诊断任务及已确认发现；没有调用工具 |
| 重启恢复 | 正常退出再启动后，编号 5、来源卡片、三个子会话的标题及摘要哈希全部保留；编号 5 首次问答正确说出原任务目标；restart-persistence.json |
| 一次性消费 | 编号 3 首次成功回复后生成 consumed 标记；编号 4 保留未使用摘要供试用；没有复制原会话聊天时间线 |
| 资源 | 115 秒、24 次采样，应用 CPU 中位数 1.75%、WebContent 1.1%，峰值 27.1%/13.7%；RSS 末值低于起点；resource-samples.jsonl、resource-report.json |
| 崩溃 | 本轮相关诊断报告新增 0；不等于已完成长时间 soak 或所有挂起检测 |
| 删除 | 隔离存储夹具覆盖 owner 停止后删除、刷新不复活、停止失败保留数据；未删除用户真实会话 |

## 范围边界

这是 Mac 功能试用候选，不是四端正式发布验收。其他平台实机、完整清洁安装/覆盖升级、长时间 soak，以及最终候选上“已创建子会话后模型超时再重试复用”的完整故障注入链路尚未完成；发布门禁仍为 BLOCK，不冒充全部稳定性验收通过。

最初卡死与中间候选的真实失败保留在 DEV227_CONTINUATION_AUDIT_2026-09-23.md。旧候选 ZIP 不能代替本次 r3 应用。

试用入口：来源会话右侧“…”→“派生会话”；编号 4 仍是未发送首条消息的派生会话，可直接验证上下文继续开发。
