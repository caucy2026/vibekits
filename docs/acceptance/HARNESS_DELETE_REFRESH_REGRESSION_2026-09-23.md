# Harness 删除后刷新恢复：2026-09-23

## 原因
本地 dev.225 未提交修改为避免刷新整个页面，移除了删除前停止官方 DSH Web 的步骤。`HarnessSessionStore.deleteSession` 只编辑磁盘目录、workspace.json 和 session_projcache.json，注入脚本只移除 DOM 行；官方运行时仍持有旧内存索引，刷新或后续写盘可能恢复列表行。此前局部 UI/文件测试未覆盖 live owner 的最后写盘。

## 修复
- 删除前等待当前 Harness owner stop 完成，再改磁盘；停止失败不得删除。
- 删除后重新启动并连接 Harness，再核对会话目录，才报告成功。
- Harness 忙碌/审批中或已有删除操作时拒绝新的删除，避免重启中断正在运行的任务或并发写入。
- 保留精确 ID 定位、删除确认和局部行状态；失败提示不再错误保证原会话仍保留。
- 代价：删除会触发 Harness 短暂重连。当前官方 runtime 没有已验证的 session.delete 远程端点，不用猜测 API 替代安全停写。

## 验证
聚焦 Flutter 回归 22 项通过，包括模拟后台 stop 最后一次写入后再刷新索引，以及 stop 失败保留会话。本次未操作用户真实会话进行永久删除，真实用户场景仍需在修复候选中复核。不能将这些自动化结果宣称为全场景验收通过。

负向控制：在隔离副本中故意把顺序改成先删除、再执行 owner 最后写盘；同一刷新检查准确失败（refresh resurrected session）。正确顺序通过，证明测试能捕获此回写缺陷。两份修复源码 dart analyze 无问题，macOS Release 构建成功。
