# VibeKits v1.9.0-dev.216 远程仿真按需传输修复验收

日期：2026-09-16  
版本：`1.9.0-dev.216+2216`  
源码基线：`276d971c66d40dc896409b78c8aece79f45b7bce` + 当前工作区改动

## 根因

RustDesk 字节转发是按需启动的：只有本地客户端连接转发端口后，原生载体才会建立 P2P/中继传输。控制器拆分控制、MCP、SSH 三条通道后，错误地先等待 `transport_connected`，随后才发送 HTTP/MCP 请求，形成双方互等并在 45 秒后超时。既有测试使用会立即返回 ready 的假进程，因此没有模拟真实按需行为。

## 修复

- 控制通道：先启动 SSH bootstrap HTTP 请求，再等待原生传输就绪。
- MCP 通道：先启动 MCP initialize/list 请求，再等待原生传输就绪。
- Android/iOS 控制端复用首条 MCP 通道时执行相同顺序。
- 异步请求立即挂接错误观察器，失败时仍由原始 Future 返回真实错误。
- 回归测试使用“收到真实请求前永不 ready”的按需进程模型，覆盖控制、MCP 和 SSH 三条隧道。

## 自动化结果

- `harness_simulator_controller_test.dart`：5/5 通过。
- macOS Release 构建成功。
- Universal：`x86_64 arm64`；最低系统：macOS 12+；Harness、ADB、7-Zip、GitHub CLI、Git 兼容性门禁通过。
- 本地验收候选为临时签名，只用于真实链路验证，不作为正式交付包。

## 真实跨机结果

控制端：dev.216+2216；目标 ID：`5298938227`；目标实际运行：dev.215+2215。

- 3.8 秒内返回 `connected=true`。
- 传输：`p2p_or_relay`；SSH 与 MCP 均 ready。
- 已验证主机：`kemideMac-mini.local`；系统 macOS 26.5.1；架构 arm64。
- 远端公开 207 项工具；应用、进程、系统版本和签名均可只读查询。
- 目标运行包：`/Users/kemi/Downloads/Vibekits.app`，实际版本 `1.9.0.215+2215`，深度签名校验通过。
- 验收结束后已断开，复核 `connected=false`，无残留隧道。

## 结论

本次 ID-only 远程仿真真实链路通过。正式发布仍需对 dev.216 候选执行 Developer ID 签名、公证及最终包复验；本记录不把临时签名候选声明为正式发布包。
