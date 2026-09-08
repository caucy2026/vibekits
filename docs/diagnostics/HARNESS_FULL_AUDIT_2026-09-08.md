# VibeKits Harness 全功能检查报告（2026-09-08）

## 结论

当前代码基本沿着最近需求实现，核心功能回归没有发现正确性失败，但本版本尚不满足“可发布”标准。

- 全项目静态分析：通过，`No issues found`（307.7 秒）。
- 全套串行回归：682 通过、14 条按实体环境门禁跳过、3 条失败，总耗时 20 分 12 秒。
- 3 条失败全部属于界面点击性能基准；功能断言没有失败。
- Windows Release：失败。正在运行的旧版 `vibekits.exe` 锁住输出文件，链接器报 `LNK1104`；现存 EXE 仍是 2026-09-04 产物，不能作为本次验收包。
- Git：当前 `HEAD` 为 `ef440fd`、分支 `main`。工作树有约 110 个变更文件，其中大量是本轮误触发的机械格式化噪声；未推送云端。

## 最近需求对照

| 需求 | 代码/测试状态 | 判定 |
|---|---|---|
| Harness Release 自带 `kemi-s1-hardware-debug` | Windows/macOS runtime 准备脚本复制完整技能；Release 校验脚本检查 `SKILL.md`、`agents/openai.yaml` 和两份 reference；单元测试验证安装到 Harness 实际扫描目录 | 代码与测试通过，Release 实包因链接失败尚未终验 |
| 技能表达串口、ADB、Git、Markdown 报告联动 | 技能正文与 HiV730 路由资料齐全；Harness 的 YAML 解析器可成功读取 | 通过 |
| 新同事安装即可使用，不依赖系统盘技能目录 | 运行时从 App 自带 `builtin-skills` 安装到当前 Harness agent home；支持显式 `CODEX_HOME` | 逻辑通过，需新 Release 包做净环境实测 |
| 三层 MCP：本 App、本机、局域网 | 实时目录、注册文件、LMCP/2 认证和三层查询顺序测试通过 | 通过 |
| 本机/局域网设备动态更新与自动调用 | 周期公告、迟启动观察者、goodbye 下线、失败退避、自动调度与租约释放通过 | 通过 |
| MCP 开关、设备名/硬件码、远程调用审批 | 身份稳定、名称含硬件识别码、开关持久化、风险确认、无 UI 审批时高风险默认拒绝均通过 | 通过 |
| 长任务可启动、查询、等待、取消 | CLI 长任务、磁盘分析任务、任务 ID 等待和取消测试通过 | 通过 |
| 串口/ADB/Git 联动能力 | 串口自动探测与长连接、ADB 会话与工具桥、Git 查询/提交/推送分离均通过 | 通过；本轮未连接实体 75 设备 |
| Record and Replay 是语义技能而非坐标回放 | 演示编译为参数化语义技能、缺少必填语义输入时拒绝回放测试通过 | 通过 |
| Windows/macOS 跨平台打包 | 两个平台打包脚本已加入技能；本轮只在 Windows 主机测试 | 部分验证 |

## 本轮发现并修复

### 1. 清理策略 5 万候选性能退化

原实现对每一条候选重复规范化 Windows 系统保护目录、重复创建路径匹配对象，并反复规范化受保护根目录。隔离测试耗时约 4.0–4.4 秒，超过 3 秒门限。

修复后改为在一次清理计划开始时预编译平台删除边界和受保护根目录，再对候选执行轻量匹配。相同 5 万条测试约 2 秒完成，8 条清理决策测试全部通过。保护语义未放宽：系统目录、磁盘根目录、当前程序目录仍优先拒绝。

### 2. 版本测试未同步

应用版本升级为 `1.9.0-dev.159+2159` 后，更新服务测试仍期待旧 build 2158。本轮已同步为 2159并通过。

### 3. `path` 依赖声明不完整

Harness 技能安装代码直接引用 `package:path`，但 `pubspec.yaml` 未声明为直接依赖。已加入 `path: ^1.9.1`，静态分析恢复为零问题。

## 全套测试详情

执行命令：

```powershell
D:\tools\flutter\bin\flutter.bat analyze --no-pub
D:\tools\flutter\bin\flutter.bat test --no-pub --concurrency=1
```

通过范围包括：ADB、串口、Harness UI/会话/工具桥、Git、SSH/SFTP、RustDesk、LMCP/2、本机 MCP、局域网 MCP、远程审批、清理器、压缩、文档、数据库、OCR/本地模型、应用更新、Record and Replay、Windows 测试节点等。

14 条跳过项都带环境门禁，主要需要真实 ADB 地址、真实串口、远程节点、发布缓存或指定外部测试资产。本次不能把这些跳过项计为实体设备通过。

### 仍失败的 3 条性能基准

1. 一级工作区点击：Harness 首次打开约 3859 ms，门限 2500 ms。
2. 开发工具暖启动：本次轻量虚拟机约 1076 ms，门限 1000 ms；先前独立复测中程序员计算器也出现 1025 ms。
3. 文档/支持格式窗口：该组合测试仍超时；单次采样受 Debug JIT 和主机负载影响，但已多次复现，不能判为通过。

建议后续对 Harness 首屏做懒加载，把模型发现、目录扫描和后台服务初始化移出首次构建关键路径；开发工具复用已创建状态；再用 profile/Release 帧时序补充用户可感知指标，而不是放宽现有门限。

## Release 构建结果

执行：

```powershell
D:\tools\flutter\bin\flutter.bat build windows --release --no-pub
```

结果：链接 589.9 秒后失败。

```text
LINK : fatal error LNK1104: 无法打开文件
D:\vibecode\vibekits\build\windows\x64\runner\Release\vibekits.exe
```

该路径已有一个 2026-09-04 14:36:31 的旧 EXE，运行中的 VibeKits 占用它。本轮没有强制结束用户正在使用的 App，因此也未执行依赖新产物的 `verify_windows_bundle.ps1`。构建还报告 NuGet 未安装和 `webview_windows` 的 CMake CMP0175 开发者警告；它们不是这次终止构建的直接原因，但应在发布环境消除或固定工具链。

## Git 与发布风险

当前工作树约 110 个文件变化。真正与本需求相关的改动集中在：

- `.skills-publish/kemi-s1-hardware-debug/`
- `lib/features/dev_tools/domain/deepseek_harness_service.dart`
- `lib/features/cleaner/domain/cleanup_decision_engine.dart`
- `lib/features/cleaner/domain/cleanup_platform_policy.dart`
- Windows/macOS Harness runtime 准备、打包和验证脚本
- 版本、依赖、对应测试与开发记录

其余大量文件是一次全目录 `dart format lib test` 造成的机械格式变化。由于工作区原本已有用户改动，不能未经确认用破坏性恢复命令批量覆盖。因此本轮没有提交或推送，避免把无关噪声上传云端。

## 发布前必须完成

1. 先保存或关闭正在运行的旧 VibeKits，再重新执行 Windows Release 构建。
2. 对新产物运行 `tool/verify_windows_bundle.ps1`，并在干净 agent home 中启动 Harness，现场查询全局技能目录。
3. 优化并重跑 3 条点击性能测试，目标为 0 失败。
4. 注入真实 75 设备 ADB 地址和串口，执行 14 条环境门禁中相关的 live tests，保存串口/ADB 一致性证据。
5. 审核并清除机械格式化噪声，只提交本需求相关差异；之后再推送云端。
