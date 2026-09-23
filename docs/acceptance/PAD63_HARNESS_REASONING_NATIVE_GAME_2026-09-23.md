# PAD63 Harness 推理与原生打地鼠验收标准

日期：2026-09-23。目标设备：PAD63（VibeKits ID `6795854383`，ADB `192.168.3.63:5555`）。本文件的六项要求均以 PAD 真机、当前安装包和 Harness 会话记录为准；源码存在、工具链已安装或控制端代编译均不等于通过。

真机当前安装：VibeKits `1.9.0-dev.232` / versionCode `2232`；打地鼠包 `com.vibekits.whacdemo` 的 `pm path` 存在。测试包未作为商城正式包发布。下表保留此前阶段结果；最新复验见末节。

| ID | 用户要求 | 可执行验收标准 | 当前结果 |
|---|---|---|---|
| PAD-HARNESS-01 | PAD Harness 新建会话，由它设计图标、生成原生打地鼠 APK，在 PAD 本机编译、安装、运行 | 新会话记录含 PAD Harness 发出的源码/图标写入、设备端编译、签名、安装、启动工具调用；`pm path` 能找到游戏包；前台 Activity 为游戏；九宫格、倒计时、计分、重玩真实可操作。禁止用 Mac 编译或代装。 | **部分通过**：PAD 会话 `session-1790147991127877` 写入原生 Java/Manifest/自设计图标，PAD Harness 调用设备本地 `/build`，本地九步编译、签名、安装、启动均 exit 0；游戏包 `com.vibekits.whacdemo` 已安装。构建依赖临时 Termux 桥，尚非默认 APK 内置能力；计分/重玩未正向确认，因此整体 BLOCK。 |
| PAD-HARNESS-02 | 推理呈现与原版同样清楚，有过程、进度、结果；避免满屏多处转圈 | 对真实流式模型响应，前台会话显示非伪造的 `reasoning_content`、工具步骤和最终结果；运行中可见增量，完成后可回看；切换会话不串流，取消后结束状态准确。运行时会话正文最多一个主要转圈动画，侧栏、顶部和底部用静态状态标记。未收到推理内容时明确区分模型未返回与 UI 故障。 | **部分通过**：dev227 真机新会话算式任务 9 秒完成，真实工具轨迹、最终结果 143 可见并持久化；PAD 运行态侧栏/顶部/底部改为静态状态，正文保留主进度动画。该次模型未返回独立 `reasoning_content`，不能用工具轨迹冒充推理文本；取消与切会话并发仍待真机复验。 |
| PAD-HARNESS-03 | 分析并优化推理 CPU、内存占用 | 记录同一任务的基线、运行峰值、结束后 CPU/PSS、采样时间和进程；长输出不因逐 token 全量复制/渲染导致持续高 CPU、失控内存或 ANR；与修改前数据对比。 | **部分通过**：dev227 真实 36 秒长任务 `session-1790150289535771` 完成（cursor 61）；采样进程 PID 16534，空闲/运行/结束 PSS 324545/327286/303890 KB，运行中一次 CPU 103%，随后及完成后 0%。旧版另一长任务曾约 148% CPU、PSS 最高约 1.5 GB；任务不同，不能当同任务性能提升比例。 |
| PAD-HARNESS-04 | 63 号 PAD 前台能看到 Harness 真正推理和执行记录 | PAD 前台为 VibeKits Harness 的目标会话；远程命令出现在该会话聊天/时间线；通过会话状态和历史游标核对每步，不能只提供控制端 MCP 调用；后台安装工具链不算 PAD Harness 在工作。 | **通过当前任务范围**：dev227 前台目标会话真实显示算式任务的工具步骤和结果，远端状态 completed、cursor 10；本机游戏会话保存 8 条消息及最后的设备构建核对结论。 |
| PAD-HARNESS-05 | 降低 Harness CPU 占用，长任务不能卡死 | 对长代码生成/多轮工具任务按时间采样 VibeKits 进程 CPU、PSS 与 UI 响应，记录峰值和完成后的回落；任务可取消、切会话后其他会话可交互；无 ANR、持续高 CPU 或无界增长。旧问题触发流程必须成为回归用例。 | **部分通过**：36 秒真实流式长任务正常 completed，CPU 回落 0%，PSS 回落约 23 MB，最近 3000 行 logcat 未见该包 ANR/FATAL；本轮采样非连续峰值，取消和并发切会话未验，不能宣称全场景不卡死。手动回归入口 `test/manual_pad63_long_reasoning_test.dart`。 |
| PAD-HARNESS-06 | 基于系统权限远程 ADB PAD | 仿真开关启用后，独立控制端仅经 VibeKits 已授权 P2P/relay 隧道连接 PAD 的固定本机 ADB 端口，跨网执行 `getprop` 与安装/调试权限测试；重启后复测。设备端系统权限只用于启动/维持 adbd，不假定主 App UID 10091 自动获得 root；关闭仿真后远端无法继续访问。不得影响 Mac/Windows/Linux。 | **部分通过**：dev227 冷启动后仿真 32147/32148 端口就绪，强制 HBBR 隧道远程 ADB 的 `adbReady` 和 `getprop ro.product.model` 通过。PAD adbd 原已在 5555 监听；端口关闭时由系统 UID 自动启动尚未实现/验证。主 APK UID10091 无 `nlsu` 权限，不能据此声称系统权限自启动。 |

