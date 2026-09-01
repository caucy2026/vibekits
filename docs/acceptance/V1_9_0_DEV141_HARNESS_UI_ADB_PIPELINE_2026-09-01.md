# VibeKits dev.141 Harness UI / ADB 管道验收

## 问题证据

- 宽屏下输入框固定最大 820px，与全宽的任务时间线、运行条左右边界不一致。
- Harness 调用 `vibekits.adb.shell` 时曾把 `dumpsys display | grep -E ...` 整个参数列表交给 ADB。ADB 会把 argv 重新组合成远程 shell 字符串，模型生成的引号在设备端丢失边界，返回 `adb shell: syntax error: no closing quote`。后续纯 `dumpsys display` 成功证明 ADB 连接和内置工具没有缺失。

## 修复合同

1. Composer 在可用水平空间内必须占满与运行条相同的宽度，不再使用 820px 封顶。
2. Android Shell 仅对基础命令为 `dumpsys` 或 `getprop`、后缀为单一 `grep` 的管道做规范化。
3. 支持 `grep` 的 `-E` / `-F` / `-i` 组合；未知 flag、多重管道或非只读基础命令不会被伪装成安全过滤。
4. 实际 ADB argv 不含 `|` / `grep` / pattern；结果保留原始请求参数、实际执行参数、`pipelineNormalized=true` 和本地过滤摘要，便于 UI 审计。
5. 该规范化是同一次工具调用的正常执行路径，不先记录一次失败再重试。

## 自动化证据

- `test/lmcp_capacity_manager_test.dart`
- `test/harness_tool_bridge_test.dart`
- `test/deepseek_harness_test.dart`
- `test/adb_pipeline_live_test.dart`（使用 Release 内置 ADB 对真实设备做只读验收）
- 最终结果：60 passed / 1 platform skip / 0 failed。
- 管道定向断言实际 runner 只收到 `-s 192.168.3.63:5555 shell dumpsys display`，返回值仅保留 `DisplayDeviceInfo` 和 `mDisplayId`匹配行。
- 宽屏定向断言 1280px 视口中 composer shell 宽度大于旧上限 820px。
- Release 内置 ADB 已真实连接 `192.168.3.63:5555`，通过 Harness 工具桥执行与现场失败截图同形的 `dumpsys display | grep -E ...`：1/1 通过，`pipelineNormalized=true`，无首次红色失败。
- 正式 App 视觉证据：[`screenshots/V1_9_0_DEV141_HARNESS_ALIGNED.jpeg`](screenshots/V1_9_0_DEV141_HARNESS_ALIGNED.jpeg)；输入区与上方会话内容区左右边界一致。

## 发布门禁

- 版本：`1.9.0-dev.141+2141`
- LMCP `catalogRevision=2141`（ADB Shell 公开工具描述发生变化）。
- Release 必须放入项目 `bin/Vibekits.app`，完成深度签名校验、启动和正式进程版本核对后才可交付。
- 最终 App executable SHA-256：`161c718ea205a440c4c4a8bf2b1032a26b4e2ad55387368dc27464ce8d466b3e`。
- 最终 App.framework SHA-256：`157cc77afcd79a1128203d28f92a2ba9cdd2da405b4b4869f8847591e0c6037b`。
- 运行路径：`/Volumes/ORICO/newlink-new/vibekits/bin/Vibekits.app`；验收 PID `41601`；UDP `*:47831` 已监听。
