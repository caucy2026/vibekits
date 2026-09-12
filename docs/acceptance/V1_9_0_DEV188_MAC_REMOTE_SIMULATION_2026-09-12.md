# VibeKits dev.188 macOS 远程仿真与 Harness 远程会话阶段验收

日期：2026-09-12
源码版本目标：`1.9.0-dev.188+2188`
本机精确候选显示版本：`1.9.0.188+2188`
结论：**远程仿真工具链通过；Harness 远程项目/会话双机闭环仍未通过，不得合并表述。**

## 1. 本轮问题与修复

升级后的平台数据根目录从旧的：

`~/Library/Application Support/Vibekits/Harness`

迁移到应用隔离目录：

`~/Library/Application Support/com.caucy.vibekits/Vibekits/Harness`

旧版本已经保存 `DEEPSEEK_API_KEY`，新目录只有浏览器会话记录。启动检查因此把官方 Harness 误判为未配置，用户侧表现为“智能体找不到文件/不可用”，实际安装包中的 Node、DSH 和 MCP 文件均存在。

修复后的启动流程只迁移旧 `.credentials.yaml` 中的 `DEEPSEEK_API_KEY` 标量，合并到当前 `refs` 节点；不复制其他旧记录、不覆盖当前浏览器会话、不删除旧凭据、不记录密钥值，并把新文件权限限制为 `0600`。凭据存在性检查同时兼容旧顶层格式和官方当前 `refs` 嵌套格式。

## 2. macOS 精确候选

- App：`/Volumes/ORICO/kemi-build-cache/vibekits-dev/run-20260912-credential-fix/source/build/macos/Build/Products/Release/Vibekits.app`
- DMG：`/Volumes/ORICO/kemi-build-cache/vibekits-dev/run-20260912-credential-fix/package/Vibekits-1.9.0.188+2188-macos-universal.dmg`
- DMG 字节数：`392361480`
- DMG SHA-256：`f6e0e1f1c75a74b258f60696595c30522ba9738f99a23f6abb91940fe006aca8`
- 主程序架构：Universal `x86_64 + arm64`
- 签名：`Developer ID Application: zhen ji (26T5WV4GLP)`；App 深度严格验签和 DMG 验签均通过。
- DMG 只读挂载后再次验证内层 App、版本和双架构通过。
- **未执行 Apple 公证、staple 或 Gatekeeper 外部分发门禁；本包只能作为签名测试候选。**

## 3. 本机 Harness 启动证据

同一精确候选实际启动后存在：

- VibeKits 主进程；
- 内置 `@deepseek-ai/dsh` Web 进程；
- `vibekits-mcp-server.mjs`；
- `vibekits-android-stress-mcp.mjs`；
- 独立 `vibekits-harness-relay --vibekits-harness-service`。

官方 Harness Web UI 已呈现侧栏、新建会话、工作区选择、模式选择、输入框和发送按钮；迁移后的凭据文件存在且权限为 `0600`。凭据内容未写入测试日志。

## 4. ID 4456560334 远程仿真证据

- 普通 P2P/自动中继连接成功，目录返回 `195` 个工具。
- 真实调用 `vibekits.device.processes` 成功，返回目标机 VibeKits 主进程、Harness Node 和两个 MCP 子进程。
- 强制 HBBR 模式返回 `transport=relay`，同一远程进程读取成功。
- 正常断开后隧道进程退出。
- 强杀本机控制端主进程后，隧道通过 stdin EOF 生命周期退出；没有留下旧目标 ID 的后台隧道。

这证明“只给 ID 后，通过 VibeKits 内置 RustDesk P2P/HBBR 访问目标受控 MCP 工具”的远程仿真链路可用；它不等同于官方 Harness 项目与会话 UI 已完成双机验收。

## 5. 首次证书配对与 Harness 远程会话

本机钥匙串存在已记住设备 `9464730211` 的 v2 记录：包含完整远端证书、证书摘要、项目范围 `/Volumes/ORICO/harness`，以及 `history/models/selectModel/rename/prompt/updateQueue/cancel` 七项会话权限。因此“首次明确授权后持久保存证书与范围”的数据合同有真实落盘证据。

2026-09-12 使用该记录强制 HBBR 连接时，对端在 TLS 握手期间终止连接，最终结果：

- `HARNESS_TRANSPORT_transport_connect_timeout`
- `REMOTE_TUNNEL_TLS_TIMEOUT`
- `HandshakeException: Connection terminated during handshake`

因此本轮**没有**把项目列表、会话历史、发送、反馈和停止标记为双机通过。新增 `manual_real_harness_remote_session_test.dart` 作为可重复门禁：默认跳过；只有显式设置真实目标与开关时才读取远端；模型发送与停止还需要第二个显式 mutation 开关，避免普通回归误发任务。

## 6. 63 真机状态

- `192.168.3.63:5555` ADB 连接成功并通过设备身份核验：`huanglong / hi3781v730_tablet`。
- 已安装 `com.vibekits.vibekits`，版本 `1.9.0-dev.165+2165`，arm64-v8a，APK Signature Scheme v3。
- 从停止状态启动 `DualScreenLaunchActivity` 成功，进程 PID `18656`；截图确认 Harness 主界面和输入区已显示。
- 由于 63 上仍是 dev.165，以上只证明旧版可启动，不能作为 dev.188 远程会话功能通过证据。

## 7. 自动回归

- 凭据迁移、工具桥和远程控制会话定向测试：35/35 通过。
- 新增真实远程会话测试默认安全跳过，显式真实运行结果按第 5 节记录为对端 TLS 终止。
- Windows/macOS 共用 Dart 协议、Windows Relay 构建合同仍需本轮完整回归；Windows 真机 Release/安装/UI 未执行，不能标记通过。

## 8. 剩余发布门禁

1. 在同版本在线双机上重新完成首次证书请求、执行端确认和持久化复连。
2. 真实同步至少一个项目、一个会话和历史记录。
3. 真实发送一条无工具任务，观察接受反馈，再独立停止并确认执行端终态。
4. 把 dev.188 安装到 63，完成 PAD 角色与状态 UI 验收。
5. Windows D 盘真机构建、安装、启动、共用协议和交互回归。
6. Apple 公证、staple、Gatekeeper；全部通过前不得复制到正式 `bin` 或发布市场。
