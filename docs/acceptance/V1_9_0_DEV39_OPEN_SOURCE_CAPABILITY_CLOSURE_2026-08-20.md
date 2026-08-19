# v1.9.0-dev.39 开源能力融合后续项验收

日期：2026-08-20

平台：Windows x64

版本：`1.9.0-dev.39+49`

## 本轮完成项

1. JSON/YAML/TOML/XML 共用结构化查询与安全路径语法。
2. 常见语言类、类型、函数声明的后台只读搜索。
3. 文件搜索默认根 `.gitignore` 常用模式和 smart case。
4. 内置 SHA-256、JSON、Base64 的预热、多轮和百分位基准。
5. 全部能力由 `ToolSpec` 自动注册到 Harness、模型选择描述和模块日志。

## 边界

- 结构化查询是安全常用子集，不支持任意 jq/yq 程序或原地改写。
- 代码结构搜索是声明级索引，不冒充 tree-sitter、编译器 AST、LSP 引用分析。
- `.gitignore` 支持根目录常用 glob/目录/否定规则；不宣称覆盖 Git 的全部嵌套规则细节。
- 性能基准不运行 shell、外部程序、清缓存或提权操作。

## 自动验收

| 检查 | 结果 |
|---|---|
| JSON/YAML/TOML/XML 真实查询 | PASS |
| 代码声明真实文件定位与忽略构建目录 | PASS |
| `.gitignore` 与 smart case | PASS |
| 性能预热、多轮、百分位与任意命令拒绝 | PASS |
| Harness 目录发现与真实调用 | PASS |
| 定向回归 | 48/48 PASS |
| Flutter Analyze | 0 问题 |

## 发布结论

机器报告：`build/acceptance/20260820_035007_release_acceptance.md`

| 发布检查 | 结果 |
|---|---|
| 正式任务链清单 | 14 条，PASS |
| 开源能力收口专项 | PASS |
| Harness 全桥回归 | PASS |
| 全量 Flutter Analyze | 0 问题 |
| Windows Release | 构建成功 |
| 自包含运行时/模型 | 17/17 |
| FileVersion / ProductVersion | `1.9.0-dev.39+49` |
| EXE SHA-256 | `FD3DFB2DA82268B9321902040C8DDC08E5BA81CD74A8FB54D81F9D0D1DD2731F` |

结论：上一版文档列出的 yq/ast-grep/hyperfine/ripgrep-fd 后续融合项，均已按安全、有界、不孤立的产品边界在 dev.39 收口。
