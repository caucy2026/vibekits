# Vibekits 统一开发文档

本目录是 Windows/macOS 的统一产品、设计、实现和验收基线。需求变更必须先更新文档与验收编号，再修改代码。

## 阅读顺序

1. [统一产品需求](00_PRODUCT_REQUIREMENTS.md)——最高产品与研发基线
2. [Windows 平台产品附件](00_WINDOWS_PRODUCT_SPEC.md)
3. [Windows 界面布局](01_WINDOWS_UI_LAYOUT.md)
4. [跨平台技术架构](02_TECHNICAL_ARCHITECTURE.md)
5. [统一实施计划](03_IMPLEMENTATION_PLAN.md)
6. [Windows 验收矩阵](04_WINDOWS_ACCEPTANCE_MATRIX.md)
7. [Windows 验收流程](05_WINDOWS_ACCEPTANCE_PROCESS.md)
8. [Windows 模块实现规格](06_WINDOWS_IMPLEMENTATION_SPEC.md)
9. [Windows UI 验收矩阵](07_WINDOWS_UI_ACCEPTANCE_MATRIX.md)
10. [交互与操作习惯规范](08_WINDOWS_UX_CONVENTIONS.md)
11. [开发日志](09_DEVELOPMENT_LOG.md)
12. [当前实现状态与未完成清单](10_CURRENT_IMPLEMENTATION_STATUS.md)
13. [macOS 平台实现附件](11_MACOS_PLATFORM_SPEC.md)
14. [统一验收矩阵](12_UNIFIED_ACCEPTANCE_MATRIX.md)
15. [用户需求总账](13_REQUIREMENT_LEDGER.md)
16. [实验与闭环路径](14_EXPERIMENTATION_PATH.md)
17. [程序员工具版图与移植决策](15_DEVELOPER_TOOL_LANDSCAPE.md)
18. [第三方组件、模型与供应链记录](16_THIRD_PARTY_COMPONENTS.md)
19. [发布完成清单](17_RELEASE_COMPLETION_CHECKLIST.md)——当前唯一执行与验收清单
20. [无歧义原子验收动作](18_ATOMIC_ACCEPTANCE_CASES.md)——前置、动作、唯一预期、失败判定与证据
21. [官方 Harness Web 对齐基线](19_OFFICIAL_HARNESS_WEB_PARITY.md)
22. [跨工具开发工作流](20_INTEGRATED_DEVELOPER_WORKFLOWS.md)
23. [发布质量门禁](21_RELEASE_QUALITY_GATE.md)
24. [能力融合与智能体自动发现最高准则](22_CAPABILITY_INTEGRATION_STANDARD.md)——新增或移植任何工具时必须遵循
25. [创新能力交付路线](23_INNOVATION_DELIVERY_ROADMAP.md)
26. [智能清理产品与架构准则](24_CLEANER_COMPETITIVE_ARCHITECTURE.md)——清理竞品结论、五任务入口、规则数据库和超越路线
27. [Windows 测试节点与 GitHub 受控备份](25_WINDOWS_TEST_NODE_AND_GITHUB_BACKUP.md)——节点生命周期、GitHub 代理回滚和分离审批备份合同
28. [dev.61 Windows 测试节点与 GitHub 备份剩余工作](26_WINDOWS_NODE_GITHUB_BACKUP_REMAINING.md)——helper 实体、关闭工具、Release 门禁和两台 Mac 实证
29. [安全 Windows 测试节点复用指南](27_SECURE_WINDOWS_NODE_INTEGRATION_GUIDE.md)——helper 协议、设备身份、跨设备证据与智能体接入通用设计
30. [dev.58～dev.61 GitHub 备份记录](acceptance/GITHUB_BACKUP_DEV58_DEV61_2026-08-21.md)——备份范围、安全边界和远端核验方法
31. [智能体使用 Windows 测试节点所需工具](28_AGENT_WINDOWS_NODE_TOOL_REQUIREMENTS.md)——已完成工具、缺失 ToolSpec、输入输出、安全边界和验收门禁
32. [Mac 调用 Windows 测试节点完整搭建手册](30_MAC_WINDOWS_NODE_CALL_GUIDE.md)——v2.0 标准账户、独立密钥、局域网防火墙、本机预验收、SFTP 哈希闭环与 MCP 注册
33. [Windows 节点智能体工具接口](29_AGENT_WINDOWS_NODE_TOOL_API.md)——Harness/Codex 调用顺序、参数、返回、STDIO 注册和可用性发现
34. [dev.63 外部 Codex MCP 验收](acceptance/V1_9_0_DEV63_CODEX_MCP_2026-08-21.md)——全局注册、77 工具发现、节点调用与 Release 证据
35. [dev.64 清理经验决策引擎验收](acceptance/V1_9_0_DEV64_CLEANUP_DECISION_2026-08-22.md)——同机只读复扫、四级决策、安全边界与性能数据
36. [dev.65 30 项高频微工具验收](acceptance/V1_9_0_DEV65_UTILITY_PLUS_30_2026-08-22.md)——GitHub 能力去重、界面/Harness/日志闭环与性能数据
37. [dev.66 工具集 UI 与智能体接口验收](acceptance/V1_9_0_DEV66_UTILITY_UI_AGENT_2026-08-22.md)——自动可见工具条、小窗口、自带接口 ID 与快捷执行
38. [dev.67 ADB 语义工具与真机验收](acceptance/V1_9_0_DEV67_ADB_SEMANTIC_TOOLS_2026-08-22.md)——Shell、Logcat、文件往返、截图与 APK 安装门禁
39. [dev.68 代理与轻量虚拟机闭环验收](acceptance/V1_9_0_DEV68_NETWORK_VM_CLOSED_LOOP_2026-08-22.md)——真实系统代理恢复、qcow2 创建、QEMU 启停和 Harness 调用
40. [dev.69 Android 真机与 macOS 构建验收](acceptance/V1_9_0_DEV69_ANDROID_MACOS_2026-08-22.md)——arm64 真机性能、进程退出与 macOS 14 Release CI
41. [dev.70 Harness 本地启动性能验收](acceptance/V1_9_0_DEV70_HARNESS_STARTUP_2026-08-22.md)——旧入口纠正、真实分段计时、已完成优化与 3 秒门槛结论
42. [dev.71 Clash Verge 工作区验收](acceptance/V1_9_0_DEV71_CLASH_WORKSPACE_2026-08-22.md)——订阅、节点、代理模式、系统代理、统计和日志真实闭环
43. [dev.72 Clash 订阅修复验收](acceptance/V1_9_0_DEV72_CLASH_SUBSCRIPTION_2026-08-22.md)——长 URL、系统代理、客户端标识、无端口 YAML 和脱敏日志
44. [dev.73 Clash 标准 Profile 验收](acceptance/V1_9_0_DEV73_CLASH_STANDARD_PROFILE_2026-08-22.md)——行内节点、内置 GeoData、启动前预校验与真实 Profile 证据
45. [dev.74 Clash 测速与关闭验收](acceptance/V1_9_0_DEV74_CLASH_DELAY_CLOSE_2026-08-22.md)——真实延迟、分组测速、进度与恢复网络
46. [dev.75 Clash 标准界面验收](acceptance/V1_9_0_DEV75_CLASH_STANDARD_LAYOUT_2026-08-22.md)——八项侧栏、真实流量、双列节点、单节点与分组测速
47. [dev.76 音频调试验收](acceptance/V1_9_0_DEV76_AUDIO_DEBUG_2026-08-22.md)——PCM/WAV 波形、播放、频谱、信号健康、拖入与 Harness
48. [音频 Harness 工具接口](31_AUDIO_HARNESS_TOOL_API.md)——PCM/WAV 质量、谐波、杂讯、转换、播放与测试音接口
49. [dev.77 音频质量闭环验收](acceptance/V1_9_0_DEV77_AUDIO_QUALITY_HARNESS_2026-08-22.md)——FFT 性能、质量指标、Harness 真调用与 Release
50. [dev.78 清理经验算法与性能闭环验收](acceptance/V1_9_0_DEV78_CLEANUP_EXPERIENCE_ALGORITHM_2026-08-22.md)——本机只读审计、10 GiB 目标规划、安全缺口与大候选集性能
51. [dev.79 Android UI 与局域网 Key 验收](acceptance/V1_9_0_DEV79_ANDROID_UI_LAN_KEY_2026-08-23.md)——底部导航、返回历史、Keystore、一次性二维码网页输入与 APK 构建
52. [清理算法跨平台拆分与迁移基线](32_CLEANER_PLATFORM_MIGRATION.md)——公共内核、Windows/macOS/Android 独立规则与删除边界
53. [dev.80 清理平台拆分验收](acceptance/V1_9_0_DEV80_CLEANER_PLATFORM_SPLIT_2026-08-23.md)——规则互斥、Android 沙箱、双重越界保护与轻量回归
54. [智能体原生产品与持续演进规范](33_AGENT_NATIVE_PRODUCT_AND_EVOLUTION.md)——产品简介、逐工具智能体验收、Harness 上游发现、候选验证、灰度和回滚
55. [dev.81 智能体协作与演进验收](acceptance/V1_9_0_DEV81_AGENT_NATIVE_EVOLUTION_2026-08-23.md)——高频工具回归、真实模型 MCP 主链、音频时间定位和上游候选检测
56. [系统资源诊断与 Harness 接口](34_SYSTEM_RESOURCE_HARNESS_API.md)——Windows/macOS/Android 的 CPU、内存、GPU、磁盘、Top 进程和连续采样合同
57. [dev.82 系统资源诊断验收](acceptance/V1_9_0_DEV82_SYSTEM_RESOURCE_DIAGNOSTICS_2026-08-23.md)——本机真采样、ADB Android、界面与 Harness 闭环
58. [全部工具的智能体闭环验收准则](35_HARNESS_ALL_CAPABILITY_ACCEPTANCE.md)——公开工具执行器、真实调用、日志、授权、环境门禁和 APP 自检
59. [dev.83 全工具智能体闭环验收](acceptance/V1_9_0_DEV83_ALL_HARNESS_CAPABILITIES_2026-08-23.md)——482 项全量结果、30/30 微工具和生命周期修复
60. [Android 单屏/双屏启动规范](36_ANDROID_DUAL_SINGLE_SCREEN.md)——默认双屏、长按单屏、跨屏路由与原子退出规范
61. [dev.86 Android 双屏退出验收](acceptance/V1_9_0_DEV86_ANDROID_DUAL_EXIT_2026-08-24.md)——192.168.3.62 上 D0/D2 任一屏关闭后双屏同时退出
62. [dev.87 Android 双屏异显验收](acceptance/V1_9_0_DEV87_ANDROID_HETEROGENEOUS_2026-08-24.md)——D0 Harness、D2 资源诊断、图表说明与双屏退出真机证据
63. [dev.88 Android 1920×2560 双屏布局验收](acceptance/V1_9_0_DEV88_ANDROID_1920X2560_2026-08-24.md)——图标文字底栏、上下屏区段和可见退出按钮真机闭环
64. [dev.93 Android 连续跨屏画布验收](acceptance/V1_9_0_DEV93_ANDROID_CONTINUOUS_CANVAS_2026-08-24.md)——唯一 Activity/Engine/状态树，D2 上半区、D0 下半区、D2 触摸联动与双屏退出真机闭环
65. [dev.97 Android Harness/清理/OCR 真机验收](acceptance/V1_9_0_DEV97_ANDROID_REAL_DEVICE_2026-08-24.md)——移动 Harness 原生链、Android 安全清理、PP-OCRv6 ONNX 真推理和双屏退出
66. [dev.106 Harness 连续启停 100 次验收](acceptance/V1_9_0_DEV106_HARNESS_100_RESTART_2026-08-26.md)——真实 DSH HTTP、托盘退出、子进程回收与启动/退出分位数据
67. [外部智能体 MCP 与 Harness 工具接口目录](37_HARNESS_CAPABILITY_CATALOG.md)——从注册表自动生成，包含任意 MCP 客户端接入、真实工具名映射、参数与安全边界
68. [dev.107 Harness 能力认知闭环验收](acceptance/V1_9_0_DEV107_HARNESS_CAPABILITY_INVENTORY_2026-08-26.md)——真实模型主动调用能力检查的历史检查点；当前动态数字以能力目录为准
69. [dev.108 Harness 冷启动修复验收](acceptance/V1_9_0_DEV108_HARNESS_COLD_START_2026-08-26.md)——现场 84.858 秒定位、可选插件裁剪及两轮 5～6 秒 Release 实测
70. [dev.109 Harness 幽灵会话删除验收](acceptance/V1_9_0_DEV109_HARNESS_SESSION_DELETE_2026-08-26.md)——旧自测会话清理、内存投影刷新、真实工作区保护与 Release 实测
71. [dev.113 Harness 滚轮与阅读密度验收](acceptance/V1_9_0_DEV113_HARNESS_SCROLL_DENSITY_2026-08-26.md)——长会话真实鼠标滚轮、Codex 字体密度、远程分享与会话日志分离
72. [dev.114 SSH 密码认证验收](acceptance/V1_9_0_DEV114_SSH_PASSWORD_AUTH_2026-08-26.md)——密码/私钥模式、凭据安全映射、网络可达与 SFTP 复用
73. [dev.115 SFTP 双栏导航验收](acceptance/V1_9_0_DEV115_SFTP_NAVIGATION_2026-08-26.md)——本地/远端独立后退、上一级、根目录边界与轻量闭环
74. [dev.116 远程历史与多设备验收](acceptance/V1_9_0_DEV116_REMOTE_HISTORY_MULTI_DEVICE_2026-08-26.md)——成功后自动记住、系统凭据、多终端并行与 Harness 在线状态
75. [dev.124 Harness rc.2 首启与 100 次完整重启验收](acceptance/V1_9_0_DEV124_HARNESS_RC2_100_RESTART_2026-08-27.md)——官方 rc.2、portable 编译缓存、100/100 完整退出重启与零残留进程
75. [网络抓包（PCAP）与 Harness 接口](38_NETWORK_PACKET_CAPTURE_HARNESS_API.md)——内置 WinDivert、实时抓包、保存读取、协议分析和 5 个智能体接口
76. [dev.117 网络抓包验收](acceptance/V1_9_0_DEV117_NETWORK_CAPTURE_2026-08-26.md)——Release 真抓、PCAP 解析、Harness 回读和权限失败边界
77. [dev.118 Android 63 Harness/Pad 全接口验收](acceptance/V1_9_0_DEV118_ANDROID63_HARNESS_PAD_2026-08-26.md)——ARM64 真机构建、130 接口可发现、平台门禁、五入口触控与 118 项自动化
78. [工具真实连续使用场景矩阵](39_TOOL_REAL_USAGE_SCENARIO_MATRIX.md)——再次进入、多目标并存、安全凭据、Harness 共用历史与逐工具缺口
79. [dev.119 工具连续使用验收](acceptance/V1_9_0_DEV119_TOOL_CONTINUITY_2026-08-27.md)——SSH 多设备复核、API 脱敏历史、ADB/串口复用和 19 工作区合同门禁
80. [多平台存储与清理策略](40_PLATFORM_STORAGE_AND_CLEANUP_POLICY.md)——Windows/macOS/Android 的持久目录、缓存、凭据库与不同清理边界
81. [dev.120 多平台策略验收](acceptance/V1_9_0_DEV120_PLATFORM_POLICY_2026-08-27.md)——平台合同、设置迁移、Windows 真扫与 Android/macOS 环境门禁
82. [dev.121 macOS 编译门禁](acceptance/V1_9_0_DEV121_MACOS_COMPILE_GATE_2026-08-27.md)——跨宿主路径仿真修复、macOS Analyze/测试及 unsigned Release 云端门禁
83. [dev.122 客户端存储可写门禁](acceptance/V1_9_0_DEV122_STORAGE_WRITE_PROBE_2026-08-27.md)——官方目录 API、启动写探针、不可写自动降级与三端编译门禁
84. [dev.123 Android 清理、长连接、自迭代与 DSH 首启验收](acceptance/V1_9_0_DEV123_ANDROID_HARNESS_ARCHIVE_SESSIONS_2026-08-27.md)——62 真机、161/139 接口、归档互操作、长连接和首启实测
85. [dev.125 Android 63 APK 连续安装与串口监听验收](acceptance/V1_9_0_DEV125_ANDROID63_APK_INSTALL_100_SERIAL_STRESS_2026-08-27.md)——Harness 发起、100/100 次安装、boot_id 重启判定与串口 0 B 未通过项
86. [dev.126 Harness 剪贴板验收](acceptance/V1_9_0_DEV126_HARNESS_CLIPBOARD_2026-08-27.md)——真实 DSH 输入框、系统剪贴板、物理鼠标与 Ctrl+V/Ctrl+C 双向闭环
87. [dev.127 Android 53 Harness ADB/串口联合压力验收](acceptance/V1_9_0_DEV127_ANDROID53_HARNESS_ADB_SERIAL_STRESS_2026-08-27.md)——真实 Harness 调用、100/100 次安装、boot_id 重启判定、长连接释放与串口 0 B 未通过项
88. [dev.128 Android 53 ADB/串口/Logcat 100 轮验收](acceptance/V1_9_0_DEV128_ANDROID53_ADB_SERIAL_LOGCAT_100_2026-08-28.md)——COM33 真实回环、100/100 次安装、11 份系统日志与零重启闭环
89. [dev.129 Android 53 全新安装/启动/串口并行监控 100 轮验收](acceptance/V1_9_0_DEV129_ANDROID53_FRESH_INSTALL_LAUNCH_SERIAL_100_2026-08-28.md)——100 次卸载、全新安装、启动和新 PID 校验，串口独立监听与重启现场采集
90. [dev.130 外部智能体 MCP 与 OCR 空间理解验收](acceptance/V1_9_0_DEV130_EXTERNAL_MCP_OCR_SPATIAL_2026-08-28.md)——通用 MCP 接入、自动接口目录、归一化位置和真实 OCR 推理
91. [dev.131 Harness 自动配置与串口技能验收](acceptance/V1_9_0_DEV131_HARNESS_AUTOCONFIG_SERIAL_SKILL_2026-08-28.md)——全工具精确参数查询、串口被动自动探测、技能注入和真实 Harness 问答闭环
92. [dev.132 Harness 调试目录、清理建议与诊断日志验收](acceptance/V1_9_0_DEV132_HARNESS_DEBUG_CLEANUP_LOGS_2026-08-28.md)——调试目录占用、选择性清理、工作状态和脱敏诊断日志
93. [dev.133/134 网络下载与 ADB 真机安装验收](acceptance/V1_9_0_DEV133_NETWORK_DOWNLOAD_ADB_2026-08-28.md)——Harness 下载、SHA-256、53 设备连接、显式降级参数与真实安装成功
94. [dev.135 Harness 远端 Git 按需取码验收](acceptance/V1_9_0_DEV135_HIV730_REMOTE_GIT_2026-08-28.md)——实读项目指南、Gerrit refs、master manifest、103 个仓库解析与整包同步禁令
95. [Harness × RustDesk P2P 实时状态架构](38_HARNESS_RUSTDESK_P2P_STATUS_ARCHITECTURE.md)——多项目状态机、本机安全 IPC、端到端 P2P 心跳、隐私边界和跨仓实施顺序
96. [RustDesk × Vibekits 可选集成合同](39_RUSTDESK_VIBEKITS_OPTIONAL_INTEGRATION_CONTRACT.md)——双方独立运行、发现握手、未连接 UI、协议兼容、失败隔离和 15 项联合验收
97. [dev.136 科米远程办公连接标识验收](acceptance/V1_9_0_DEV136_KEMI_REMOTE_LINK_STATUS_2026-08-28.md)——自动科米办公 ID、真实握手/心跳标识、过期降级和首屏解耦

## 完成定义

“代码已写”不等于“功能完成”。一个功能只有在以下条件全部满足后才能标记完成：

1. 产品规格存在唯一验收编号。
2. 实现代码、错误处理和资源释放完整。
3. 自动测试通过。
4. Windows Release 构建通过。
5. 验收矩阵中的人工步骤在目标 Windows/macOS 电脑实际执行并记录结果。
6. 对应 UI 验收编号通过并具有截图或录屏证据。
