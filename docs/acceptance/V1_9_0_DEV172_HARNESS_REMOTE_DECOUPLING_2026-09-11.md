# VibeKits dev.172 Harness 与远程层解耦验收记录

日期：2026-09-11  
候选版本：`v1.9.0-dev.172+2172`  
需求基线：`docs/65_UNIFIED_ID_SIMULATOR_TARGET_REQUIREMENTS.md`

## 1. 修复范围

- 本机 ID、协同/仿真开关、密码、连接历史与连接操作只保留在“设置 → 高级”。
- 官方桌面 Harness 和移动端/回退 Harness 都只显示只读状态，不再显示远程管理按钮。
- 删除“进入协同后用远程页面替换 Harness 工作区”的逻辑；协同与仿真不再改变 Harness 的 Widget/WebView 生命周期。
- 状态统一为协同连接中、协同已连接、协同断开、协同异常，以及局域网仿真关闭、准备中、可连接、仿真中、异常。
- 删除额外 DOM 长轮询、清 WebView 缓存、本地存储和页面重载链路；诊断动作不再介入正常启动。
- DSH 就绪判断只要求 TCP 端口已监听和官方带 token 的浏览器 URL已发布；探针不发送任何 HTTP 请求，一次性认证地址只允许由 WebView 首次消费。
- 真机日志定位到旧随机端口认证 Cookie 累积导致 HTTP 431。桌面端优先复用稳定端口 `3080`；macOS 仅在 DSH Cookie 数量/体积达到风险阈值时清理浏览器 Cookie，Windows 的专用 Harness WebView2 启动时清理 Cookie。项目、会话、插件、缓存和 LocalStorage 均不受影响。
- Harness 首屏完成后才异步启动远程协助、仿真、LAN/MCP；可选服务失败不改变 Harness 状态，也不触发 Harness 重启。
- 修正 Harness URL 日志脱敏替换，避免把捕获组写成字面量 `$1`。

## 2. 自动化结果

| 门禁 | 结果 |
|---|---|
| 定向静态分析 | 通过，0 issue |
| 官方/回退 Harness 远程管理隔离契约 | 通过 |
| 高级设置、协同/仿真、RustDesk 服务、Widget 回归 | 通过 |
| 本轮测试汇总 | 78/78 |
| macOS 真机首次修复启动 | 通过；HTTP 431 消失，首屏导航约 322 ms |
| macOS 真机稳定端口再次启动 | 通过；无 Cookie 清理、无 HTTP 错误，首屏导航约 25 ms |
| Developer ID 嵌套签名 | 通过；36 个 Mach-O，内置 Node arm64/x86_64 均可启动 |

## 3. 仍需候选包验证

- 在“设置 → 高级”继续完成远程协助与仿真管理的双机业务验收。
- Windows Release 构建与真机启动、同一交互和状态回归。
- PAD 75 与 Mac 真双机协同/仿真闭环。

完成以上真机门禁前，本版本仍是开发候选，不得声明正式发布。
