# Vibekits Android APK 长时间压力任务设计

## 目标

Vibekits 必须让 Harness 或任意外部 MCP 智能体，仅通过产品接口完成以下闭环：

1. 下载并验证 APK；当前Windows工作站的文件、缓存、日志和报告全部位于D盘，macOS使用绝对工作区目录。
2. 自动把设备别名 `53` 解析为 `192.168.3.53:5555`，连接后核验真实设备身份。
3. 自动枚举并识别设备串口，打开独立长连接，发送经过授权的控制台命令并持续读取日志。
4. 每轮删除目标包、全新安装、启动 Activity、检查 PID 和 `boot_id`。
5. 自动识别卡死、ADB 离线、系统重启、应用崩溃、ANR、Watchdog、解码器、Wi-Fi HAL 和 SELinux 异常。
6. 异常时采集串口尾部、Logcat、线程、Activity、Window、包状态、pstore 和 dmesg，并调用 Git 接口记录源码状态。
7. 原始证据只保存在本机 D 盘；智能体只读取有界摘要、证据路径和修复建议。

## MCP 接口

### `android__apk_install_stress_start`

立即返回，不等待100轮结束。

| 参数 | 类型 | 必填 | 约束与语义 |
| --- | --- | --- | --- |
| `serial` | string | 是 | ADB serial、IPv4或尾号；`53` 自动转换为 `192.168.3.53:5555` |
| `apkPath` | string | 二选一 | D盘本地 APK 绝对路径 |
| `apkUrl` | string | 二选一 | HTTP/HTTPS APK；通过 `vibekits.network.download` 下载和校验 |
| `downloadDirectory` | string | URL时可选 | Windows当前工作站必须在D盘；macOS使用绝对工作区目录；默认 `<APP工作目录>/tmp/downloads` |
| `serialPort` | string | 否 | 如 `COM33`；省略时调用串口枚举和自动探测 |
| `rounds` | integer | 否 | 1..100，默认100 |
| `sourceRoot` | string | 否 | D盘Git源码目录；异常时调用 `vibekits.git.inspect` |
| `packageName` | string | 是 | 目标Android包名；KEMI-PAD为 `com.newlinksz.kemi.remote` |
| `mainActivity` | string | 否 | 完整组件名；省略时安装后通过Package Manager自动解析 |

返回：`taskId`、`phase`、时间和轮次进度。`phase` 为 `queued/running/completed/failed/cancelled`。

### `android__apk_install_stress_status`

参数：

- `taskId`：`start` 返回的任务ID，必填。
- `waitSeconds`：0..45，默认20。任务运行时应持续查询同一个ID，禁止重复调用 `start`。

完成后返回有界汇总、异常计数、修复建议、JSONL明细路径和summary路径。

### `android__apk_install_stress_cancel`

参数仅为 `taskId`。设置取消标记，在当前卸载/安装/启动原子步骤结束后停止，关闭ADB和串口会话并保留证据。

### `android__apk_install_stress_100`

旧版同步兼容接口。保留已有调用方，但新智能体任务必须使用 `start/status/cancel`。

## Harness 调用策略

1. 调用 `vibekits.system.capability_check` 和工具描述接口。
2. 调用 `start`，保存唯一 `taskId`。
3. 以 `waitSeconds=20` 调用 `status`；运行中继续查询同一任务。
4. 发现 `failed/cancelled` 时读取报告路径和错误，不盲目重新开始。
5. 用户要求停止时调用 `cancel`。
6. 正式100轮前先用 `rounds=1` 执行门禁；门禁成功后才启动100轮。

## 异常判定和建议

| 分类 | 主要证据 | 默认处置 |
| --- | --- | --- |
| reboot | boot_id变化、Booting Linux、sys.powerctl | 立即停止，采集pstore/dmesg/串口尾部 |
| crash | FATAL EXCEPTION、Fatal signal | 保存2000行Logcat和exit-info |
| anr | ANR in、am_anr | 保存线程、Activity和Window状态 |
| watchdog | WATCHDOG KILLING SYSTEM PROCESS | 按系统级故障停止并保存现场 |
| decoder | OMXVDEC、decoder error | 检查缓冲区校验、空帧和解码器重建时序 |
| wifiHal | WifiVendorHal ERROR_UNKNOWN | 检查HAL错误处理和ADB退避重连 |
| selinux | avc: denied | 补最小策略或降级使用公开指标 |

自动建议只是定位入口，不应宣称已经修复源码。源码修复必须有具体仓库、日志调用栈、diff和重新编译后的复测证据。

## 验收标准

- 1轮门禁和100轮正式任务都由Harness调用MCP完成。
- 100轮中每轮均有卸载、安装、启动、PID、boot_id和串口监控记录。
- APP重启或MCP客户端短暂断开后仍可查询任务；若当前实现进程退出会丢失任务，必须在发布验收前增加任务状态落盘恢复。
- 用户取消后不再开始下一轮，并关闭所有会话。
- 模型响应不得包含完整原始串口或Logcat；只返回计数、尾部摘要和D盘证据路径。
- 最终报告明确区分事实、推断、建议和未验证项。
