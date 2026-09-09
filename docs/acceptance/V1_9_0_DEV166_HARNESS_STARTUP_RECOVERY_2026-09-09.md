# VibeKits dev.166 Harness 启动与异常退出闭环报告

日期：2026-09-09

候选版本：`1.9.0-dev.166+2166`

范围：macOS ARM Release 候选；不包含发布、公证或商场上传结论。

## 用户可见故障

- 进入“智能体（Harness）”后偶发只显示空壳、长时间不工作。
- Harness Node 进程有时会在启动阶段或运行后退出，界面不会自动恢复。
- HTTP 端口已经监听时，旧流程会过早显示“就绪”，但 WebView 内的真实编辑器可能尚未加载完成。

## 根因

### 1. 用户配置目录中的旧模块与内置 fallback 冲突

2026-09-07 至 2026-09-08 的运行日志多次记录以下致命启动错误：

```text
profiles/node_modules/@deepseek-ai/dsh exists and is not a symlink or dsh-managed module proxy
```

旧迁移逻辑仅处理 `package.json` 完整、可解析且名称完全匹配的目录。安装中断、空目录、损坏 JSON 等残缺状态会被跳过，因此每次启动都会在同一点退出，形成稳定复现的崩溃循环。

### 2. 启动成功判定不完整

旧流程只等待 Node HTTP 端口可访问，随后立即标记 Harness 就绪；它没有等待 WebView 首次导航完成。因此“后端监听成功”和“用户能输入并得到响应”之间存在假就绪窗口。

### 3. 运行期退出没有自恢复

旧流程监听到 Node 退出后只更新错误文案，不重启进程。用户只能手工点击重试，偶发退出因此表现为智能体突然不再工作。

## 修复

- 对与内置 fallback 同名、但不是 DSH 管理代理的普通目录进行原子隔离备份。
  - 包括缺失 `package.json`、JSON 损坏及安装不完整目录。
  - 不删除聊天、会话或用户插件；其他名称的用户插件保持不变。
- 启动时同时等待 HTTP 服务与 WebView 首次页面加载完成，二者均成功后才发布 `ready`。
- 初次启动失败自动重试两次。
- 运行期异常退出采用 800 ms、1600 ms、3200 ms 有界退避自动恢复。
- 连续失败超过预算后停止循环并显示明确失败状态，避免后台无限拉起和持续占用 CPU。
- 进程稳定运行 30 秒后重置恢复预算；用户手工重试也会重置预算。
- 页面销毁时取消重启和稳定性计时器，避免退出应用后被旧定时器重新拉起。

## 自动化与真实验收

### 定向自动化

- `harness_legacy_modules_test.dart`
- `harness_startup_recovery_test.dart`
- `harness_shared_ui_contract_test.dart`

结果：`13/13` 通过。

新增覆盖：

- 完整旧模块、缺文件模块、损坏 JSON 模块均被隔离备份。
- 用户自有插件和会话数据不受影响。
- 退避时序、最大次数和稳定后重置行为正确。

### 隔离配置启动验证

最终 App 内置运行时通过独立临时配置复现冲突并执行迁移，结果：

```json
{
  "conflictReproduced": true,
  "backedUpPackages": 1,
  "startupAfterMigration": true,
  "secondStartup": true,
  "userDataModified": false,
  "modelRequests": 0
}
```

### 真实 Release 验收

- macOS Release 构建成功，产物约 792 MB。
- 冷启动后发送 `OK2`，约 3 秒获得 Harness 回复。
- 故障注入：终止 Node PID `68108` 后，应用自动启动新 Node PID `69585`，新服务监听端口 `58077`，Harness 编辑页面恢复可用。
- 最终重建候选启动后，真实会话 `OK3` 已完成模型推理并进入可交互的“等待回答”状态。

## 代码检查边界

本次修改文件的定向 `dart analyze` 结果为 `No issues found`。全仓 `flutter analyze --no-pub` 仍报告 16 项，均位于工作区中原有的未提交远程协助测试/工具改动；本次没有擅自修改这些并行开发内容来掩盖结果。

## 独立遗留项

界面当前仍报告 `Another Harness status publisher is already running`。这是远程状态发布器/中继的单订阅占用问题，与本次本地 Harness Node 启动、WebView 就绪及模型响应链路不同，不影响本次“智能体偶发不工作或退出”的闭环结论，但需要在远程协助功能的独立门禁中继续处理。
