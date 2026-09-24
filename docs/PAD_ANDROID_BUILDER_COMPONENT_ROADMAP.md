# PAD Harness 本机编译组件研发路径

## 目标与现状

PAD 默认 APK 必须能运行 Harness 与用户已开启的远程仿真/ADB。用户提出原生 APK 编译任务时，Harness 检查编译组件；未安装则在 KEMI 应用中心请求下载，用户完成系统安装确认后继续原任务。组件重启后仍可用，空闲时不运行编译服务。用户接受主 APK 不超过约 300 MB，50 MB 以内不视为“大组件”；因此体积优化不能以牺牲可靠性为代价。

PAD63 实测：现有 `com.termux` APK 33 MB，但 `/data/data/com.termux/files/usr` 展开后 995 MB；其中 Java 21 258 MB（`lib` 171 MB、可评估剔除的 `jmods` 80 MB），Android 35 平台 JAR 26 MB，`aapt` 1.3 MB、`dx.jar` 1.3 MB、`apksigner.jar` 1.1 MB。当前 VibeKits 签名 APK 约 86.8 MB。已有打地鼠构建依赖 Termux 与仅在测试期间启动的 `127.0.0.1:18473` Python 桥；PAD63 重启后端口未监听。此路径不算产品能力。

2026-09-24 再查 PAD63：系统 API 31、arm64；已装 `com.termux` 的 targetSdk 28；独立 `com.vibekits.vibekits.component.builder` 尚未安装。不能把现有 Termux 当作已交付的商城组件，也不能为了沿用旧版可执行文件策略让新组件无评估地降到 targetSdk 28。

## 选择的交付结构

1. 保留 PAD 主包中的 Harness、仿真服务和 ADB 辅助组件，不依赖编译组件即可正常启动与远程调试。
2. 在商城登记独立 Android 编译组件，固定包名与宿主 `com.vibekits.vibekits`；应用中心现有 HTTPS、精确大小、SHA-256、签名校验和 Android 系统安装确认流程负责安装。版本检测用 PackageManager 整数 versionCode；不从进程或下载历史推断已安装。
3. 编译组件通过同签名、显式绑定的受限接口接收工作区源码归档的只读文件描述符、构建参数，再把产物以受限文件描述符交还宿主；不能直接读取另一个 APP 的私有工作区绝对路径。只开放构建、状态、取消、取日志四种操作。Harness 不直接获得 Termux 任意命令权限。构建按需启动，完成后退出；用户关闭仿真不影响已经明确启动的本机构建，反之亦然。
4. 组件返回每步退出码、产物路径/字节/SHA-256 与签名证书；宿主再次核对 APK 包名和签名后才交给系统安装。任务与产物保存在持久目录，重启后恢复状态；不自动重跑中断的签名或安装步骤。

## 实现难点与决策门禁

- **不能直接改包名复制 Termux。** 官方包依赖固定 `/data/data/com.termux/files` 前缀；改包名需要重建 bootstrap 和相关 packages。原版 Termux 的 `RUN_COMMAND` 又要求用户授权及手动开启 `allow-external-apps`，并暴露较宽的命令权限。因此正式路径使用专用受限构建组件；现有 Termux 只作开发验证和故障对照。
- **Android 可执行文件限制。** 不可假定从应用可写 `filesDir` 解包后就能执行 JDK、aapt；需选定受系统允许的只读安装路径或改为组件内原生/JVM API，并在目标 Android 版本真机验证。禁止让 system-UID ADB 辅助组件代跑任意编译命令。
- **现有可复用先例。** `android/proxy_component` 将 Mihomo 的 arm64 可执行文件按 `libmihomo.so` 放入签名 APK 的 `nativeLibraryDir`，由带 signature 权限的 Binder 服务启动并验证版本。编译组件复用这一 APK/服务/文件描述符骨架；但 Termux 的 JDK、aapt 等还存在运行前缀与动态库依赖，必须逐件验证，不能因为 Mihomo 成功就假设整套工具链可直接复制。
- **工具链接口。** 先把商城的精确组件包名、版本查询和同签名安装闭环接通；随后做 Android 服务的显式绑定与最小原生 APK 正向样例。若原生服务无法执行所需工具链，再评估官方 Termux `RUN_COMMAND` 权限门禁作为过渡，明确显示用户授权及 `allow-external-apps` 配置，不以临时 18473 HTTP 桥替代。商城中的 Termux 应按它自己的原签名独立安装，不伪装成同签名宿主组件。
- **跨应用文件与验收。** 宿主把已确认的工作区文件打包，通过只读 `content://` 授权或 ParcelFileDescriptor 提供给受限组件；组件写入自己的私有构建目录，完成后通过一次性授权交回 APK，宿主验证哈希、包名和签名。不能要求 `MANAGE_EXTERNAL_STORAGE`，也不能通过 root/system UID 绕过 Android 沙箱。
- **大小。** 只打包必需编译链，剔除 JDK `jmods`、demo、文档与无关 Termux 包；最终压缩 APK 实测必须在用户接受的范围内。先证明功能，再调整包体，不以未经验证的估算称已达标。
- **签名和商场。** 组件与宿主身份须可信，商城记录必须有 HTTPS、精确字节、SHA-256、严格递增版本码。下载和系统安装由用户触发；不能静默绕过 Android 安装授权。Termux 上游 APK 不可重签后覆盖用户既有不同签名的 `com.termux`。
- **重启与恢复。** 已安装组件的版本由 PackageManager 查询；编译服务无需开机常驻。Harness 重启后通过持久任务记录继续读取结果或明确报告中断，不依赖 18473 临时监听。

