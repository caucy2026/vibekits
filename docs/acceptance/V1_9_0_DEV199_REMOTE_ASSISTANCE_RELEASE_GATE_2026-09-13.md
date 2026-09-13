# VibeKits dev.199 远程协助发布门禁

日期：2026-09-13  
版本：`1.9.0-dev.199+2199`  
代码提交：`9451cf405f97e3bc66e4ff075db51c58b9f8e501`  
RustDesk 传输提交：`6b90c3ae6`  
结论：**BLOCK，尚未发布**

## 本轮验收口径

只有下列闭环全部留下真实证据，才允许把候选标为通过：

1. 控制端只输入统一设备 ID，首次由目标端明确批准证书和工作区范围；记住后使用相同证书安全重连。
2. 默认 P2P 与强制 HBBR 分别完成连接、传输和断开，记录实际传输模式；断开后原生连接表和本地隧道均清空。
3. 同步目标端真实项目、会话与历史；发送命令后收到反馈，并能独立停止。
4. 远程仿真能读取进程，执行严格主机指纹校验的 SSH 命令，上传文件并在两端核对 SHA-256。
5. macOS 与 Windows 使用同一领域逻辑；63/75 真机状态单独记录，离线设备不得记为通过。
6. 最终交付字节必须与验收字节一致；macOS 需 Universal、macOS 12+、Developer ID、公证、staple 和 Gatekeeper 全部通过。

## 已取得的真实证据

### 精确 macOS 候选

- 隔离门禁目录：`/Volumes/ORICO/kemi-build-cache/app-release-gate/vibekits/macos/1.9.0-dev.199+2199-20260913-a`
- 源码归档：`source-9451cf4.tar`
- 源码归档 SHA-256：`effe17aee5b73bbcf69e7090cf89795fd6872645410caa4da925e230fceb698c`
- App：`source/build/macos/Build/Products/Release/Vibekits.app`
- App 主可执行 SHA-256：`4ba1d109f0b01d91870e93617658f865c8435d4634dbb6447789b03d9145c6d9`
- Relay SHA-256：`5106137843e76a5e5bb88e39f42faa5622fc3c6b4956806c926ede066639b9b6`
- App 与 Relay 均为 `x86_64 + arm64`；全功能 macOS 12+ 兼容门禁通过。
- 精确候选已使用 `Developer ID Application: zhen ji (26T5WV4GLP)` 从内到外签署 `36` 个 Mach-O，Hardened Runtime、时间戳和 Team ID `26T5WV4GLP` 均通过。
- Apple 公证 submission `0f738b1b-cb2a-480e-9c0e-9935beca05d6` 返回 `Accepted`；staple、stapler validate、严格 codesign 与 Gatekeeper 均通过，Gatekeeper 来源为 `Notarized Developer ID`。
- 签名后主程序 SHA-256：`004e3590539e2edd55d75bf828821a74a904a2690865623256b4d6b8f88a1dd3`；签名后 Relay SHA-256：`e4ce541fc25adcf6eda0b6903a66c8032d4df5c55deee3fbc25cee56362d079e`。
- 最终 ZIP：`delivery/Vibekits-1.9.0-dev.199+2199-macOS-universal-notarized-20260913.zip`，SHA-256：`224718b6bb05fb78ad3bd0345a6bd6aff2ba3af3e8bf97c859e79e752082b256`。

### 本机载体与首次配对到达

- 包内 Relay 原生命令 `--vibekits-harness-remote-assistance-access 1` 返回 `ok=true`。
- Relay 曾确认 `routingId=1554650784`、`callable=true`、`rendezvousOnline=true`、`registrationKeyConfirmed=true`、`state=registered`。
- VibeKits 打开远程协助后，`127.0.0.1:32145` 配对端点和 `127.0.0.1:32146` 会话端点由精确 App 进程监听。
- PAD 75（控制 ID `9464730211`）只输入目标 ID `1554650784` 后，目标端 `32145` 出现真实 `ESTABLISHED` 连接，并显示包含调用方 ID、证书摘要和工作区范围的批准卡片。
- 尚未执行“确认并记住”：持久访问授权需要操作发生时的用户确认，因此证书持久化、项目/会话和命令闭环仍未通过。

### 自动回归与静态检查

- 全量 Flutter：`859` 通过、`0` 失败、`21` 显式跳过，退出码 `0`。
- 全项目 `flutter analyze --no-pub`：`0 issue`。
- 先前远程相关定向组合：`152` 通过、`0` 失败、`1` 个环境跳过。
- Rust macOS 库测试：`6` 通过、`0` 失败；相关三文件 rustfmt 通过。
- macOS 官方内置 Harness 真实进程测试再次通过：本地模型端点收到真实请求，Harness 完成 SHA-256 MCP 工具调用、原生批准命令、最终反馈和正常退出，`1/1` 通过。随后将隔离测试源码的 runtime 临时指向“已签名、公证、装订后的 App 内 runtime”，相同真实闭环再次 `1/1` 通过并自动恢复。精确 App 内 DSH CLI 返回 `0.1.2-rc.1`，签名后 runtime 验证确认 Node 原生/Intel 均可执行、DSH 可启动。
- 签名脚本启动精确 App 并验证本地 Harness 桥成功；公证后使用 `open -g` 再次后台启动，桥发布成功且进程干净退出。`open -j` 强制隐藏的自动化启动不会更新桥文件，不能把这种非产品启动方式计入三轮冷启动通过，也没有以它替代正常启动结论。
- 21 个跳过项包含真实配对、真实远程会话、真实远程仿真、ADB/网络与平台专属门禁，均继续按未验收处理。

