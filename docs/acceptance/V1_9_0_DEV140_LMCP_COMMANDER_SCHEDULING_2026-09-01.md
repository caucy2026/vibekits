# VibeKits 1.9.0-dev.140 LMCP 指挥官调度验收

日期：2026-09-01  
版本：`1.9.0-dev.140+2140`  
唯一规范：`docs/50_LMCP_APP_DEVICE_IDENTITY_AND_SWITCH_STANDARD.md`

## 交付结果

- `announce` 增加严格 runtime：idle/busy/saturated/draining/error、capacity、inFlight、availableSlots、loadRevision、queueDepth、oldestTaskAgeMs 和 acceptingReservations。
- 调用方启动后主动发送 discover；已运行 Provider 在 0～500 ms 抖动内应答；稳定时 4 秒公告，负载变化 250 ms 合并重发。
- Provider 固定公开 `lmcp.node.status`、`lmcp.capacity.reserve/renew/release`。
- 租约绑定签名调用方、toolName、idempotencyKey 和 scopeDigest；10～120 秒 TTL；错误身份或 token 拒绝；token 不进入 UDP、状态、日志或最终报告。
- 指挥官保持 app→local→lan 层级，同层按容量 35%、工具质量 25%、可靠性 15%、延迟 15%、新鲜度 5%、公平性 5% 排序。
- Harness 新增只读 `vibekits.mcp.schedule_plan` 和实际执行 `vibekits.mcp.auto_call`；后者完成排序→预约→业务调用→finally 释放，预约忙自动换队。
- app 层已有独立 8 槽 in-process 容量并优先执行；local 只有声明 runtime 和四工具且能跨调用保存租约的 Provider 才可调度；LAN 使用签名 HTTPS 和 `tools/call.params.scheduling`。

## 自动化证据

- Flutter 3.47.0 / Dart 3.13：`flutter analyze --no-pub`，0 issue。
- LMCP/Harness 门禁：68 passed、1 platform skip、0 failed。
- 100 个指挥官同时争抢单槽：1 granted、99 `CAPACITY_BUSY`，无超卖。
- 同幂等键复用同一 lease；错误身份/token 返回 `LEASE_SCOPE_MISMATCH`；status 不含 token。
- 协议真实完成 reserve→绑定业务 tools/call→node.status→release。
- 首选 LAN 节点预约忙时自动切换第二节点；业务调用一次、release 一次；最终 JSON 不含 token。
- app 自动调度优先本机并在完成后恢复 8/8 空闲槽。
- 双实例共享 UDP、晚启动观察者发现、discover 响应、goodbye 移除、1200-byte 公告门禁全部通过。

完整仓库测试另行运行过，静态检查仍为 0；全量测试存在 24 项与本轮无关的环境/既有失败，主要为测试运行环境缺少打包 Git runtime、系统 Keychain 编码差异、并行 UI/文件系统隔离和显式 live 环境缺失。本报告不把它们伪报为通过，也不把这些失败算作 LMCP 调度回归。

## Release 与生产证据

- 正式路径：`/Volumes/ORICO/newlink-new/vibekits/bin/Vibekits.app`
- Bundle：`1.9.0.140 (2140)`；ad-hoc 深度签名，`codesign --verify --deep --strict` 通过。
- 主可执行 SHA-256：`1da13b4d1f80f6f72057284bd18ba0d47538e95bf6c0c5e896848478d2c2a377`；App.framework SHA-256：`05962494b331769bb6f2cf129a1679bf0b40689c11a608bcd26eae82037d07ed`。
- 正式进程真实 Harness `vibekits.mcp.catalog_list` 返回 app：`schedulable=true`、state=idle、capacity=8、availableSlots=8、四个控制工具齐全、`vibekits.mcp.auto_call` 可见。
- 正式进程监听 UDP `*:47831`；MCP 对外开关保持用户设置，不绕过首次授权。

## 192.168.3.62 真实 LAN 门禁

正式 Harness 已发现 `com.newlink.kemiscrollbench:41B8C7FDF4`、版本 2.3.0/revision 7、端点 `https://192.168.3.62:9443/mcp`，且 `discoveryAlive=true/endpointReachable=true`。

但实际目录认证为 `catalogState=rejected / catalogErrorCode=http_401`，因此工具为空、runtime 未提供、`callable=false/schedulable=false`。VibeKits 正确拒绝调用，没有使用缓存或 shell 伪造结果。已通知 KEMI-BM 开发任务按唯一规范修复首次/持久调用方授权、runtime、四个租约工具和 scheduling；对方 READY 后必须重新由正式 Harness 执行 `catalog_list → auto_call(kemi.benchmark.run) → status(final=true)`，保存 taskId/traceId/reportSha256/finalScore/grade。该真实物理闭环在对方修复前保持未通过。
