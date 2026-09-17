# VibeKits v1.9.0-dev.215 macOS 发布验收记录

日期：2026-09-16  
构建号：2215  
源码基线：`276d971c66d40dc896409b78c8aece79f45b7bce` + 本记录对应工作区差异  
结论：**本机 Harness 稳定性通过；正式发布暂时 BLOCKED（Apple 公证上传待强制审批，远程 Mac 真实链路未通过）。**

## 候选信息

- App：`Vibekits.app`
- 平台：macOS 12+
- 架构：主程序、内置 Node、远程仿真中继均为 `x86_64 arm64`
- 签名：Developer ID Application，本地深度校验通过
- Harness：DSH `0.1.5-rc.2`，Node `v22.19.0`
- 待公证候选 ZIP：`Vibekits-1.9.0-dev.215+2215-macOS-universal-signed-PENDING-NOTARIZATION.zip`
- 待公证候选 SHA-256：`50c1f2c9529db3eb86a689236105d61f447a370e520990577706c98adea2b5a7`
- ZIP 字节数：`317154638`

## 已通过门禁

1. 全量 Flutter 测试：882 通过、31 个真实设备/网络条件测试按设计跳过、0 失败。
2. `flutter analyze --no-pub`：0 issue。
3. macOS Release 兼容性：Universal、macOS 12+、Harness、ADB、7-Zip、GitHub CLI、Git 均通过。
4. Developer ID 深度签名：通过；内置 Harness Node 的 arm64/x86_64 启动、JIT 与签名权限通过。
5. 负向门禁：从隔离副本移走 Harness Node 后，启动压力工具以退出码 3 正确拒绝候选。
6. 本机 100 次循环：100/100 通过。每轮均执行：启动精确候选、读取本机工具目录、实际调用 `vibekits.system.capability_check`、退出、确认 DSH/MCP 子进程清理。
7. 100 次结果：0 失败；平均 1170 ms，最大 5000 ms；测试期间没有新增 Vibekits crash/hang/spin 报告。
8. Harness 内置准则已补充远程仿真固定流程：只需 6–16 位设备 ID；仅调用 `vibekits.simulator.*`；后台静默 P2P/中继；禁止启动或依赖 RustDesk 远程桌面 UI。

## 真实远程 Mac 验收

目标路由 ID：`4456560334`。

- 本机候选桥接正常，远程仿真技能能够正确调用 `vibekits.simulator.connect`。
- 两次真实连接均在 45 秒后返回结构化错误：`transport_failed: TimeoutException`。
- 随后 `connection_status` 返回 `connected=false`，失败会话已调用 `disconnect` 清理。
- `kemi-chat.newlinksz.com:21116` 与 `:21117` TCP 可达；业务状态端点 `:21114` 拒绝连接。21114 与原生 HBBS/HBBR 不是同一门禁，不能仅据此断言目标离线或原生中继故障。
- 因未取得目标身份验证、远端 catalog、系统信息和应用状态，不能声称该 Mac 已可正确仿真。

## 正式发布阻塞项

1. 工具审批要求用户对 dev.215+2215 这一具体包上传 Apple 公证服务作明确确认；未获得该审批前不得把待公证 ZIP 宣称为正式安装包。
2. 目标 `4456560334` 需处于开启远程仿真且服务在线的状态，再重跑 `connect → connection_status → catalog → 只读系统/应用检查 → disconnect` 并取得完整证据。

解除两项阻塞后，必须对装订票据后的 App 重新生成最终 ZIP，重新计算 SHA-256，并至少再执行 1 次从最终 ZIP 解压后的启动与 Harness 调用检查。
