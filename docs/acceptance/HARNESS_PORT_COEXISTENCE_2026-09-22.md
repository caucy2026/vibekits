# VibeKits 与官方 Harness 共存：独立默认端口

## 要求及实现
VibeKits 内置桌面 Harness 默认使用 127.0.0.1:13080，避免抢占独立官方实例惯用的 3080。仅调整 VibeKits 启动适配层，继续使用官方 web --port 参数，不修改官方推理、会话或内核。

- 默认启动参数与空闲端口选择共用 HarnessLaunchSpec.defaultPort = 13080。
- 13080 已占用时由系统分配空闲回环端口，不结束或接管占用进程。
- WebView 与命令桥继续读取实际启动 URL，不固定连接 13080。
- DSH_HOME 继续使用 VibeKits 独立数据目录；不迁移或修改独立官方实例的数据。
- PAD 端使用其既有移动实现；此改动不新增 Android 桌面 Node 服务，也不改变远程设备的目标端口。

## 验证进度
- 端口选择、指定端口、占用后回退与原监听仍可连接：自动测试通过。
- Harness 相关回归合计 31 项通过。
- Mac/PAD Release 均完成编译；实际验证结果与限制见下文。

证据目录：/Volumes/ORICO/kemi-build-cache/app-release-gate/vibekits/port13080/

## 导航数字移除
按用户追加要求，移除共享 MainShell 导航项右侧的 1–7 数字，不改图标、文字、点击行为或快捷键绑定。该组件供各平台共用，不使用仅 macOS 生效的条件分支。新产物需重新编译后验证。

## 平台组件约束
- PAD：保留 Android 移动端 DeepSeekAgentWorkspace、触控 NavigationBar 和现有双屏宿主，不引入 macOS WebView。
- Linux：必须采用 Linux 支持的窗口、WebView/浏览器、输入与文件选择组件，不复用 macOS 原生桥。当前工作树没有 linux/ runner，因此 Linux 构建及真机验证标记为未实现/未验证，不以 Mac 或 PAD 结果替代。

## 实测结果
- 共享导航及 Android 双屏回归：29 项通过；Harness 回归：31 项通过。
- Mac 最终界面：导航数字消失；内置 Harness 实际监听 127.0.0.1:13080。
- 共存：未修改的官方 CLI 使用独立测试 DSH_HOME 在 3080 运行，和 VibeKits 13080 同时监听，两端均返回预期认证响应 HTTP 401；测试结束仅关闭测试实例。此项证明端口共存，不代表两边同时执行模型任务已验证。
- PAD63：192.168.3.63:5555 当前型号 KEMI Vibe Pads S1，设备代号 hi3781v730。通过 Harness ADB bridge 覆盖安装 dev.225+2225、核对版本、冷启动、PID、截图及应用 PID 日志；未见 FATAL EXCEPTION/Fatal signal。截图确认 Android 触控导航无序号，Harness 首页正常。未执行在线模型回答验收。
- 第一次真机检查因旧文档预期型号 huanglong 与现场产品名不同失败，保留实际数据后改为核对设备代号，并重新执行通过；不将第一次失败隐去。
- PAD APK SHA-256：a71d54e0cd10c5d9325f4e3a37bf919f63ca55566151e50e7d6930624a3e0f7a。

## 最终复核与限制

- 旧开发工具 Harness 启动入口也改用同一 defaultPort；补改后两平台重新编译完成。最终 PAD APK 哈希与上文一致，再次覆盖安装与启动测试通过，证据 `pad63-final.log`、`pad63-final/pad63-results.json`。
- Mac 曾在一次启动中显示“内置 Harness 运行时缺失”，重试恢复；全部构建结束后再次退出、冷启动，无需重试进入正常工作区，实际端口为 13080。单次异常原因未确定，不把重试结果覆盖原异常；完整发布稳定性门禁仍为 BLOCK，当前未发布。
- 当前实际 Mac DSH_HOME 为 `/Users/newlink/Library/Application Support/com.caucy.vibekits/Vibekits/Harness`，本轮端口改动未修改或迁移该路径。
- Linux 平台 runner 缺失；该平台仅落实设计约束，不能宣称 Linux 版本已构建或测试。
