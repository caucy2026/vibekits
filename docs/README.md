# Vibekits 统一开发文档

本目录是 Windows/macOS 的统一产品、设计、实现和验收基线。需求变更必须先更新文档与验收编号，再修改代码。

## 阅读顺序

1. [统一产品需求](00_PRODUCT_REQUIREMENTS.md)——最高产品与研发基线
2. [Windows 平台产品附件](00_WINDOWS_PRODUCT_SPEC.md)
3. [Windows 界面布局](01_WINDOWS_UI_LAYOUT.md)
4. [跨平台技术架构](02_TECHNICAL_ARCHITECTURE.md)
5. [统一实施计划](03_IMPLEMENTATION_PLAN.md)
6. [Windows 验收矩阵](04_WINDOWS_ACCEPTANCE_MATRIX.md)
7. [Windows 验收流程](05_WINDOWS_ACCEPTANCE_PROCESS.md)
8. [Windows 模块实现规格](06_WINDOWS_IMPLEMENTATION_SPEC.md)
9. [Windows UI 验收矩阵](07_WINDOWS_UI_ACCEPTANCE_MATRIX.md)
10. [交互与操作习惯规范](08_WINDOWS_UX_CONVENTIONS.md)
11. [开发日志](09_DEVELOPMENT_LOG.md)
12. [当前实现状态与未完成清单](10_CURRENT_IMPLEMENTATION_STATUS.md)
13. [macOS 平台实现附件](11_MACOS_PLATFORM_SPEC.md)
14. [统一验收矩阵](12_UNIFIED_ACCEPTANCE_MATRIX.md)
15. [用户需求总账](13_REQUIREMENT_LEDGER.md)
16. [实验与闭环路径](14_EXPERIMENTATION_PATH.md)
17. [程序员工具版图与移植决策](15_DEVELOPER_TOOL_LANDSCAPE.md)
18. [第三方组件、模型与供应链记录](16_THIRD_PARTY_COMPONENTS.md)
19. [发布完成清单](17_RELEASE_COMPLETION_CHECKLIST.md)——当前唯一执行与验收清单
20. [无歧义原子验收动作](18_ATOMIC_ACCEPTANCE_CASES.md)——前置、动作、唯一预期、失败判定与证据
21. [官方 Harness Web 对齐基线](19_OFFICIAL_HARNESS_WEB_PARITY.md)
22. [跨工具开发工作流](20_INTEGRATED_DEVELOPER_WORKFLOWS.md)
23. [发布质量门禁](21_RELEASE_QUALITY_GATE.md)
24. [能力融合与智能体自动发现最高准则](22_CAPABILITY_INTEGRATION_STANDARD.md)——新增或移植任何工具时必须遵循
25. [创新能力交付路线](23_INNOVATION_DELIVERY_ROADMAP.md)
26. [智能清理产品与架构准则](24_CLEANER_COMPETITIVE_ARCHITECTURE.md)——清理竞品结论、五任务入口、规则数据库和超越路线
27. [Windows 测试节点与 GitHub 受控备份](25_WINDOWS_TEST_NODE_AND_GITHUB_BACKUP.md)——节点生命周期、GitHub 代理回滚和分离审批备份合同
28. [dev.61 Windows 测试节点与 GitHub 备份剩余工作](26_WINDOWS_NODE_GITHUB_BACKUP_REMAINING.md)——helper 实体、关闭工具、Release 门禁和两台 Mac 实证
29. [安全 Windows 测试节点复用指南](27_SECURE_WINDOWS_NODE_INTEGRATION_GUIDE.md)——helper 协议、设备身份、跨设备证据与智能体接入通用设计
30. [dev.58～dev.61 GitHub 备份记录](acceptance/GITHUB_BACKUP_DEV58_DEV61_2026-08-21.md)——备份范围、安全边界和远端核验方法
31. [智能体使用 Windows 测试节点所需工具](28_AGENT_WINDOWS_NODE_TOOL_REQUIREMENTS.md)——已完成工具、缺失 ToolSpec、输入输出、安全边界和验收门禁
32. [Mac 端调用 Windows 测试节点指南](30_MAC_WINDOWS_NODE_CALL_GUIDE.md)——Windows 一次准备、Mac 独立身份、登记、onboarding、验证和撤销调用顺序
33. [Windows 节点智能体工具接口](29_AGENT_WINDOWS_NODE_TOOL_API.md)——Harness/Codex 调用顺序、参数、返回、STDIO 注册和可用性发现
34. [dev.63 外部 Codex MCP 验收](acceptance/V1_9_0_DEV63_CODEX_MCP_2026-08-21.md)——全局注册、77 工具发现、节点调用与 Release 证据
35. [dev.64 清理经验决策引擎验收](acceptance/V1_9_0_DEV64_CLEANUP_DECISION_2026-08-22.md)——同机只读复扫、四级决策、安全边界与性能数据
36. [dev.65 30 项高频微工具验收](acceptance/V1_9_0_DEV65_UTILITY_PLUS_30_2026-08-22.md)——GitHub 能力去重、界面/Harness/日志闭环与性能数据
37. [dev.66 工具集 UI 与智能体接口验收](acceptance/V1_9_0_DEV66_UTILITY_UI_AGENT_2026-08-22.md)——自动可见工具条、小窗口、自带接口 ID 与快捷执行
38. [dev.67 ADB 语义工具与真机验收](acceptance/V1_9_0_DEV67_ADB_SEMANTIC_TOOLS_2026-08-22.md)——Shell、Logcat、文件往返、截图与 APK 安装门禁
39. [dev.68 代理与轻量虚拟机闭环验收](acceptance/V1_9_0_DEV68_NETWORK_VM_CLOSED_LOOP_2026-08-22.md)——真实系统代理恢复、qcow2 创建、QEMU 启停和 Harness 调用
40. [dev.69 Android 真机与 macOS 构建验收](acceptance/V1_9_0_DEV69_ANDROID_MACOS_2026-08-22.md)——arm64 真机性能、进程退出与 macOS 14 Release CI
41. [dev.70 Harness 本地启动性能验收](acceptance/V1_9_0_DEV70_HARNESS_STARTUP_2026-08-22.md)——旧入口纠正、真实分段计时、已完成优化与 3 秒门槛结论

## 完成定义

“代码已写”不等于“功能完成”。一个功能只有在以下条件全部满足后才能标记完成：

1. 产品规格存在唯一验收编号。
2. 实现代码、错误处理和资源释放完整。
3. 自动测试通过。
4. Windows Release 构建通过。
5. 验收矩阵中的人工步骤在目标 Windows/macOS 电脑实际执行并记录结果。
6. 对应 UI 验收编号通过并具有截图或录屏证据。
