# VibeKits dev.196 仅凭 ID 的 SSH/SFTP 远程仿真候选验收

日期：2026-09-13
版本：`1.9.0-dev.196+2196`

## 结论

dev.196 已完成控制端与被控端的仅凭 ID SSH/SFTP 实现、共享协议回归、Universal macOS 12+ 构建、Developer ID 签名、Apple 公证以及最终 DMG 真实启动验收。它可以作为目标 Mac `4456560334` 的下一轮双机验收候选。

本文不把本机自动测试冒充双机结果。目标机尚未安装本文精确候选，因此“输入 ID 后首次批准公钥、严格核对主机指纹、执行 SSH、上传文件、安装/启动/日志/回滚”的物理双机闭环仍是未通过门禁；通过前不得声称远程仿真正式完成，也不得上传 KEMI 商场。

## 实现范围

- 被控 Mac 打开“远程仿真”一个开关时，同时准备固定回环 MCP `32147`、RustDesk P2P/HBBR 载体和系统 SSH `22`；关闭时撤销 VibeKits 管理的公钥，并只在本轮确实由 VibeKits 打开 SSH 时恢复原状态。
- 控制端只输入统一设备 ID。它先经已认证 MCP 获取目标 SSH 用户与 Ed25519 主机指纹，按目标 ID 生成独立 Ed25519 密钥；目标首次显示允许/拒绝，批准后把受限公钥写入当前用户 `authorized_keys`。
- SSH 与 SCP 都固定通过 RustDesk 回环隧道，使用 `BatchMode`、`IdentitiesOnly`、`StrictHostKeyChecking` 和独立 `known_hosts`；不接受用户手填 IP、端口、账号、密码、私钥或主机指纹。
- 新增共享 Harness 工具：应用清单、签名安装、安全卸载、SSH 身份、SSH 公钥状态/授权/撤销，以及控制端 SSH 命令和文件上传。
- macOS 安装仅接受 SHA-256 匹配、Gatekeeper 通过、Bundle ID 匹配的单 App ZIP；覆盖前备份，失败自动回滚。卸载按唯一 Bundle ID 移入废纸篓，并保护 VibeKits 自身。
- Windows 与 macOS 共用应用清单、审批、协议和控制端逻辑；Windows 只接受 SHA-256 匹配、Authenticode 有效且发布者匹配的 MSI。Windows 系统 SSH 身份、公钥文件生命周期、D 盘 Release 和进程级启动已在 58 真机通过；经 VibeKits ID 的另一台 Windows 端到端仿真仍需单独验收。
- 危险远程调用在目标端统一进入可见审批；拒绝或两分钟未处理时不执行。关闭仿真会回收端点、隧道和 VibeKits 管理的 SSH 公钥，不删除用户自己的 SSH 密钥。

## 自动化证据

- 全量 Flutter 测试：856 项通过，19 项按真实外设/联网条件预期跳过，0 失败。
- 远程仿真、SSH 授权、目标运行时定向回归：16/16 通过；新增假传输闭环覆盖首次公钥授权、主机指纹不匹配拒绝、严格 SSH、SCP SHA-256 校验以及先关 SSH 后关 MCP 隧道。
- 首次审批 Hub 与界面回归覆盖允许、拒绝和等待态；生产代码静态分析 0 issue。
- 手工真机门禁 `manual_real_harness_simulator_test.dart` 已扩展为同时验证工具目录、进程读取、SSH 命令、SCP 上传、远端 SHA-256 和临时文件清理；未设置显式 live 环境时保持跳过，不会误连设备。
- 打包门禁新增 Harness Runtime 断链检查；任何 npm `.bin` 链接缺失目标文件时在复制进 App 前失败，不再延迟到签名阶段才报模糊错误。

## macOS 正式候选

- DMG：`/Volumes/ORICO/kemi-build-cache/vibekits-dev/run-20260913-dev196/package/Vibekits-1.9.0-dev.196+2196-macos-universal-notarized.dmg`
- 大小：`396205663` bytes
- SHA-256：`7a4652f36e734eaa11b2f5691b5461cc34c8515bc7d795209c1bbb568aaed642`
- 兼容：Universal `x86_64 + arm64`，最低 macOS 12.0。
- 签名：`Developer ID Application: zhen ji (26T5WV4GLP)`；深度严格验签、Hardened Runtime 和时间戳均通过。
- App 公证：Apple `Accepted`，Submission ID `70b4d81a-cfaa-4581-a382-eddd6aaf16d0`；App 已 staple/validate，Gatekeeper 为 `Notarized Developer ID`。
- DMG 公证：Apple `Accepted`，Submission ID `eb8385f8-f101-4ba7-a1cc-e8a978e0d728`；DMG 已签名、staple/validate，`hdiutil verify` 通过。
- 从最终 DMG 只读挂载、提取 App 后再次通过 Developer ID/Gatekeeper；真实启动发布 Harness 工具桥，校验到精确进程 PID，随后正常退出并清理临时副本。
- 包内 Harness Node v22.19.0 在 arm64 与 Rosetta x86_64 下均可启动 DSH；Harness、ADB、7-Zip、GitHub CLI 与 Git 完整性门禁通过。

