# Vibekits Windows 开发文档

本目录是 Windows V1 的产品、设计、实现和验收基线。需求变更必须先更新文档与验收编号，再修改代码。

## 阅读顺序

1. [Windows V1 产品规格](00_WINDOWS_PRODUCT_SPEC.md)
2. [Windows 界面布局](01_WINDOWS_UI_LAYOUT.md)
3. [技术架构](02_TECHNICAL_ARCHITECTURE.md)
4. [实施计划](03_IMPLEMENTATION_PLAN.md)
5. [Windows 验收矩阵](04_WINDOWS_ACCEPTANCE_MATRIX.md)
6. [Windows 验收流程](05_WINDOWS_ACCEPTANCE_PROCESS.md)
7. [Windows 模块实现规格](06_WINDOWS_IMPLEMENTATION_SPEC.md)
8. [Windows UI 验收矩阵](07_WINDOWS_UI_ACCEPTANCE_MATRIX.md)
9. [Windows 交互与操作习惯规范](08_WINDOWS_UX_CONVENTIONS.md)
10. [开发日志](09_DEVELOPMENT_LOG.md)
11. [当前实现状态与未完成清单](10_CURRENT_IMPLEMENTATION_STATUS.md)

## 完成定义

“代码已写”不等于“功能完成”。一个功能只有在以下条件全部满足后才能标记完成：

1. 产品规格存在唯一验收编号。
2. 实现代码、错误处理和资源释放完整。
3. 自动测试通过。
4. Windows Release 构建通过。
5. 验收矩阵中的人工步骤在当前 Windows 电脑实际执行并记录结果。
6. 对应 UI 验收编号通过并具有截图或录屏证据。
