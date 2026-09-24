# PAD Harness 本机编译组件研发路径

## 目标与现状

PAD 默认 APK 必须能运行 Harness 与用户已开启的远程仿真/ADB。用户提出原生 APK 编译任务时，Harness 检查编译组件；未安装则在 KEMI 应用中心请求下载，用户完成系统安装确认后继续原任务。组件重启后仍可用，空闲时不运行编译服务。用户接受主 APK 不超过约 300 MB，50 MB 以内不视为“大组件”；因此体积优化不能以牺牲可靠性为代价。

PAD63 实测：现有 `com.termux` APK 33 MB，但 `/data/data/com.termux/files/usr` 展开后 995 MB；其中 Java 21 258 MB（`lib` 171 MB、可评估剔除的 `jmods` 80 MB），Android 35 平台 JAR 26 MB，`aapt` 1.3 MB、`dx.jar` 1.3 MB、`apksigner.jar` 1.1 MB。当前 VibeKits 签名 APK 约 86.8 MB。已有打地鼠构建依赖 Termux 与仅在测试期间启动的 `127.0.0.1:18473` Python 桥；PAD63 重启后端口未监听。此路径不算产品能力。

2026-09-24 再查 PAD63：系统 API 31、arm64；已装 `com.termux` 的 targetSdk 28；独立 `com.vibekits.vibekits.component.builder` 尚未安装。不能把现有 Termux 当作已交付的商城组件，也不能为了沿用旧版可执行文件策略让新组件无评估地降到 targetSdk 28。

进一步对 PAD63 的现有工具链做只读二进制检查：`aapt` 文件内含 `/data/data/com.termux/files/usr`；`javac` 为 ELF 启动器，运行库路径含该前缀；`dx` 脚本首行是 `#!/data/data/com.termux/files/usr/bin/sh`，并从该前缀加载 `dx.jar`。这直接否定“把现有 bin 目录复制到独立 APK 即可运行”的捷径，专用组件需要重建/移植工具链或换用不依赖固定前缀的实现。

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
6. 安装 KEMI 商城组件后断开外网，PAD 仍能把最小 Java/资源工程编译、签名并产出可安装 APK；不得在首次编译时再到其他仓库执行 `pkg install`、下载 SDK/JDK 或由控制端代编。若组件不含完整工具链，商城条目不能标注“PAD 本机编译可用”。

## PAD Harness 的任务路由

用户说“在 PAD 上编译代码或 APK”时，PAD Harness 先调用 `vibekits.android.builder_component_status`。仅把精确包名的专用构建组件当作可安装的编译环境；原签名 `com.termux` 即使已在商城或本机，也只供诊断，不能代替完整离线组件。已安装但 `buildReady=false` 表示只有包名/versionCode，工具链仍未验收；缺失且市场记录可信时调用 `vibekits.android.builder_component_install`，该工具会下载校验并打开 Android 系统安装确认，不能把“打开安装器”说成“安装成功”。用户确认后重查版本，再做构建服务握手。商城没有包、元数据缺 HTTPS/字节/SHA-256、签名不符或权限被拒绝时，保留原会话和源码并报告准确状态，不转去控制端代编、临时 HTTP 桥或现场重建 Android 工具链。

`builder_component_status` 的结果必须带可执行的 `nextAction`：商城可信且组件缺失时明确指向 `builder_component_install`；未上架、元数据不完整或本机安装状态未知时明确停在相应故障，不建议另找工具链。Harness 可以先在当前工作区准备源码，但只有组件自检 `buildReady=true` 才能开始 PAD 本机编译；系统安装确认期间保留当前任务，不把安装器打开当成完成。

安装器打开后，Harness 调用只读 `builder_component_wait_install`：最多 90 秒只轮询专用包的 PackageManager 版本，不重复下载或访问商城；确认安装后立即做组件自检，`buildReady=true` 才继续当前任务。等待超时返回未安装，不自动重建工具链；用户稍后确认安装时可在原会话重查并继续。

任务中的“编译”指 PAD 本机真正执行构建；Harness 可生成源码，但编译环境只能来自经 KEMI 商城验证并已安装的完整组件。组件缺失时应保持当前会话与源码，提示“正在检查/需要安装 PAD 编译组件”，由商城安装完成后继续同一任务。不能把桌面编译产物、下载 Termux 后现场组装工具链、或仅检查 `aapt` 命令存在，称作已满足请求。