## 分阶段可执行验收

1. 宿主识别组件缺失、商城条目及版本；缺失时引导安装，拒绝/取消不丢当前 Harness 任务；安装完成后恢复任务。商城条目未发布时清楚提示未上架。
2. 构建组件正式签名并通过系统安装；断网和重启后 PackageManager 仍识别同一版本，无常驻进程。
3. PAD Harness 在新会话自行写 Java/资源/图标，经受限接口在 PAD 本机编译、签名、安装原生 APK，工具日志与聊天记录一致；控制端不得代编译。
4. 第二屏真实运行、触摸与重启记忆回归；错误源码、缺依赖、取消、空间不足、组件升级和签名不匹配均有有界失败结果。
5. 通过 KEMI 商城公网页面与 CDN 下载相同字节的组件，从旧版本升级并验证系统安装。以上未通过前不把本机编译标记为正式能力。

## PAD Harness 的任务路由

用户说“在 PAD 上编译代码或 APK”时，PAD Harness 先调用 `vibekits.android.builder_component_status`。优先精确包名的专用构建组件；若尚未上架，检查商城中的原签名 `com.termux` 作为受权限约束的过渡依赖。已安装但 `buildReady=false` 表示只有包名/versionCode，工具链仍未验收；缺失且市场记录可信时调用 `vibekits.android.builder_component_install`，该工具会下载校验并打开 Android 系统安装确认，不能把“打开安装器”说成“安装成功”。用户确认后重查版本，再做构建服务握手。商城没有包、元数据缺 HTTPS/字节/SHA-256、签名不符或权限被拒绝时，保留原会话和源码并报告准确状态，不转去控制端代编、临时 HTTP 桥或现场重建 Android 工具链。

Termux 的[官方 RUN_COMMAND 契约](https://github.com/termux/termux-app/wiki/RUN_COMMAND-Intent)明确要求第三方调用权限和 `allow-external-apps`；[官方执行环境说明](https://github.com/termux/termux-packages/wiki/Termux-execution-environment)说明固定包前缀。它可以作为独立商城商品或受限过渡方案，但不能冒充同签名宿主组件。商城组件方案的完成标准是 PAD 自身获取源码、编译、签名、安装原生 APK，而不只是能找到市场条目。

## 当前推进记录

- 宿主已将 `com.vibekits.vibekits.component.builder` 作为保留组件 ID 识别，按真实 PackageManager versionCode 查询；同签名宿主安装白名单已加入该精确包名。伪造原生包名会在下载前被拒绝。商城回归测试 28/28 通过。
- PAD Harness 的移动端任务规则与 MCP 工具已接入：收到“在 PAD 编译”先查组件状态，只有完整可信的商城条目才能发起下载并打开系统安装确认；安装动作不冒充构建完成。查询工具会明确标记 `buildReady=false`，直到受限服务在真机完成原生构建握手。商城、Harness 桥接、能力目录和 DeepSeek 相关回归通过（既有 1 项按条件跳过）；Dart 静态分析与 Android Kotlin 编译通过。
- 当专用构建组件未上架时，商城发现支持原包名 `com.termux` 的独立 APK；伪造 `android_package_name` 的条目在下载前被拒绝。Termux 安装只解决依赖入口，不代表其权限、包集和构建结果已经验收。
- 2026-09-24 公共商城 `api/store/apps?os=android` 分别搜索 `Termux` 和 `VibeKits 编译组件`，两次均返回 `status=200, total=0, list=[]`。因此目前只能证明客户端路由，不能在 PAD63 演示“从商城安装”；发布前须有真实签名包、完整条目和设备端验收。
- 这只完成第一阶段的宿主接线。组件 APK、编译服务、真机原生 APK 构建和商城条目均未完成；P06/P12/P13 仍为 BLOCK。下一道实机门禁是：确定工具链在 API 31 非 system-UID 独立 APK 中的可执行方式，然后完成受限构建接口和原生样例。
