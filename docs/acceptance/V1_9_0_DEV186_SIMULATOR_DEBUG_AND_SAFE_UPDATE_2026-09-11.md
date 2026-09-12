# VibeKits dev.186 整机仿真诊断与安全升级阶段验收

日期：2026-09-11
版本：`1.9.0-dev.186+2186`

## 1. 本阶段目标

用户在目标 Mac 打开“允许作为仿真机”后，只提供统一 ID，控制端即可通过 VibeKits 内置 P2P/HBBR 通道发现目标端完整 MCP 目录，读取目标机上任意 App 的进程、系统日志、崩溃和资源证据，并执行受控启停。无需用户配置 IP、端口、SSH、密码或密钥。

同时加入 VibeKits 自身的签名候选升级合同，使完成一次 dev.186 引导安装的目标机后续可直接通过同一 ID 接收新版本。

## 2. 已完成代码

- 修复 Rust 被控端固定 `127.0.0.1:32147` 仿真端点的授权顺序：不再等待不存在的桌面 Connection Manager IPC，也不在发送登录响应前错误标记为已授权。
- 控制端只接收 `routingId`，自动选择 P2P/HBBR、分配本机回环端口、初始化 MCP、读取当次工具目录并在断开时回收隧道。
- 新增整机诊断工具：任意进程检查、macOS/Windows 系统日志、崩溃报告、应用启动/停止；并继续公开权威目录中的系统资源、文件、Git、网络和工程工具。
- 新增 VibeKits 自升级工具：`vibekits.simulator.install_candidate`、`vibekits.device.update_begin`、`vibekits.device.update_status`、`vibekits.device.update_apply`。
- 上传只允许仿真专用回环端点，采用五分钟、单次、随机令牌，绑定文件名、大小和 SHA-256；通用 LAN MCP 明确返回 `403 simulator_update_upload_disabled`。
- 应用前验证单一 App 根目录、Bundle ID、递增构建号、相同 Developer ID Team、Universal `x86_64 arm64`、`minos 12.0` 和深度签名；采用唯一回滚目录，避免覆盖历史恢复副本。
- 修复应用中心偶发点击无效：非当前工作区时彻底关闭后台 WKWebView 的 macOS 原生命中测试，切回 Harness 时恢复输入，不修改官方 Harness DOM。

## 3. 真机与自动证据

目标统一 ID：`4456560334`。目标端当时运行 `dev.183+2183`。

- ID-only `p2p_or_relay` 连续 2 轮，均初始化成功、读取 191 项远端工具、调用 `vibekits.device.processes` 并获得目标机真实进程，再可靠断开。
- 强制 HBBR relay 连续 2 轮得到同样结果，证明中继不是只显示在线而没有业务流量。
- 对目标机 VibeKits 读取 1000 行 Unified Log、进程及崩溃报告；没有发现 Flutter 手势异常或崩溃，应用中心点击问题定位为本地 WKWebView 原生命中层拦截。
- 本机真实 UI 使用系统点击从“开发工具”进入“应用中心”，macOS 列表加载成功，并打开 KEMI OFFICE 详情弹窗。证据：`/private/tmp/vibekits-dev185-app-center-cgevent.png`、`/private/tmp/vibekits-dev185-app-details.png`。
- 最终整合回归：101 项通过、1 项环境跳过，覆盖仿真传输、任意 App 诊断、安全升级、应用中心输入、设置滚动和主界面。新增用例验证令牌单次使用、大小/SHA 绑定、专用回环上传返回同一令牌、普通 LAN 端点拒绝上传、完整诊断和升级工具进入目录。
- 静态分析：新增升级服务、控制器、工具桥、LAN 服务器和目标端运行时均无问题。

## 4. macOS 候选门禁

- Release 构建成功：822.3 MB App bundle。
- Bundle ID：`com.caucy.vibekits`。
- 可执行架构：`x86_64 arm64`。
- 最低系统：`macOS 12.0`。
- Developer ID：`Developer ID Application: zhen ji (26T5WV4GLP)`。
- `codesign --verify --deep --strict`：通过；36 个 Mach-O 文件完成签名验证；内置 Harness Node `v22.19.0` 和 DSH 启动门禁通过。
- 干净候选 ZIP：`/private/tmp/Vibekits-1.9.0-dev.186+2186-macos-universal-developer-id-clean.zip`。
- SHA-256：`6831d5acc6b9db5f84a807158f10303218721bd70ddb2d02edd9e0ab8cefdf09`。
- ZIP 解压后二次 `codesign`：通过。
- Apple 公证后续已完成，历史提交 ID：`b5df5b05-0abb-4438-a3b2-2d938533b5db`，状态 `Accepted`；dev.186 随后被包含协同会话生命周期修复的 dev.187 正式包取代。

## 5. 明确未完成项

1. 目标 ID `4456560334` 的 dev.183 目录没有新增升级工具，因此不能用尚不存在的协议给自己安装 dev.186。需要用户或现有受控辅助通道一次性安装 dev.186；此后才能验收纯 ID 的远端升级。
2. 还需在 dev.186 目标上执行一次完整有效候选替换、同一 ID 恢复、工具再次调用及失败回滚真机验收。
3. 其他 KEMI App 的签名候选部署尚未实现为专用工具；当前已经能诊断、取证和启停任意 App，但“修复后自动部署其他 App”不能用 VibeKits 自升级接口冒充完成。
4. 本条后续已闭环：公证、staple 和 Gatekeeper 均通过；最终对外版本以 dev.187 验收记录为准。

结论：整机远端诊断的 P2P/relay 业务通道已在目标真机通过；安全自升级协议和自动测试已完成。dev.186 的公证缺口后来已消除，但旧目标的一次引导安装、版本替换回滚以及其他 App 专用部署仍按本记录所述单独验收。
