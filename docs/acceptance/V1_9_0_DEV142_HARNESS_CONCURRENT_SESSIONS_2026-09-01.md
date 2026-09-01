# VibeKits 1.9.0-dev.142 Harness 多会话并行验收

日期：2026-09-01

## 验收目标

1. 会话 A 推理时可切到会话 B，B 的输入框与发送按钮可用。
2. B 能启动第二个 Harness 任务；A/B 的输出、停止、时间线和未发送草稿互不影响。
3. 只有选中的项目/会话显示 `…`；未选中的运行项显示转圈；未选中空闲项不显示右侧操作。
4. 完成其中一个任务不得把全局 Harness 误报为空闲；最后一个任务结束后才恢复 ready。

## 自动化证据

- `flutter test --no-pub test/deepseek_harness_test.dart`：21/21 通过。
- 新增定向用例：`同一项目的两个 Harness 会话可独立并行运行`。
- 跨项目用例同时断言：源项目运行时只显示转圈，目标选中项目显示菜单，两个任务均能启动。
- `flutter analyze --no-pub`：0 issues。

组合回归 `deepseek_harness + harness_work_status + harness_tool_bridge + mcp_commander_scheduler`：69 项通过，1 项平台条件跳过。全仓套件还执行到 601 项通过、13 项跳过、49 项失败；失败集中在当前测试环境缺少内置 Git/7-Zip/Windows Node、未开启真机门禁、平台专属清理规则与串口超时。本次修改相关用例无失败，但不将全仓套件记为全通过。

## Release 运行态证据

- 版本：`1.9.0-dev.142+2142`；macOS Bundle `1.9.0.142 (2142)`。
- 正式路径：`/Volumes/ORICO/newlink-new/vibekits/bin/Vibekits.app`。
- 运行 PID：`34058`；UDP `*:47831` 监听正常。
- 使用 `tool/sign_macos_release.sh` 逐项签署并验证 20 个 Mach-O；App 启动后再次执行 `codesign --verify --deep --strict` 通过。
- App executable SHA-256：`13cf32f34fe4086d24073b3166235fb3da6a3dbbf72daabf9c78d744c143e318`。
- App.framework SHA-256：`27444edaf63d4335143ba8d6c83087225acf64de48bbf2a183300b7db8b41de3`。
- 内置 ADB SHA-256：`8c2672e2a9aa6ab6efec787195a54451b66f3a3043c4f27d1ef67f7b339e6970`。
- 截图：`/private/tmp/vibekits-dev142-final-running.png`。截图显示页脚与侧边版本均为 dev.142+2142，选中项目/会话显示 `…`，未选中空闲项不显示操作按钮。
