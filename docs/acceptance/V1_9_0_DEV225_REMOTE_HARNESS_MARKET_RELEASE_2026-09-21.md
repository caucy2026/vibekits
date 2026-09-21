# VibeKits 1.9.0-dev.225 远程 Harness 与商场安装修复验收

- 日期：2026-09-21
- 版本：`1.9.0-dev.225+2225`
- 目标：远程命令必须进入目标机官方 Harness、执行记录可增量读取；商场不得因发布记录使用展示大小而误报缺少 HTTPS/精确大小；主程序退出后 Harness Worker 不得成为高 CPU 孤儿。

## 修复

- 远程 `session_prompt` 改走 VibeKits 持久消息队列与官方页面输入桥，沿用本地用户真实发送路径；忙碌时排队，空闲时立即调度。
- `session_history` 按请求游标过滤，最多返回 64 条、256 KiB；单条超大工具记录压缩为有序摘要并保留继续读取游标，移除无界 projections。
- 已安装且云端版本不高于本机时只显示“已是最新版”或“禁止降级”，不再显示与当前操作无关的安装元数据缺失警告。
- macOS/Linux Node Worker 记录自己的直接父进程；父进程变化为 launchd/init 时立即退出，避免仅检查已被复用的 VibeKits PID 导致孤儿忙循环。
- 发布时要求 KEMI 商场公开详情同时返回 HTTPS 下载地址、精确十进制 `file_size`、同值 `file_size_bytes` 和 64 位 SHA-256。

## 自动门禁

- 聚焦回归：远程命令、执行历史、应用中心和 Harness 生命周期相关测试全部通过。
- 全量 Flutter：`926 passed / 32 environment-gated skips / 0 failed`。
- 修改文件静态分析：`No issues found`。
- macOS Release：Universal `x86_64 + arm64`，Info.plist 为 `1.9.0.225 / 2225`。

## 现场 CPU 诊断

- 发现 dev.221 的官方 DSH Web 及两个 MCP Worker 在主程序退出后成为 PPID 1 孤儿，CPU 约为 `189% + 92% + 93%`。
- 三个进程忽略 SIGTERM，已使用 SIGKILL 清除；清除后 VibeKits Harness 孤儿不再出现在 CPU 排名中。
- 同时存在的 Android Release 构建属于另一任务，未停止或修改。

## 待发布闭环

- 正式 Developer ID 签名、Apple 公证与票据装订。
- 目标机安装 dev.225 后真实提交任务，验证 `accepted → running → completed`、有界历史和最终回答。
- KEMI 商场 app_id 53 更新；公开详情、默认列表、CDN、2224 正向更新与 2225 反向检查全部通过。
- 公布后更新全局 KEMI 商场技能，固化精确字节字段门禁。
