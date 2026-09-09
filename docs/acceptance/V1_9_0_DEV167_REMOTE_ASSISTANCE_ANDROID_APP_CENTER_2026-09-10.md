# VibeKits 1.9.0-dev.167 远程协助与 Android 应用中心验收报告

日期：2026-09-10  
版本：`1.9.0-dev.167+2167`  
LMCP catalogRevision：`2167`

## 本轮目标

1. Mac 默认不开放远程协助，但主界面始终容易查看独立 Harness ID。
2. Mac 可在同一入口打开远程协助，也可输入另一台 Mac 的 ID 发起协助。
3. PAD 只作为协助端，不接受别人协助；进入协助模式后，未连接前禁止本地项目、会话、命令和工具操作。
4. Mac→PAD 只同步 Harness 项目、会话、阶段、文本、命令和反馈，不传远程桌面画面。
5. RustDesk 只承担设备注册、打洞和 HBBR 中继字节通道；应用数据由 VibeKits 自己的 mTLS、首次配对和最小权限协议保护。
6. PAD 默认单屏启动，并补齐只显示 Android 商品的应用中心。
7. 本机 MCP 入口点击后立即出现结果框或加载状态，不允许无反馈等待。

## 最终交互

### Mac 被协助

1. 打开 VibeKits，即使远程协助关闭，官方 Harness 容器顶部仍显示 `本机远程协助 ID`。
2. 点击同一行的“远程协助”。
3. 打开“允许远程协助”；默认密码为 `12345678`，用户可修改。
4. 首次连接需要执行端明确批准并核对身份；授权记录持久化，随时可断开、撤销或拉黑。

### Mac 协助另一台 Mac

1. 对方先允许远程协助并告知 ID。
2. 本机点击“远程协助”，输入对方 ID；已连接设备可从历史记录重连。
3. 连接成功后，远端工作区在本机按项目、会话、状态、时间线和文本反馈展示，可发送命令、停止任务和断开连接。

### PAD 协助 Mac

1. PAD 默认进入单屏本地模式。
2. 点击醒目的“远程协助”。
3. 输入 Mac 的 Harness ID 并连接。
4. 连接前本地操作全部禁用；连接后只呈现远端 Harness 数据和允许的操作；顶部持续标识远程协助状态并提供退出按钮。
5. PAD 没有本机 ID、开放协助或接收入站连接入口。

## 安全与依赖边界

- macOS/Windows 使用 App 包内 `vibekits-harness-relay`，Android 使用 APK 内 RustDesk relay 进程；不搜索、不启动、不依赖单独安装的 RustDesk/KEMI App 或插件。
- 远程协助默认关闭。读取持久 ID 不启动监听，也不会把状态提升为 `callable`。
- 只有 HBBS 注册与密钥确认完成后才允许呼叫；P2P 优先，失败才使用 HBBR。
- 首次配对绑定双方 ID、证书、nonce、口令和最小授权范围；工作区能力不能在握手中被扩大。
- 关闭连接会统一释放隧道、订阅和远端会话，不允许后台继续发送命令。

## 自动化结果

- 全量 Flutter 测试（串行，避免跨文件共享状态干扰）：`776 passed / 18 skipped / 0 failed`。
- 相关快速回归：`63/63`。
- 远程身份与对话框定向回归：`15/15`。
- 静态检查：本轮 5 个产品改动文件 `0 issue`；全仓分析无 error，保留测试/验证脚本中的 15 条既有 import/style info 和 1 条未使用可选参数 warning，不影响产物。
- 全量日志：`/private/tmp/vibekits-dev167-merged-full-test-with-runtime.log`。
- 源码目录未保存被 `.gitignore` 排除的 7-Zip 构建缓存；全量回归显式使用最终 App 内已签名、已验版本/格式/双架构/minOS 的真实 `7zz`，不是 mock 或跳过测试。

## Android 75 真机

- 设备：`192.168.3.75:5555`，Android 12。
- 安装：非增量覆盖安装成功，未清除用户数据。
- 包：`versionName=1.9.0-dev.167`，`versionCode=2167`。
- 冷启动 Activity：`.SingleScreenActivity`。
- APK 签名：v2/v3 通过；证书 SHA-256 `c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8`。
- APK SHA-256：`d1774e498bc4b9593eb1a1a12458e62391798ce4f8cb29a0ac00ef88c6dd321e`。
- 远程协助界面：只显示连接远程设备、退出、默认密码说明和历史区域；连接前禁用本地操作。
- 应用中心：识别为“Android 应用”；服务端当前没有 Android 上架项，因此真实返回空列表，未伪造测试商品。
- 冷启动日志：未发现 VibeKits FATAL/ANR。
- 证据：
  - `/private/tmp/vibekits-dev167-merged-pad75.png`
  - `/private/tmp/vibekits-dev167-final-remote-assist.png`
  - `/private/tmp/vibekits-dev167-final-app-center.png`

## macOS 真机候选

- App：`build/macos/Build/Products/Release/Vibekits.app`。
- 当前运行 PID：`55181`（验收记录时）。
- UI 版本：`v1.9.0-dev.167+2167`。
- 主程序：Universal `x86_64 + arm64`。
- Developer ID：`Developer ID Application: zhen ji (26T5WV4GLP)`。
- Hardened Runtime：已开启；36 个 Mach-O 文件逐项签名验证通过；内置 Harness Node 22.19、x86_64 路径和 JIT 启动验证通过。
- 默认关闭协助时，主界面真实显示独立 ID `1554650784` 和“远程协助”按钮。
- 证据：`/private/tmp/vibekits-dev167-merged-macos.png`。

本候选是 Developer ID 已签名的本地验收产物，最后一次重建后尚未重新提交 Apple 公证，因此本报告不把它标记为已公证正式发行包。

## 尚未完成的外部闭环

- 当前现场只有一台可操作 Mac；尚未完成 dev.167 的 Mac↔Mac 双机真实 P2P/中继连接、远端命令与反馈闭环。
- 当前 relay 状态为离线，因此没有伪报 `callable`。双机验收需要第二台 Mac 在线并允许远程协助后执行。
- Android 市场当前无上架商品，APK 安装器已完成客户端实现和签名/哈希/版本校验，但需等待真实 Android 商品后再做一次下载→系统安装器闭环。

## 双机最终验收步骤

1. Mac A 打开远程协助，记录 ID、状态和执行端批准提示。
2. Mac B 只输入 A 的 ID，验证 P2P；强制中继一次验证 HBBR。
3. B 读取 A 的真实项目/会话/阶段；在 A 运行安全只读任务，验证 `reasoning → toolRunning → reasoning → ready`。
4. B 向 A 发送安全只读命令并收到流式反馈，然后主动停止一项运行任务。
5. B 断开，确认两端连接状态、隧道、订阅和活动任务归零；A 本地 Harness 不被关闭。
6. 重连历史记录，再撤销授权，确认旧证书与会话立即失效。
