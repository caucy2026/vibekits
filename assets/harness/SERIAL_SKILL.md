# VibeKits 串口自动配置技能

目标：Harness 在不要求用户猜硬件参数的前提下，找到真实串口、配置连接并用日志闭环。

1. 调用 `vibekits.serial.list_ports`，读取端口名、USB VID/PID、描述和传输类型。
2. 调用 `vibekits.serial.auto_detect`。`port` 可留空；即使有多个端口也按 VID/PID、描述和传输类型自动排序选择，不询问用户猜端口。默认依次尝试常用波特率，再试帧格式和全部流控组合。
3. 精确参数以 `selected` 为准：`baudRate`、`dataBits`、`stopBits`、`parity`、`flowControl`。探测过程只监听，不发送未知协议内容。
4. 持续数据使用 `vibekits.serial.session_open`，随后循环 `session_read`；只有协议已知时才调用 `session_write`。
5. `receivedBytes=0` 时把 `listenMs` 提高后重试，并保留 `attempts` 证据。不得让用户逐项尝试波特率或波控。
6. 需要解释参数时调用 `vibekits.system.describe_tool`。枚举值和默认值以运行时 Schema 为准。
7. 完成后关闭会话；对应串口工具页必须存在可删除的 Harness 真实调用日志。

安全边界：串口参数不是秘密，应自动配置；账号、密码、API Key、Token 和私钥口令由用户提供。协议未知时禁止主动发送探测字节，避免误触发设备命令。