## Windows 58 真机证据

- 节点：`192.168.3.58`，Windows 10 22H2 / build 19045，全部源码、缓存、临时目录、Rust/C++ 与 Flutter 构建输出位于 `D:\KEMI-Test`。
- Windows RustDesk Harness Relay 由源码提交 `447af40bd0cdd20321d0a982f3eb23cdd80887ac` Release 构建；EXE SHA-256 为 `07237288c52d66420482e7e042dabe064bd746b43ef7ab3cd48eda1a71413ffa`，来源 JSON、EXE 重算值和 AGPL 许可证齐全，状态命令返回合法离线 JSON。
- Windows 静态分析 0 issue；远程访问、首次配对、项目/会话同步、并发命令、反馈、停止/撤权、仿真控制、SSH/SCP 和 Relay 生命周期定向回归 `90/90` 通过。
- 真机发现标准用户无法直接读取 `C:\ProgramData\ssh\ssh_host_ed25519_key.pub`。提交 `694e20a` 改为从回环 `ssh-keyscan` 公钥计算相同 OpenSSH SHA-256 指纹，不提权、不关闭主机校验；真机实际完成身份读取、受限公钥写入、状态确认和精确撤销，`1/1` 通过。
- 精确 Release 通过项目验证器：版本 `1.9.0-dev.196+2196`、40 个必需运行时、Git `2.55.0.windows.3`、GitHub CLI `2.100.0`；安装目录为 `D:\KEMI-Test\app\Vibekits-dev196-694e20a`，Dart `app.so` SHA-256 为 `e7cc41f7cfb782909dff8bae735c33c78d54da0cbfc2d7035d96167f6c6c8cfe`。
- 三次会话 0 进程级启动均在 12 秒采样时存活，工作集约 82～94 MB；每次只停止精确测试 PID，最终 Node/Relay 残留为 0。SSH 会话 0 不能替代交互桌面，因此不把上述结果冒充 UI 点击验收。
- 主 EXE 与 Relay 的 Authenticode 均为 `NotSigned`。该目录仅是 Windows 真机测试候选，不得发布或上传市场。

## 目标 Mac 实时探测

- 控制端只使用统一 ID `4456560334`。默认 P2P 探测均能启动本地回环监听，但远端 `32145`（首次证书配对）、`32147`（仿真 MCP）和 `22`（系统 SSH）全部返回 `transport_connect_failed` / 远端未监听。
- 这证明当前阻塞不是控制端 ID 格式、监听端口分配或测试机 SSH，而是目标 Mac 未运行本文精确候选的仿真服务。由于目标没有任何可用 VibeKits/SSH 数据通道，不能在后台通过该 ID 自升级；必须先在目标机安装本文公证 DMG 并打开远程仿真开关。
- 63 与 PAD 75 的 ADB 连接探测当前均为 `No route to host`，设备列表为空。本轮没有把离线状态记成真机通过。

## 物理双机必须取得的证据

在目标 Mac `4456560334` 安装上述精确 DMG 并打开远程仿真后，按以下顺序验收，任何一步失败都不得标记完成：

1. 控制端只输入 ID；目标端首次出现一次公钥批准，拒绝路径不写入密钥，允许路径写入受限 Ed25519 公钥。
2. 控制端从认证 MCP 取得目标主机指纹；隧道扫描值完全一致后才登录，错误指纹必须 fail-closed。
3. 默认 P2P 与强制 HBBR 分别执行固定无副作用 SSH 探针，记录远端真实主机名和退出码，不记录账号、路径、密钥或业务数据。
4. 上传唯一测试文件，记录本地/远端相同 SHA-256、字节数和远端暂存路径；验收后只删除该暂存文件。
5. 使用独立、无业务数据、已签名测试 App 验证上传、安装、启动、PID、日志、停止、覆盖失败回滚和安全卸载；禁止拿 VibeKits 自身做破坏性安装测试。
6. 关闭远程仿真后，SSH 与 MCP 两条隧道均退出，VibeKits 管理的授权密钥被撤销，用户原有 `authorized_keys` 内容保持不变。
7. 63/PAD 完成项目、会话、历史、发送、反馈、停止和断开；Windows 58 完成 D 盘 Release、系统 SSH、安装/兼容性/性能和远程仿真真机闭环。

## 当前未完成

- 目标 `4456560334` 的 dev.196 精确安装和上述双机证据。
- 63/PAD 的精确版本协同闭环。
- Windows 58 经另一台 VibeKits ID 的端到端隧道登录、安装、日志和回滚；当前只完成本机系统 SSH 与 Release/进程门禁。
- KEMI 商场上传、公开 CDN 回下载及当前版本无更新检查。
