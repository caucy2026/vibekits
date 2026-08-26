# v1.9.0-dev.107 Harness 能力认知闭环验收

日期：2026-08-26  
平台：Windows x64  
版本：`1.9.0-dev.107+117`

## 验收目标

向 VibeKits 自带 Harness 真实提问：“这个 APP 有多少功能，功能模块接口如何调用？”验证模型不是凭记忆回答，而是主动调用 APP 自有工具取得实时注册结果，并能说明工具发现、参数、权限和典型调用链。

## 产品与接口口径

- 产品一级页面：5 个——智能体（Harness）、解压缩、系统清理、文档阅读、开发工具。
- 开发能力条目：78 个。
- 独立开发工作区：18 个。
- Harness 已定义接口：146 个。
- Harness 当前可执行接口：125 个。
- 无执行器缺口：0 个。
- 环境或安全门禁暂不公开：21 个。

这些数字含义不同，不得相加后称为“功能总数”。运行时接口数量始终以 `vibekits.system.capability_check` 和本轮 MCP Schema 为准。

## 实际闭环

1. 使用用户已经在 APP 内保存的 DeepSeek 凭据启动真实模型调用；测试程序不打印、不写入凭据。
2. 只向模型发送 VibeKits 工具名称、数量、描述和参数 Schema。
3. Harness 主动调用 `vibekits.system.capability_check`，工具日志记录为成功。
4. 接口返回 `definedTools=146`、`executableTools=125`、`missingHandlers=[]`，权限分布为只读 92、写数据 10、控制设备 23。
5. 能力检查同时返回产品层级：5 个一级页面、78 个开发能力条目、18 个独立工作区以及业务模块清单，避免模型把页面数误判为未知。
6. Harness 按运行时业务组列出 125 个可执行工具 ID，说明参数以工具 `inputSchema` 为准，并给出 ADB、音频、Git、GitHub 代理、SQLite 等闭环调用链。
7. Harness 输出完成标记 `VIBEKITS_HARNESS_CAPABILITY_INVENTORY_OK`，退出代码为 0。

## 结果

| 检查项 | 结果 |
|---|---|
| 真实模型请求 | 通过 |
| 主动调用 APP 自有能力检查工具 | 通过 |
| 定义/可执行数量一致 | 通过 |
| 所有公开接口均有 handler | 通过 |
| 模块和工具 ID 列举 | 通过 |
| 调用格式、Schema 和权限说明 | 通过 |
| 完成标记和正常退出 | 通过 |
| API Key 脱敏扫描 | 通过，记录中未发现 Key/Bearer |

最终原始脱敏记录保存在构建验收目录：`build/acceptance/capabilities/harness-capability-2026-08-26T07-23-23.667725.log`。该目录不是发布资产，不会打包用户凭据。

## Harness 长期认知来源

- 人类可读且由代码生成的完整目录：`docs/37_HARNESS_CAPABILITY_CATALOG.md`。
- 随 APP 打包的指令源：`assets/harness/AGENTS.md`。
- 启动时自动维护：`DeepSeekHarnessService.prepareHarnessCapabilityInstructions()` 将受控指令块写入 `$DSH_HOME/AGENTS.md`，保留用户自定义内容。
- 运行时真实来源：MCP 工具 Schema 和 `vibekits.system.capability_check`；文档与运行时冲突时以运行时为准。

结论：Harness 已经准确回答 5 个一级页面、14 个业务模块、78 个开发能力条目、18 个独立工作区、146 个定义接口和 125 个可执行接口，并知道统一调用方式；新增工具仍须进入 `ToolSpec` 和执行桥，目录生成测试会阻止文档与代码漂移。
