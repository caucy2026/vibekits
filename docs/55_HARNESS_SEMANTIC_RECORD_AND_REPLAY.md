# Harness 语义 Record & Replay

## 1. 目标

VibeKits Harness 的 Record & Replay 不是传统 RPA 宏。传统宏记录鼠标坐标、按键和等待时间，窗口移动、分辨率变化、数据变化后就容易失效。本功能学习的是：

- 用户真正要完成的目标；
- 哪些输入每次会变化；
- 每一步操作的业务意图和首选 MCP 工具；
- 操作前后的结构化状态与可观察结果；
- 失败时允许的等价工具和停止条件；
- 整个任务最终如何证明完成。

OpenAI 官方 Record & Replay 同样把一次演示转换为可复用 Skill，并在新任务中结合当前 Computer Use、浏览器和插件能力执行，而不是保存固定坐标。本设计沿用“演示生成 Skill”的核心，但把 VibeKits 的三层 MCP 目录、长任务、风险审批和证据闭环纳入强制合同。

## 2. 当前 MCP 接口

### `vibekits.workflow.record_start`

开始一次示教。必填参数：

- `name: string`：稳定、易识别的工作流名称；
- `goal: string`：业务目标，不能写成按钮序列；
- `successCriteria: string[]`：至少一个客观可验证的完成条件；
- `variables[]`：可选的变化输入，每项包含 `name`、`description`、本次非敏感 `recordedValue` 和 `required`。

开始后，Harness 的真实 MCP 工具调用会被捕获为语义步骤。密码、Token、API Key、Cookie、私钥等不得作为变量；活动记录层会继续脱敏。

### `vibekits.workflow.record_stop`

停止示教并原子生成版本化 Skill JSON。可用 `notes` 补充示范画面中没有显式表现的命名规则、默认值、选择分支或禁止事项。没有捕获到工具调用时拒绝生成空工作流。

### `vibekits.workflow.list`

列出工作流 ID、名称、目标、创建时间和步骤数，不读取文件正文之外的数据。

### `vibekits.workflow.prepare_replay`

参数为 `workflowId` 与本次 `inputs`。服务检查必填变量、绑定 `{{variable}}`，返回 Skill 和执行合同。它不会直接机械执行旧动作；Harness 必须：

1. 实时刷新本 APP、本机和局域网 MCP 列表；
2. 按步骤 `intent` 选择当前可用工具，优先 `preferredTool`；
3. 参数遵守本轮工具 Schema，不依赖旧 Schema；
4. 每一步检查 `expectedOutcome`；
5. 工具不可用时可以选择语义等价工具；
6. 写入/控制步骤无法验证时立即停止，不盲目重试；
7. 最后逐项验证 `successCriteria`。

## 3. 存储和安全

Windows 开发、运行和测试数据继续位于 D 盘项目/发布工作目录下的 `.runtime-cache/harness/semantic_workflows`。单工作流最大 2 MiB、最多 200 步；列表最多返回 100 个。文件使用临时文件加原子改名，格式或版本不正确的文件不会执行。

录制授权不等于回放授权。回放调用每个 MCP 工具时仍执行当前 Harness 权限策略；破坏性操作不会因用户曾经示范过一次而永久放行。远程 Harness 发起回放时仍受远程控制审批约束。

## 4. “理解”而非“照抄”的验收标准

同一工作流必须在以下变化中仍能正确完成或安全停止：

- 窗口位置、分辨率和控件坐标变化；
- ADB 序列号、文件路径、日期范围等输入变化；
- 首选工具临时离线但存在等价本机或局域网 MCP；
- 工具 Schema 升级，需要按实时目录调整参数；
- 中间结果与示范不一致，需要重新发现状态；
- 写入步骤无法证明成功，应停止并报告证据，而不是继续后续步骤。

仅能在完全相同界面、相同坐标和相同数据上重放，不算通过。

## 5. 后续界面阶段

当前语义内核和四个 MCP 接口已经可供 Harness 自动调用。下一阶段 UI 在右侧工具轨增加一个紧凑的“示教”入口，显示录制状态、工作流列表、编辑变量/成功标准、试运行和删除；界面只是控制面，Skill 模型和 MCP 合同保持不变，以便 Windows、macOS 和局域网智能体共用。
