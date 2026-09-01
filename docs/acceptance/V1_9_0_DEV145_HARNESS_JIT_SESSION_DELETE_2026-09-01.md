# VibeKits 1.9.0-dev.145 Harness JIT 与会话永久删除验收

日期：2026-09-01  
版本：`1.9.0-dev.145+2145`  
状态：通过

## 1. 修复目标

1. 正式 Developer ID/Hardened Runtime 包中的 Harness 必须能真实工作，不能只通过签名和公证。
2. 项目内单个会话必须能够永久删除全部聊天、推理、规划、工具时间线、结果和草稿，同时保留项目文件与其他会话。

## 2. 根因与修复

dev.144 的内置 Node 在发送 Harness 任务时于 V8 初始化阶段触发 `SIGTRAP`。正式签名脚本给所有 Mach-O 启用了 Hardened Runtime，却没有给 Node 保留 V8 JIT 所需的 `com.apple.security.cs.allow-jit`。

dev.145 增加 `macos/Runner/HarnessNode.entitlements`，并在 Developer ID 与 ad-hoc 签名脚本中单独重签内置 Node。新增签名运行时验证和签名后真实 Harness MCP 冒烟；任何一项失败都会在上传 Apple 前终止发布。

会话菜单新增破坏性“删除会话”入口。运行中会话不能删除；已停止会话必须二次确认，确认文案逐项说明被删除数据和不受影响的数据。持久层移除目标 session，草稿仓库同步清理，界面切换到剩余会话或空状态。

## 3. 自动化结果

- `flutter analyze --no-pub`：0 issue。
- `flutter test --no-pub test/deepseek_harness_test.dart`：23/23。
- 删除回归：目标 session、messages、execution trace、draft 均删除；另一 session 保留。
- Universal Release：构建通过。
- 兼容性：App x86_64 最低 macOS 10.15、arm64 最低 macOS 11.0；内置 Node 22.19.0 为 x86_64/arm64 Universal，完整 Harness 最低 macOS 11.0。
- 签名运行时：Hardened Runtime=true、allow-jit=true、Node `--version` 与 DSH `--help` 均通过。

## 4. 正式发布与真实闭环

- Apple notarytool：`Accepted`。
- Submission ID：`9a0cddb1-41ce-4fe5-a231-7feb209fc128`。
- staple/validate：通过。
- `codesign --deep --strict`：通过。
- Gatekeeper：`accepted`，`source=Notarized Developer ID`。
- 正式 App：`bin/Vibekits.app`。
- 正式 ZIP：`bin/Vibekits-1.9.0-dev.145+2145-macos-universal-notarized.zip`。
- ZIP SHA-256：`60dff7aec1ec2a4887d2f9d2819c5b3b043cc90c89570697389945918352392b`。
- App executable SHA-256：`939b12a9b1b950317f8cb96a08cd13f5bdee4fd287475fc94761860ea7205ceb`。
- App.framework SHA-256：`38d9f4a74db95830d962da9e1a8719ebc0900068baa9322264f60e5df0d9962a`。

从最终 `bin/Vibekits.app` 启动的精确工具桥执行真实只读 `vibekits.mcp.catalog_list` 成功：app=1、local=0、lan=1。局域网节点 `com.newlink.kemiscrollbench:41B8C7FDF4`（`192.168.3.62:9443`）为 online、`catalogState=verified`、`callable=true`，有 1 个空闲执行槽。这同时验证“提供方先启动、VibeKits 后启动”仍可发现并读取能力目录。

## 5. 验收结论

dev.145 解决了公证包 Harness 启动即崩溃的正式发布缺陷，并把真实 Harness MCP 调用提升为公证前硬门禁。单会话永久删除已经按用户定义清理聊天与完整推理执行过程，不再只是移出项目或隐藏入口。

跨平台交互尚有明确后续门禁：dev.145 的 Windows 官方 WebView 入口与 macOS Flutter 入口仍是两套页面。下一版本必须把二者收敛为共享 Flutter 交互/会话/状态机，并将官方 DSH 隔离在版本化 `HarnessEngineAdapter` 后；本报告不把该后续项误写为已完成。