对已安装的 Termux，Harness 继续调用 `vibekits.android.termux_probe`。此探针只通过官方 `RUN_COMMAND` API 执行固定的 `aapt/javac/dx/apksigner` 存在性检查，返回包版本、权限状态、命令是否齐全和有界错误；它不运行用户任意文本，不替代实际 APK 构建验收。接收结果使用一次性 PendingIntent，最多等待 15 秒，不启动常驻桥服务。

Termux 的[官方 RUN_COMMAND 契约](https://github.com/termux/termux-app/wiki/RUN_COMMAND-Intent)明确要求第三方调用权限和 `allow-external-apps`；[官方执行环境说明](https://github.com/termux/termux-packages/wiki/Termux-execution-environment)说明固定包前缀。它可以作为独立商城商品或受限过渡方案，但不能冒充同签名宿主组件。商城组件方案的完成标准是 PAD 自身获取源码、编译、签名、安装原生 APK，而不只是能找到市场条目。

## 当前推进记录

- 宿主已将 `com.vibekits.vibekits.component.builder` 作为保留组件 ID 识别，按真实 PackageManager versionCode 查询；同签名宿主安装白名单已加入该精确包名。伪造原生包名会在下载前被拒绝。商城回归测试 28/28 通过。
- PAD Harness 的移动端任务规则与 MCP 工具已接入：收到“在 PAD 编译”先查组件状态，只有完整可信的商城条目才能发起下载并打开系统安装确认；安装动作不冒充构建完成。查询工具会明确标记 `buildReady=false`，直到受限服务在真机完成原生构建握手。商城、Harness 桥接、能力目录和 DeepSeek 相关回归通过（既有 1 项按条件跳过）；Dart 静态分析与 Android Kotlin 编译通过。
- 当专用构建组件未上架时，商城诊断仍可发现原包名 `com.termux` 的独立 APK；但 PAD 编译任务入口现在明确拒绝把它当作完整组件安装。伪造 `android_package_name` 的条目在下载前被拒绝。Termux 仅用于开发对照，不代表其权限、包集和构建结果已经验收。
- 2026-09-24 公共商城 `api/store/apps?os=android` 分别搜索 `Termux` 和 `VibeKits 编译组件`，两次均返回 `status=200, total=0, list=[]`。因此目前只能证明客户端路由，不能在 PAD63 演示“从商城安装”；发布前须有真实签名包、完整条目和设备端验收。
- 2026-09-24 实机候选 dev.253+2253：Release APK 85,027,740 字节，以既有 PAD 签名编译并安装到 63 号 PAD，PackageManager 回报已安装 dev.253。应用可以启动。安装传输后仿真 ADB 隧道离线；用已验证的同一设备 LAN ADB 查询确认安装成功，仿真重连报告托管 Harness 访问被禁用，故此轮不能声称完成远程 Harness 工具调用。
- 实机 Termux 已安装，但 VibeKits 的 `com.termux.permission.RUN_COMMAND` 初始为 `granted=false`，Termux 的 `allow-external-apps` 仍是注释状态。测试时临时授予了前一权限，随后已撤销恢复原状；后一配置始终未开启。因此工具命令实际执行、原生 APK 编译和从商城安装均未通过。专用组件必须避免让用户自行搭建整套 Termux 环境。
- 修正组件查询优先级：即使设备已有 Termux，也先检查 KEMI 商城是否上架可信的专用组件，避免 Termux 抢先返回遮蔽升级路径；商城不可用时仍报告已安装 Termux。新增对应回归，`app_center_test.dart` 31 项通过，Dart 静态分析通过。
- PAD63 已验证从原 Termux 安装目录迁移后的工具链：`aapt version`、OpenJDK `java -version`、`javac` 编译、系统 Dalvik 运行 `dx`、`apksigner` 版本与签名均在 `/data/local/tmp/vbk-builder-probe` 独立路径成功。用该链在 PAD 本机生成的最小原生 APK 通过签名校验、`pm install`，并在 `Display #2` 启动。非调试目标 SDK 31 和 35 的应用进程均成功从自身私有目录启动携带依赖的 `aapt`；这只证明 PAD63 这版系统可行，不代表其他 Android 版本已验收。
- 从这套已验证文件制成 346 项、89 MB 的隔离工具链 ZIP，SHA-256 `367d0f2327bf28b57509351fd06afb38656e7e9b2562a9ad46e72720c91f1452`；它是 PAD63 开发快照，正式发布前仍需整理上游包版本、许可与可复现来源，不能把此快照直接当最终供应链证明。
- 开发快照内 `java-21-openjdk/release` 自报 Termux OpenJDK `21.0.12`，`aapt` 二进制含 `android-16.0.0_r4`；这与 Termux 的 [OpenJDK 21](https://github.com/termux/termux-packages/blob/master/packages/openjdk-21/build.sh) 和 [aapt](https://github.com/termux/termux-packages/blob/master/packages/aapt/build.sh) 配方对应。Termux 的 [apksigner 配方](https://github.com/termux/termux-packages/blob/master/packages/apksigner/build.sh) 指向 Android SDK 构建工具。ZIP 包含 JDK 自带 `legal` 目录；其他所含动态库及 Android 工具的精确上游包修订、许可文本和官方二进制校验清单仍未齐，不能仅凭这些版本字符串宣称正式组件供应链可复现。
- 已从 Termux [官方 aarch64 包索引](https://packages.termux.dev/apt/termux-main/dists/stable/main/binary-aarch64/Packages.gz) 下载并按索引 SHA-256 校验原始 `.deb`。快照中的 `aapt`=`16.0.0.4-2`、`apksigner`=`37.0.0`、`dx`=`1:1.16-7` 逐字节匹配；OpenJDK 21.0.12 的 336 个快照条目全部按内容哈希核对：332 个来自 `openjdk-21`（含其原始符号链接目标），另外 4 个图形库来自同版本 `openjdk-21-x`，该子包精确字节与官方索引 SHA-256 `e974be513dfd355bda6c9a793e69636298d3ac5f41e561fb8557e1909e979485` 一致。`libandroid-shmem`=`0.7`、`libandroid-spawn`=`0.3`、`libexpat`=`2.8.5`、`libpng`=`1.6.58` 也逐字节匹配；`android.jar` 与本机官方 Android SDK API 35 文件 SHA-256 同为 `4566663c3876e022b4fa4ced8c8697c4ab1688267f090114fd92d027b32e619b`。旧版 `zlib 1.3.1` 的[历史镜像包](https://cdn.doomsdayrs.page/termux/apt/termux-main/pool/main/z/zlib/)中 `libz.so.1` 与快照逐字节匹配；`zlib 1.3.1-1` 与快照不符。SDK JAR 再分发许可仍须完成门禁，因此当前候选只供 PAD 真机功能验收。
- `libc++_shared.so` 溯源已完成：从 [Google 官方 NDK r27c](https://dl.google.com/android/repository/android-ndk-r27c-linux.zip) 分段读取 arm64 库，原件 1,794,776 字节、SHA-256 `f9992c4ba6b7c5a716e3a202fceb1ce029d6a2b0605838ac6b3219f489dd7970`，与组件快照具有同一 ELF Build ID `b04675a35ad96f8a9dcaa073e3bd31d4536f00ad`。对原件执行 `llvm-strip --strip-unneeded` 后，两者仅差 Termux `termux-elf-cleaner` 清除 `AARCH64_BTI_PLT` 动态项的 10 个字节；按此变换得到与快照逐字节一致的 SHA-256 `5a6b08716b673bbb58c6bcdca56d4cbc646d29c2b50720f02987c6bb215c9a45`。NDK [构建系统文档](https://android.googlesource.com/platform/ndk/+/ndk-r28-release/docs/BuildSystemMaintainers.md)要求使用共享 libc++ 时将其放进 APK；NCSA 文本已随组件打包。
- API 35 的 `android.jar` 已与 [AOSP fullsdk 官方预置文件](https://android.googlesource.com/platform/prebuilts/fullsdk/platforms/+/refs/heads/main/android-35/android.jar)核对：两者均为 27,092,450 字节，本机文件的 Git blob ID `2d6652edf0fb6046a23638f3a2f2c6246c745b08` 与 AOSP 页面完全一致。这解决精确来源问题，但不自动证明再分发许可；[Android SDK 条款 3.4/3.5](https://developer.android.com/studio/terms)对普通 SDK 组件限制再分发，对开源授权组件例外。该预置 JAR 的适用许可与通知文本仍需逐文件确认，在此之前商城发布门禁继续 BLOCK。
- 2026-09-24 再核对官方条款：第 3.4 条明确限制 SDK 组件再分发，第 3.5 条只豁免**已有明确开源许可的具体组件**；API 35 平台包声明 `android-sdk-license`，`android.jar` 内仅有 `NOTICES/libcore-NOTICES.txt`，不能由 AOSP 仓库可公开下载或其他目录的总许可反推整包可再分发。当前 91 MB 组件保留为内部功能候选，商城公开发布需先取得该 JAR 的明确许可依据，或换成可逐文件证明许可的 Android API 编译桩并重新做离线编译/签名及包大小验收；不得让 PAD 首次编译时自行下载 SDK 来规避门禁。
- 新增独立 `com.vibekits.vibekits.component.builder`：目标 SDK 35，Release APK 约 87 MB，正式 PAD 证书 SHA-256 `c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8`。组件无开机常驻服务，只允许同签名调用的 Binder 接口；源码和 APK 通过文件描述符交换，任务状态落盘，解包有路径、数量与大小约束。PAD63 安装后组件自身离线编译/签名自检回报 `buildReady=true`。
- 同签名的独立测试客户端在 PAD63 经 Binder 递交源码 ZIP，组件回传 8,535 字节已签名 APK；客户端复核包名 `com.vibekits.builderipcprobe` 与 SHA-256 `5d8085262e9c80f846c30f02b0dca6f5e2865c53c49b81645f6e9a3f65faa897`。这证明跨应用 IPC 与真实编译闭环，不等同于 VibeKits Harness 自己已调用成功。
- 宿主新增同签名 Binder 客户端及 `builder_component_build/task_status/cancel/install_apk` 工具，任务源码限于 PAD 工作区，完成时重新核对 APK 包名、字节、SHA-256。宿主 Release Kotlin 编译、Dart 静态分析和 Harness/商城回归通过；此版宿主尚未安装到 PAD63 做 Harness 会话实测。PAD63 随后局域网 ADB 与仿真 ID 均暂时离线，故主程序端到端验收、断网/重启验收及商城下载升级仍未完成。
- 当前组件只支持有 `app/src/main/AndroidManifest.xml` 和 Java 源码的 Android 项目，可包含 XML 资源；使用组件私有的开发签名，不支持把任意 Flutter/Kotlin/C++/Gradle 工程误报为可编译。下一阶段须完成宿主实机调用、系统安装确认和恢复验收，再取得可复现供应链证据并发布可信商城条目。未完成这些前 P06/P12/P13 仍为 BLOCK。
- 宿主源码入口已改为相对当前 Harness 工作区的项目路径（根目录填 `.`），由 Flutter 桥先拒绝绝对路径、`..` 和符号链接，再由 Android 宿主核对真实工作区边界；不再把工作区硬编码为默认目录。每次 Binder 状态/构建调用完即解除绑定，避免只查一次状态便让服务空闲常驻；首次解包及自检最多等待 90 秒再返回状态，诊断页在后台等待，主线程只更新文字。
- 2026-09-24 本轮 Harness/商城 73 项测试通过（1 项按条件跳过），新增相对路径契约、Termux 不可代替正式组件、商城 `nextAction` 分流及系统安装有界等待回归通过；Dart 静态分析和 Android 宿主/组件 Release 编译通过。最终组件候选 `1.0.1`（versionCode 2）Release APK 为 91,235,075 字节，SHA-256 `413a567d6dc058a890ba83ece8f197f2106679ffdbe168fa58cebcb2bdb6f512`，证书 SHA-256 为 `c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8`，内嵌工具链 ZIP 哈希与固定值一致；包内增加了 `licenses/` 第三方许可声明。宿主候选 `1.9.0-dev.254+2254` 为 86,846,549 字节，SHA-256 `019962eb51ed76fbc077b0b78ae27da97d72da59419b9375dea83026ee1f1698`，同一证书。两个包尚未在 PAD63 以最终字节实装验证，不能据此解除真机与商城门禁。
- 编译任务的商城查询现在只读取专用包 `com.vibekits.vibekits.component.builder`；不再先探测 Termux、也不把 Termux 的未知安装状态当作专用组件查询失败。Termux 仍有独立诊断探针，但不能通过 `builder_component_install` 安装为编译依赖。针对“Termux 状态未知但专用组件已上架”的回归和全部商城/Harness 71 项测试通过。
- PAD63 在本轮重试时，局域网 ADB `192.168.3.63:5555` 连接超时，仿真 ID `6795854383` 返回 `Remote desktop is offline`。设备恢复后先安装上述精确哈希候选，验证首次自检、独立客户端 Binder 编译、宿主 Harness 会话、构建完释放服务、重启持久状态和第二屏运行。离线期间不改用控制端代编充当 PAD 验收。
- 2026-09-24 最新核对：仿真 `connection_status` 对 ID `6795854383` 返回 `connected=false`；商城 Android 公开搜索固定包名 `com.vibekits.vibekits.component.builder` 返回 `total=0`。宿主源码提交 `c27266b` 已统一移动端提示、工具描述和生成能力目录，禁止“未上架时改装 Termux”的旧引导；Harness/商城回归 77 项通过、1 项条件跳过，目标 Dart 静态分析通过。此前 dev.254 已签名 APK 的字节不含该提交，不得作为此次指令修正的最终产物。
