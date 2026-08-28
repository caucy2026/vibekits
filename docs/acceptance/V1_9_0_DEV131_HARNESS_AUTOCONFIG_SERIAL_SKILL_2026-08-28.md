# v1.9.0-dev.131 Harness 自动配置与串口技能验收

## 验收目标

1. Harness 对可枚举、可检查、可复用或可安全试探的工具配置自动填写。
2. 串口自动识别端口、波特率、数据位、停止位、奇偶校验和流控，不要求用户逐项试错。
3. 协议未知时串口探测只能监听，不得发送测试字节。
4. Harness 能精确列出任意公开工具参数；只有账号/登录身份缺失、秘密、业务目标缺失或破坏性确认才询问用户。

## 实现

- `vibekits.serial.auto_detect`
  - 端口留空时按 USB VID/PID、描述和传输类型自动排序选择。
  - 波特率默认候选：115200、921600、460800、230400、57600、38400、19200、9600。
  - 分阶段尝试 8-N-1、常见帧格式以及 none、DTR/DSR、RTS/CTS、XON/XOFF 和组合流控。
  - 返回 `selected`、`summary`、`confidence`、`attempts`、文本/HEX 样本和下一步动作。
- `vibekits.system.describe_tool`
  - 返回运行版本真实 `inputSchema`，另提供逐参数结构化列表。
  - 参数字段包含名称、类型、是否必填、默认值、枚举、范围和说明。
- 串口技能：`assets/harness/SERIAL_SKILL.md`，同一规则写入并自动更新官方 DSH 使用的 `$DSH_HOME/AGENTS.md`。

## 自动化测试

| 测试 | 结果 |
| --- | --- |
| 自动探测在模拟持续日志中选择 115200 / 8-N-1 / RTS/CTS | 通过 |
| 自动探测不调用 `send` | 通过 |
| `describe_tool` 精确返回串口默认值与全部枚举 | 通过 |
| 143 个当前可执行接口逐项调用 `describe_tool` 并核对原始 Schema | 通过 |
| Harness 能力文档与实际注册表一致并注入 DSH | 通过 |
| Harness 工具桥回归 | 28/28 通过 |
| Windows Release | 通过 |

串口模拟只验证算法和零发送安全边界，不冒充某一台真实硬件已经完成自动探测；真实硬件仍需在它持续输出的窗口执行 `serial.auto_detect` 后核对证据。

## 真实 Harness 问答闭环

最终 Release 以 `--open-harness --webview-debug-port=9333` 启动，向 APP 内官方 Harness 提交只读验收问题。Harness 真实轨迹依次调用：

1. `mcp__vibekits__system__capability_check`
2. `mcp__vibekits__system__describe_tool`：`vibekits.serial.auto_detect`
3. `mcp__vibekits__system__describe_tool`：`vibekits.serial.session_open`
4. `mcp__vibekits__system__describe_tool`：`vibekits.serial.transact`
5. `mcp__vibekits__system__describe_tool`：`vibekits.serial.list_ports`

Harness 回答核对结果：

- 5 个一级页面、14 个业务模块、163 个定义接口、143 个可执行接口，口径未混淆。
- 精确列出 `port / baudRate / dataBits / stopBits / parity / flowControl`；包含 115200、8-N-1 默认值和全部 8 种流控枚举。
- 精确列出 `auto_detect` 的 `baudRates/listenMs` 和 `transact` 的 `data/mode/waitMs`。
- 明确回答不会让用户选择端口、波特率、数据位、停止位、校验或流控；这些由 `list_ports → auto_detect` 自动完成。
- 明确回答只有未保存账号/身份、密码/API Key/Token/私钥口令等秘密、缺失的业务目标和破坏性确认才询问用户。
- 本轮按要求没有打开真实串口。

## 结论

本项验收通过。最新版 Windows 程序为：

`D:\vibecode\vibekits\build\windows\x64\runner\Release\vibekits.exe`