## 验收证据要求

- 记录 VibeKits 包版本、签名、目标设备身份、会话 ID、游戏 APK 路径与签名指纹。
- 每项保存正向断言及失败记录；连接拒绝、超时、编译错误不得被测试脚本的“正常返回”误记为通过。
- 游戏编译流程由 PAD Harness 会话触发；构建工具可作为设备端基础设施，控制端不得直接执行游戏编译、安装或启动步骤。
- 最终只报告 `PASS` 或 `BLOCK`，并逐项列出证据与缺口；本文件不是发布许可。

## 本轮实现与范围

- dev227 修复仿真控制端口先成功、第二端口失败时首端口未关闭造成的重试死循环；回归用例覆盖该故障。真实 PAD 冷启动后两个监听端口均恢复。
- PAD 推理界面删去侧栏、顶部、底部三处重复动态圈，静态状态仍标明任务运行；只保留会话正文的主进度动画。模型流式输出仍以服务端实际字段为准。
- 移动端模型调用遇到 429/502/503/504 时只有限重试两次，401/403 立即结束；假服务端回归覆盖一次 503 后成功。此修复针对打地鼠任务曾真实遇到的 DeepSeek 503。
- 本轮测试用的 Termux/loopback 构建桥不是正式可下载组件；未完成前不得把 PAD 原生 APK 制作标为默认即用。平台签名的 system-UID ADB 辅助组件也未交付，`xtqx.md` 明确的普通应用 UID 与 system UID 限制仍存在。

## dev228：Key、模型名称与长推理修复

- 最终候选包 `1.9.0-dev.228` / `2228`，APK SHA-256 `ee09579e17488eac171f33e80abd366fc8152b42f4f95b6da5e0a0600f8bbff9`，v2 签名证书 SHA-256 `c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8`。PAD63 覆盖安装、前台启动成功，实际包版本与候选一致，未见该包安装后 ANR/FATAL。真机 Harness 新任务 8 秒完成，状态 `completed`、游标 8。
- 安全存储读取期间 Key 状态改为中性的“系统检测中”；只有读完并确认没有 Key 才提示填写。若读取失败而无法确认，保持中性；收到明确 401/403 认证失败仍提示真实错误。
- PAD 模型选项与输入框显示 `deepseek-official/<真实模型 ID>`；保留 Mac 截图里的兼容别名 `deepseek-v4-flash-vision-exp` 可选。实际请求使用所选原始 ID，未把显示前缀发送给 DeepSeek。当前新 API 默认 ID 仍为 `deepseek-flash`，没有伪称它就是旧别名。
- 旧 `8 MiB` 错误来自 PAD 自己的 SSE 累计字符数检查，不在 Mac 的官方 Harness 启动路径。现移除 PAD 整次推理流累计上限；单条异常事件、回复正文和工具参数仍做独立内存保护。推理持续流向界面；超过显示窗口后滚动保留最新过程，不让 UI 停在最早的 40K 字。假服务端发送超过 64 MiB 推理流后仍返回最终结果，回归通过。
- 相关 `flutter analyze` 0 issue；`test/deepseek_model_discovery_test.dart` 与 `test/deepseek_harness_test.dart` 合计 38 项通过。Mac 官方 Harness 内部的独立限制未在本仓库证明，不能把 PAD 旧 8 MiB 数值归因于 Mac。

## dev230：原生打地鼠效果与系统 UID ADB 组件

