# VibeKits dev.179 仿真生命周期与系统文件关联验收

## 修复范围

1. “局域网仿真”恢复从 `OfficialHarnessWorkspace` 移到桌面 App 根生命周期。
   保存为开启状态后，VibeKits 启动即异步恢复独立 routing ID、回环 MCP
   端点和原生授权门禁，不再要求用户进入 Harness 页面，也不阻塞首帧。
2. Harness 工作区只显示仿真状态，不负责启动仿真服务，避免高级功能与智能体
   页面生命周期互相影响。
3. macOS `Info.plist` 按真实能力注册 6 类、215 个扩展名，`LSHandlerRank`
   为 `Owner`；`.rar`、`.r00` 和其他真实支持格式会出现在 Finder“打开方式”。
   `Owner` 是应用可声明的优先处理级别，但必须尊重用户已经明确选择的默认
   应用；安装包不得通过私有 API 或重置 LaunchServices 强制覆盖该选择。
4. Windows 沿用同一份 `SupportedFileTypes` 清单，并补齐独立音频 ProgID 和
   “用 Vibekits 分析音频”入口。

## RAR 事实门禁

- macOS 包内后端为官方 7-Zip 25.01 完整版，格式目录必须包含 RAR 和 RAR5。
- `test_data/archives/rarlng.rar` 必须完成列表、选择性解压和拖入 UI 路由测试。
- Finder“打开方式”注册与内部解压能力分别验收，任一缺失均不得交付。

## 远程闭环门禁

在目标机安装 dev.179、保持“局域网仿真”开关开启并重启 App 后，控制端只能
通过后台 helper 执行：

1. ID 路由连接；
2. MCP `initialize` 与 `tools/list`；
3. `vibekits.device.processes` 和一项只读日志能力；
4. 主动断开并确认本机临时监听端口消失。

测试不得打开远程桌面、接管键鼠或影响目标机前台工作。
