# VibeKits dev.143 macOS Intel 与执行时间线验收

## 验收目标

1. Harness 执行过程像 Codex 一样先显示清晰事件摘要，默认不展开原始工具 JSON。
2. macOS 产物同时包含 arm64/x86_64，Intel macOS 10.15 可启动 App。
3. 明确记录官方 Harness 的真实最低系统，不用不可运行的旧 Node 伪造兼容。
4. 本机包通过深度签名验证；对外包必须 Developer ID 签名并获 Apple 公证。

## 界面合同

- 运行中时间线与已保存时间线默认折叠。
- 折叠栏显示“执行时间线 · 完成/总步数”和最新动作。
- 展开后每步只显示标题、状态、目标、耗时和有界摘要。
- 超长详情必须二次点击才打开，不得挤占主会话。
- 运行任务的停止按钮始终可达，折叠不影响停止和审计。

## macOS 兼容合同

| 部件 | Intel | ARM | 最低系统 |
|---|---|---|---|
| VibeKits App | x86_64 | arm64 | Intel 10.15 / ARM 11.0 |
| Flutter/App.framework | x86_64 | arm64 | 同 App |
| ADB | x86_64 | arm64 | 随 App 校验 |
| Harness Node 22.19.0 | x86_64 | arm64 | 11.0 |
| ripgrep/node-pty/sharp | x64 包 | arm64 包 | 由发布脚本核对 |

Node 18.20.8 虽支持 Intel 10.15，但 DSH 启动会因 `node:util.parseEnv` 缺失失败，不允许作为发布运行时。

## 验证命令

```bash
/Users/newlink/flutter/bin/flutter analyze --no-pub
/Users/newlink/flutter/bin/flutter test --no-pub test/deepseek_harness_test.dart
./tool/verify_macos_release_compat.sh build/macos/Build/Products/Release/Vibekits.app
./tool/sign_macos_release.sh build/macos/Build/Products/Release/Vibekits.app
codesign --verify --deep --strict --verbose=2 build/macos/Build/Products/Release/Vibekits.app
```

## 签名/公证门禁

本机已恢复 `Developer ID Application: zhen ji (26T5WV4GLP)` 身份和 `KEMI_NOTARY` profile。dev.143 已完成 Developer ID 签名，但在用户明确授权将 App 上传 Apple 前，不得标注“Apple 已公证”。对外发布时执行：

```bash
VIBEKITS_DEVELOPER_ID_APPLICATION='Developer ID Application: ...' \
VIBEKITS_NOTARY_PROFILE='vibekits-notary' \
./tool/sign_and_notarize_macos_release.sh \
  build/macos/Build/Products/Release/Vibekits.app
```

只有脚本返回 Developer ID 深度验签通过、notarytool Accepted、staple validate 和 Gatekeeper accepted，才能复制为对外正式包。

## dev.143 实测结果

- `flutter analyze --no-pub`：0 issue。
- Harness UI/状态/工具桥/GitHub 代理/ADB 会话联合回归：74 通过，1 项按平台条件跳过，0 失败。
- 时间线 Widget 回归单独执行：21/21 通过，覆盖运行中与历史默认折叠、展开和停止。
- Release：`bin/Vibekits.app`，版本 `1.9.0.143 (2143)`，606.6 MB。
- 签名：主程序、ADB、Harness 原生件和 frameworks 均使用 `Developer ID Application: zhen ji (26T5WV4GLP)`、hardened runtime 和 Apple 时间戳；App `codesign --verify --deep --strict` 通过。
- Intel 真运行：最终 `bin` 产物以 Rosetta 启动，PID 28071，`Code Type: X86-64 (translated)`，版本 1.9.0.143 (2143)，UDP `*:47831` 监听正常。验收后已恢复原生模式运行。
- 随包 DSH：ARM 和 `arch -x86_64` 两种模式的 `--help` 均返回成功。
- Developer ID 签名后 SHA-256：App executable `97b01383adb9b56b751d6be1970c0e823febe8c97455295a091f401b298ec066`；App.framework `26fc41e5fdb153d6a58e97187cd1a6ec329669c19e73aa2e712ad0a20cdc0691`；Harness Node `f0500090154ec38e536d0b39a99648db72f78ba174fa5ae3015801f5223ee7c1`。
