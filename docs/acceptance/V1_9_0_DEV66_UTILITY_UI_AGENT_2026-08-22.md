# v1.9.0-dev.66 工具集 UI 与智能体接口验收

日期：2026-08-22

## 验收结论

新增 30 项微工具没有形成独立页面或杂乱导航，继续融合在“开发工具 → 转换与检查”的分类 Tab。选中任意工具后，工具名称、说明、参数、输入、结果、主操作和智能体接口均在同一屏完成。

## 本轮交互改进

1. 分类使用顶部 Tab；分类内工具使用紧凑横向选择器。
2. 工具条提供明确的左右按钮，鼠标、触控板和触摸滑动均可使用。
3. 从全局搜索进入深处工具时，当前工具自动滚动到选择器中央。
4. 工具说明右侧显示 `智能体 · vibekits.<id>`；点击复制 Harness/MCP ID。
5. `Ctrl+Enter` 直接执行；底部仍只有一个高强调主按钮。
6. 宽度达到 760px 时输入/结果并排；窄窗口改为上下布局。640×720 Widget 验证无溢出。

## 接口闭环

```text
ToolSpec
  ├─ UI 分类、名称、说明、参数和执行器
  ├─ Harness/MCP tools/list：vibekits.<id>
  ├─ Harness invoke：同一个 run/runAsync
  └─ 开发工具 Harness 活动日志：默认记录、可关闭、可删除
```

界面显示的接口 ID 不是装饰文本；它由当前 `ToolSpec.id` 实时生成，与 Harness 可执行目录完全同源。新增微工具不需要手工维护另一份智能体提示词或接口清单。

## 自动验收

| 项目 | 结果 |
|---|---|
| 640×720 窄窗口布局 | PASS |
| 深处 SemVer 工具初始化并自动可见 | PASS |
| 智能体 ID 显示 `vibekits.semver_compare` | PASS |
| `Ctrl+Enter` 输入→执行→`greater` | PASS |
| 完整开发工具 Widget 回归 | 10/10 PASS |
| 30 项领域代表输入 | 30/30 PASS |
| 30 项 Harness 发现及真实 invoke | PASS |
| 16 个开发工具入口性能 | PASS；转换与检查 307 ms 首开 / 145 ms 热切换 |
| Flutter analyze | PASS，0 问题 |
| Windows Release、自包含及版本 | PASS，`1.9.0-dev.66+76` |
