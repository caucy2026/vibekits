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

## 完成定义

“代码已写”不等于“功能完成”。一个功能只有在以下条件全部满足后才能标记完成：

1. 产品规格存在唯一验收编号。
2. 实现代码、错误处理和资源释放完整。
3. 自动测试通过。
4. Windows Release 构建通过。
5. 验收矩阵中的人工步骤在目标 Windows/macOS 电脑实际执行并记录结果。
6. 对应 UI 验收编号通过并具有截图或录屏证据。
