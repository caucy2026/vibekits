# Android 被仿真构建与正式签名验证

日期：2026-09-22。结论：BLOCK（签名迁移与端到端功能验收未完成），不是发布通过。

## 已定位并修复

1. NDK 28.2.13676358 已存在。原失败是直接 cargo check 未配置 Android 交叉编译器；按 RustDesk 的 flutter/ndk_arm64.sh 使用 cargo ndk 后，arm64 release 原生库编译成功（4 分 07 秒）。动态链接检查通过。
2. Kotlin 声明的 harnessSetSimulatorAccess 原先没有 JNI 实现，已补全；harnessConnections 原先仍返回空数组，改为真实受管连接快照。最终原生库已核验两项 JNI 导出符号。
3. release Gradle 配置原先无条件使用 debug 签名。现改为显式 KEMI_ANDROID_* 签名输入；未配置时输出未签名候选，不回退 debug 签名。
4. 持久化构建入口：tool/build_android_harness_release.sh。使用现有 RustDesk NDK 脚本、外盘缓存，默认 Rust 并发 4，先校验 JNI 导出再打包。

签名依据：/Users/newlink/kemi/priv/xtqx.md 第 9.1、9.2 节。凭据不写入源码、报告或日志。

## 当前候选

- 包名：com.vibekits.vibekits
- 版本：1.9.0-dev.225+2225（本次为内部修复候选，未发布）
- 路径：dist/candidates/Vibekits-1.9.0-dev.225+2225-android-simulator-kemi-signed.apk
- APK SHA-256：bdaccb06851ba5ba5ec9e9ae9a86cb17e2607050a5cbbd7fc357297600fd8a45
- 证书 SHA-256：c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8
- apksigner：Verifies，APK Signature Scheme v2=true。
- 17 项 Dart 端口、仿真权限状态机和协助界面回归通过。
- 首次端口用例失败原因：本机运行的 Harness 正占用 13080；修正测试前置条件后通过，未停止运行中的应用。

## PAD63 实测阻塞

通过 VibeKits ADB 工具桥连接 192.168.3.63:5555 成功；设备 KEMI Vibe Pads S1 / hi3781v730。
已拉取现有 base.apk 作为回退及签名证据。现有包签名为 Android Debug，SHA-256：
fc84f538928007fb20d1ee43b8fb6bde465708c694b86fdd6a012fef19e2d5aa。
与正式候选签名不同，不能保留数据直接覆盖。不执行卸载或清数据；需要明确批准该应用数据迁移/重装范围后才能继续真机部署。

## 未完成范围

- 正式候选在 PAD63 的安装、启动、界面开关、另一台设备按 ID 入站调用、关闭撤销及重启恢复均未验收。
- Android 大组件商城按需下载仍是设计要求，当前仍有内置模型，组件 APK/Binder/商城条目链路尚未实现；不得宣称完成。
- 不把 JNI 导出、编译或单元测试替代端到端验收。当前候选未上架。

## 证据

/Volumes/ORICO/kemi-build-cache/app-release-gate/vibekits/android-harness-inbound/：
- native-build.log
- apk-build.log
- flutter-regression.log
- pad63-before.apk

## 用户批准签名迁移后的实际操作

用户明确允许在 63 备份可导出数据后卸载重装。备份检查：`run-as` 返回 package not debuggable；`/sdcard/Android/data/com.vibekits.vibekits` 不存在。旧 APK 已备份，私有数据无法导出。

- 卸载旧包：Success。
- 安装原正式签名候选：Success。
- 冷启动进入真实 Harness 界面；进程存在，限定 AndroidRuntime/DEBUG 错误日志未返回崩溃记录。
- 实际点击设置→高级：看到“允许作为仿真机”，默认关闭。本机 ID 为 6795854383。
- 实际开启后失败：PathNotFoundException，试图读取不存在的 `nativeLibraryDir/librustdesk.so`。原生库由系统直接从 APK 加载时不会存在该解压文件。
- 源码修复：Android 服务返回 `applicationInfo.sourceDir` 供运行时计算安装包指纹，替代假定存在的解压库路径。
- 重编译签名通过，最终本地候选 SHA-256 改为 `a90f0a090f17a5569a383acec081f37fe52d68566dc22be8c51fce4e7bee6826`，证书不变；原 bdaccb... 候选为已发现缺陷的历史候选，不作为通过版本。
- 安装修复候选时 ADB 返回 device offline；随后连接 192.168.3.63:5555 超时。修复版本尚未在 63 安装成功，不能宣称开关或远程入站通过。

当前阻塞已从签名授权变为 PAD63 连接不可用。设备恢复连接后继续覆盖安装上述最终哈希，验证开启、入站调用、关闭撤销及重启恢复。此前卸载重装授权持续有效，不重复询问。