- PAD Harness 会话 `session-1790154945164833` 调用设备本地构建桥，`compile_resources`、`compile_java`、`create_dex`、打包、签名、验签、安装、启动八步均返回 0。游戏原生源码保存于 `examples/pad63-whac-a-mole/WhacActivity.java`；九宫格运行时每次触摸出现短时锤击，命中时锤头目标按地鼠头部位置计算，局部裂纹从 120 ms 后展开，到 1400 ms 缩回并淡出。真机真实触摸后 `best_score=130`，证明命中与计分持久化；动画逐帧视觉验收和重玩仍待设备恢复后复测，不能标为全项通过。
- 现有 PAD63 主包曾覆盖安装到 `1.9.0-dev.229` / `2229`，设备确认 `android.permission.INSTALL_PACKAGES: granted=true`。该包中嵌入 7.5 KB 的同证书系统 UID 辅助 APK；先前辅助 APK 独立安装到 PAD63 后实测 UID 1000，签名权限限定的启动广播返回 `adbd requested on TCP 5555`。这只证明组件安装和已运行 adbd 的幂等请求，不能证明冷态自动恢复。
- 冷态验收中先卸载测试辅助 APK，再停止 PAD63 的 adbd，并尝试重启主 App。设备端预置的独立 55 秒兜底脚本没有恢复端口，`192.168.3.63:5555` 持续拒绝连接；该次测试 **FAIL**，不得被“P2P 仍在线”覆盖。VibeKits 内置仿真连接仍为 `connected=true`、`mcpReady=true`，但 `adbReady=false`、`sshReady=false`；Android 端 `device.logs`、`app_control`、`ssh_identity` 明确返回桌面专属、不可用。远端 SSH 执行返回 `ssh_not_ready`。目前不能继续对 63 做 ADB 真机安装与冷态复测，需要本机恢复网络 ADB 或重启设备。
- 后续候选 dev230 把辅助 APK 作为约 9 KB 内置组件，在开启仿真时先安装/升级到组件 v2；通过签名权限通知 UID 1000 设置 5555 和启动 adbd，再开放原生隧道。组件保存用户启用状态，开机广播仅在该状态为真时恢复；关闭仿真时撤销状态并只停止组件自己启动的 adbd；运行中端口掉线时关闭原生门禁、重试启动后再开放。主 App 不迁移到系统 UID，桌面路径不走此逻辑。dev230 已完成签名编译、证书/清单/内置组件检查和 11 项仿真状态机测试；**尚未安装到 PAD63，冷态、重启后、关闭撤销以及跨网 ADB 均 BLOCK**。
- 本轮总体判定 **BLOCK**。只有 63 恢复后装入 dev230，依次完成“原有 5555 关闭→开启仿真自动安装/启动→跨网 ADB 命令→关闭撤销→重启恢复”和游戏动画/重玩真机实测，才能给出合格报告。

## dev232：PAD 会话冷启动恢复与双屏调试

- 真机覆盖安装 `1.9.0-dev.232` / `2232`，APK SHA-256 `99d6ece9b283d2402e0ff4c24a92efb0fd4733da0ed36ad634f107d5858e167a`。原打地鼠会话所在的私有 JSON 在修复前已是 `sessions: []`；未发现完整聊天备份，不能声称恢复原文。设备构建记录与原生游戏源码仍在。
- 根因：默认工作区的编辑框实际路径非空，但启动恢复曾使用可为空的 `widget.initialWorkspace`；加载未完成时关闭窗口还可能把空会话快照写回原文件。现在从实际工作区恢复、等同一加载完成后才允许提交任务、未加载完成禁止保存空快照。增加恢复和关闭竞态回归。
- 真实 UI 复验：在 PAD Harness 建立 `session-1790161281297150`，私有会话文件先有用户消息，任务完成后有 2 条消息和 4257 字符的回复。`am force-stop` 后重新启动，侧栏与正文均显示原任务和回复。无共享目录复制用户会话文件。
- 双屏复验：设备的 display 0 `mResumedActivity` 为 `com.vibekits.vibekits/.SingleScreenActivity`，display 2 为 `com.vibekits.whacdemo/.WhacActivity`；Harness 冷启动恢复后两者仍同时处于前台。设备本地打地鼠构建桥的 `launch_game` 已指定 `am start --display 2`。PAD 本地触发完整编译，资源、Java、DEX、打包、签名、验签、安装、第二屏启动八步退出码均为 0；随即检查两屏仍分别是游戏与 Harness。本轮触发来自设备控制端，未让 PAD Harness 再次发出 `/build` 调用，因此 Harness 到双屏构建的端到端链路仍待复测。
- `flutter analyze` 修复文件 0 issue；`test/deepseek_harness_test.dart` 全部 34 项通过。ADB 辅助组件曾实测在 adbd 停止后约 8 秒恢复，但跨网隧道、关闭撤销、重启后的全链路 ADB 尚未验完，原六项总验收仍为 **BLOCK**。
