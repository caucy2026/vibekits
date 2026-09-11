# VibeKits v1.9.0-dev.173 高级能力与集群任务基线验收记录

## 1. 本轮范围

本轮依据 `docs/66_ADVANCED_DEVICE_AND_CLUSTER_TASK_CENTER_REQUIREMENTS.md` 对远程协助、局域网仿真机、集群任务中心、Harness 右侧快捷栏和能力 MCP 做统一梳理。既有 dev.172 的 Harness 白屏修复、官方插件市场、项目/会话和工具执行链保持不变。

## 2. 需求对照

| 需求 | 代码落点 | 自动测试 | 结论 |
|---|---|---|---|
| 高级设置在低高度窗口自动缩小 | `lib/app/main_shell.dart` | `widget_test.dart` 1024×600、200% 缩放 | 已通过 |
| Harness 右栏按钮不被底部遮挡 | `official_harness_workspace.dart` 使用可滚动 `ListView`；备用跨平台界面沿用同结构 | `harness_shared_ui_contract_test.dart` | 已通过代码/契约测试；待 Release 真窗口点击 |
| 高级页点击后立即显示，不等待网络身份探测 | `HarnessRemoteShareDialog` 先渲染 loading host，再局部刷新 | 低高度 Widget 用例 | 已通过 |
| 远程、仿真、集群统一页面且独立授权 | “设置 → 高级”三个独立区块 | Widget + 既有 remote/simulator state tests | 已通过本机状态层 |
| 智能体优先说明三项高级能力 | `harnessCapabilityInstructions` + `vibekits.advanced.capabilities` | `harness_tool_bridge_test.dart` | 已通过 |
| MCP 可查询/开关远程与仿真 | `harness_tool_bridge.dart` | 目录、风险与能力检查 | 接口完成；真连接仍按双机门禁验收 |
| 集群任务默认关闭、只接受 HTTPS/可信域/签名 | `cluster_task_settings.dart`、`cluster_task_protocol.dart` | settings/protocol tests | 已通过领域层 |
| 集群任务联网登记、心跳、发现、认领、回传 | 尚无确定服务地址、认证协议、签名算法/公钥 | 无法做真实服务闭环 | 未完成，不能宣称可用 |
| 新增模块不阻塞 Harness | 高级页面局部异步；MCP capability 不读取钥匙串；集群无启动钩子 | Harness/UI 回归 | 已通过自动回归；待 Release 冷启动计时 |

## 3. 本轮测试结果

- `/Users/newlink/flutter/bin/flutter analyze --no-pub`：0 issue。
- `cluster_task_settings_test.dart`：默认关闭、配置门禁、HTTPS、可信域、公钥脱敏。
- `cluster_task_protocol_test.dart`：可信 URL、去重键、过期、非可信域、坏签名。
- `harness_tool_bridge_test.dart`：高级 MCP 目录、风险等级、能力自检与既有工具回归。
- `harness_shared_ui_contract_test.dart`：官方/备用右栏可滚动、官方插件市场保留、远程层不替换 Harness。
- `widget_test.dart`：1024×600、200% 文字缩放，高级页可滚动到集群配置并无溢出。
- `deepseek_harness_test.dart`：运行/停止、项目/会话、独立草稿、并行会话和远程只读状态回归。

相关七个测试文件最终合跑：104 项通过、1 项按原条件跳过。

macOS Release 编译通过，产物为 `build/macos/Build/Products/Release/Vibekits.app`（约 853 MiB）；Info.plist 为 `1.9.0.173 (2173)`，主程序架构为 `x86_64 arm64`，`codesign --verify --deep --strict` 通过。当前构建为临时签名、`TeamIdentifier=not set`，不能当作 Developer ID 正式发布包。真实启动截图：`/private/tmp/vibekits-dev173-release.png`，界面底部显示 `v1.9.0-dev.173+2173`，Harness 主界面和右侧栏均完成渲染。

## 4. 安全与解耦结论

1. 集群任务信封只允许保存任务描述 URL 和元数据，不能携带可直接执行的命令。
2. URL 必须为无账号、无 fragment 的 HTTPS，host 必须精确命中可信域，且必须通过注入的签名校验器。
3. 在后端契约和真实签名校验器接入前，UI 的接收开关保持禁用；MCP 打开请求返回明确错误，不伪报成功。
4. 集群代码当前没有 App 启动钩子、网络轮询或 Harness 依赖，所以未使用时不会增加 Harness 冷启动链。

## 5. 下一阶段输入与门禁

后端需冻结并提供：生产/测试服务 HTTPS 地址、注册认证方式、设备短期凭证刷新、任务信封 JSON 样例、签名算法与公钥、可信任务域、认领幂等和状态回传接口。收到后实现独立 `ClusterDeviceAgent`，再完成：断网、坏签名、过期、重复、撤销、Harness 停止、真实 URL 解析及双设备任务闭环。

dev.173 目前是开发候选，不是正式发布：尚需 Developer ID 正式签名/公证、真窗口逐按钮点击、Windows 真机构建，以及集群后端闭环（若本次发布范围包含集群联网）。