### Windows 58 精确 Release

- 精确源码：`D:\KEMI-Test\source\vibekits-9451cf4-dev199`；源码归档 SHA-256 与 macOS 固定归档一致。
- Windows 10 `19045` 真机构建成功；Relay 采用单线程增量构建后生成，SHA-256 为 `9f62ddee0223b288f544bb7848d6342ae8833cc3aeea6a17adc4a113cee3e033`，远程协助 gate 标记和状态命令均通过。
- Windows 远程协助/仿真定向回归 `144/144` 通过，`flutter analyze --no-pub` 为 `0 issue`。
- Release 构建耗时 `715.4s`；完整包验证通过，版本 `1.9.0-dev.199+2199`，Git `2.55.0.windows.3`、GitHub CLI `2.100.0` 和 `40` 项必需运行时均存在。
- 主程序 SHA-256：`16bb37dfa33c2785f236356e03314a5fe5e06a2581ba6094d0adedb578beb0b8`；文件版本和产品版本均为 `1.9.0-dev.199+2199`。
- Release 已复制到独立验收目录 `D:\KEMI-Test\acceptance\vibekits-dev199-9451cf4`，连续三次冷启动各等待 8 秒均保持存活；只终止三次验收拥有的 PID，未触碰用户会话中原有进程。
- 打包内 Node `v24.18.0`、DSH `0.1.2-rc.1` 可直接运行。逐字节核对 Node、DSH CLI、manifest、批准桥、父进程看门狗和 session rebind 均与测试运行时一致。打包阶段按设计用顶层新 MCP 服务替换 runtime 内旧副本；随后明确把最终包 MCP 字节置于测试路径，官方 Harness 完成真实模型请求、SHA-256 工具调用、原生批准命令、最终反馈和退出，`1/1` 通过，并在 finally 中恢复原文件且核对原哈希。
- 当前主程序 Authenticode 状态为 `NotSigned`。上述三次启动通过 SSH Session 0 完成，只能证明进程级稳定，不能替代 Windows 可见桌面的按钮和交互验收；因此 Windows 仍未达到发布门禁。
- Windows 脱敏持久日志保留两次最终包真实智能体成功记录，均为 `VIBEKITS_FULL_STACK_OK`、`exitCode=0`；58 当前没有 KEMI 市场注册项或常见安装目录中的已安装 VibeKits，只有隔离验收目录的 dev.199 候选，因此无法把用户界面上看到的失败归因到该精确候选。

### 真机状态

- PAD 75：`192.168.3.75:5555` 在线，`hi3781v730 / huanglong`，安装 `1.9.0-dev.188+2188`；已证明配对载体到达，尚未完成证书批准后的会话闭环。
- 63：三次 ICMP 全丢包；ADB 列表无 63；SSH 22 超时。当前结论只能是外部设备不可用、未测。
- Windows 58：已核验 ED25519 指纹；Windows 10.0.19045，D 盘剩余约 52.1 GiB。精确 Release、连续启动和最终包 Harness 真实智能体闭环已通过；可见桌面 UI 与 Authenticode 尚未通过，继续阻断发布。

## 不接受的另一分支公证包

`/Volumes/ORICO/kemi-build-cache/vibekits-public-store-dev199` 的 App 已取得 Developer ID 和 Apple ticket，但其源码 HEAD 为 `e5615bb`，不是本轮固定的 `9451cf4`；两者相差 26 个文件，包含主框架、应用分发和 Relay 打包门禁。该包不得作为本轮候选，也不得发布。

## 剩余硬门禁

1. 用户在操作发生时确认首次证书配对；重新发起 PAD 75 请求并完成“确认并记住”。
2. 跑 `manual_real_harness_remote_pairing_test.dart` 和 `manual_real_harness_remote_session_test.dart`，完成项目、会话、历史、反馈、停止和断开清理。
3. 默认路径与 `forceRelay=true` 各完成一次连接生命周期；跑真实远程仿真用例，核对 SSH、上传与 SHA-256。
4. 在 Windows 可见桌面安装精确候选，逐项验收 Harness 打开、会话输入、工具展示、停止和关闭；完成 Authenticode 后重新核对最终 EXE 哈希并复跑智能体闭环。
5. 63 恢复在线后补真机；若前述真实远程门禁暴露代码缺陷，修复后的新字节必须重新构建、Developer ID 签名、公证、装订并完成最终复验。
