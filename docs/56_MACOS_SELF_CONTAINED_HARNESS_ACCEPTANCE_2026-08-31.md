# macOS 自包含 Harness 运行时验收（2026-08-31）

状态：Apple Silicon Release 真实启动与只读 MCP 调用通过；Developer ID 签名、公证、Intel 实机和异常网络矩阵待补。

## 1. 故障根因

用户已在官方 Harness 中录入 Key，但旧 macOS Release 在读取凭据前就失败。旧 App 不包含 Node、`@deepseek-ai/dsh`、`harness-runtime.json` 和 Vibekits MCP sidecar，因此界面只能显示“内置 Harness 运行时缺失或损坏”。这不是 Key 错误；凭据不能弥补缺失的可执行运行时。

另一个定位问题是 Flutter macOS 的 `Platform.resolvedExecutable` 可能指向 `Contents/Frameworks/App.framework/Versions/A/App`，不能只假设它永远是 `Contents/MacOS/Vibekits`。运行时解析现从两种入口向上寻找 `.app`，再固定读取 `Contents/Resources/tools/harness`。

## 2. 构建与供应链

- `tool/prepare_harness_runtime_macos.sh` 固定 Node 24.20.0 和 `@deepseek-ai/dsh@0.1.1-rc.2`。
- Node arm64/x64 归档来自 nodejs.org；下载与缓存均按官方 `SHASUMS256.txt` 校验。
- `lipo` 生成 Universal Node；sharp/libvips、koffi、node-addon-require-builtin 和 node-pty 同时保留 Darwin arm64/x64 产物，不携带 Linux/Windows node-pty 预构建。
- `tool/package_harness_runtime_macos.sh` 是 Release 构建阶段硬门禁；运行时或任一必要 sidecar 缺失时退出失败。
- 运行时必须放在 `Contents/Resources/tools/harness`，不能放进 `Contents/MacOS`。Resources 布局避免 codesign 把 JSON/npm 普通目录误判为嵌套代码包。
- `tool/sign_macos_release.sh` 逐一签名并验证真实 Mach-O、重封 Framework，再签 App 根包；禁止对 npm 目录盲用 `codesign --deep`。

## 3. 真实证据

- `flutter test --no-pub test/deepseek_harness_test.dart test/lan_peer_discovery_service_test.dart test/mcp_exposure_consent_dialog_test.dart`：24/24；包含两类 App bundle 路径、标准 800px 窗口侧栏开关、项目鼠标右键、项目重命名、添加工作区、会话锚定卡片、桌面鼠标即时拖动会话和 workspace-write 权限重绑定回归。
- 项目折叠补充回归：单击当前项目标题会折叠该项目全部会话，再次单击恢复；点击其他项目仍保持原有切换并展开语义，搜索时临时显示匹配会话。`test/deepseek_harness_test.dart` 最终 17/17 通过。
- `flutter analyze --no-pub`：0 issue；`git diff --check` 通过。
- `flutter build macos --release`：成功，Flutter 报告 592.7 MB。
- 签名脚本：20 个 Mach-O 文件逐项签名与验证通过；App 根包 `codesign --verify --strict` 通过。
- 内置 Node：Mach-O Universal x86_64 + arm64，版本 `v24.20.0`。
- App 主程序 SHA-256：`51d500686d376bdbfb978b289253d650b77541d41b5d79472072d3cc83fb1f5e`。
- App.framework SHA-256：`9f85069cbbd45b48cdd8415b4c9df72f848abaa0847e2c86b567232ccd2e0129`。
- 内置 Node SHA-256：`0f57e5e28d7d9584a6e6225093a13f5c066f7207a494d6ee4414a3f9f6757c6d`。
- 新 App 实际显示“Harness 就绪”，既有官方会话成功执行 `vibekits.system.capability_check`；`~/Library/Logs/Vibekits/Harness/logs/harness-work.jsonl` 记录 `toolRunning → ready`，会话日志最终为 `exitCode=0`。
- 标准 800px 实际窗口已显示左侧“新建会话”、项目和会话列表及收起按钮。原先 1020px 固定门槛会让 App 壳内约 776px 的 Harness 区域永久隐藏侧栏；现改为 720px 自适应门槛，并在收起后显示明确的“打开会话侧边栏”按钮。
- 对齐 Windows 项目栏后，macOS 侧栏增加工作区搜索、管理和文件夹 `+`；项目按一对多关系显示自己的会话。会话移动需要确认源/目标路径及权限根目录变化，运行中禁止移动，只迁移记录、不移动文件。
- 最终 Release 实机显示项目 12.5px 加粗、会话 11px；项目省略号菜单为白色圆角卡片，并已实际打开验证“编辑名称 / 在 Finder 中显示 / 在此新建会话 / 移除项目”。会话信息卡已实际打开，显示来源名称和路径、状态、时间及两个目标项目。
- 同一 App 同时监听回环状态端口和 MCP HTTPS `*:9443`；日志未记录 API Key。

## 4. 仍需完成

1. 用 Developer ID Application 正式签名、启用 Hardened Runtime、提交公证并在干净 Mac 安装验证。
2. 在 Intel Mac 或明确的 Rosetta 流程运行 DSH、sharp、koffi 与 node-pty；Universal 文件检查不能替代执行证据。
3. 补错误 Key、断网、API 超时、端口占用、强制退出和停止后无残留子进程矩阵。
4. 当前构建产物未覆盖 `/Applications` 中的正式 App，未作为公证外发包发布。
