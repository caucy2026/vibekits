# dev.218 macOS 12 Harness 启动回归（2026-09-17）

状态：**BLOCK**。macOS 12 的 JavaScriptCore 兼容缺口已修复并在目标机验证；完整 App 尚未完成 Apple 公证和目标机启动验收。

## 故障与修正

- 目标设备 `1321656264`：macOS 12.6.4、Safari/JavaScriptCore 15.6.1。现有兼容客户端的文档预览模块在模块初始化时执行 `typeof Iterator.prototype.join`；系统 JSC 中 `Iterator` 为 `undefined`，该表达式抛出 `ReferenceError`。历史 Harness 日志并未直接记录 WebView 控制台异常，因此它是已实测的兼容性缺口，不能冒充对过去每一次白屏的唯一归因。
- `tool/transpile_harness_web_macos.mjs` 现在在模块脚本前创建基于原生迭代器原型的 `Iterator` 兼容对象。`tool/prepare_harness_runtime_macos.sh` 在打包时执行功能回归，避免以后又产出缺少补丁的运行时。
- `test/harness_macos_compatibility_test.dart` 和 `tool/test_harness_macos12_polyfills.mjs` 固化了加载顺序及实际迭代行为。旧 dev.217 包在负对照中抛错，新 dev.218 包通过。

## 已完成验证

- Flutter 定向回归 18 项通过，覆盖 macOS 12 兼容、中文 ZIP 自动安装、Harness 输入与队列契约。
- 重制 macOS Harness 运行时：55 个兼容客户端模块生成，内置技能与会话重绑检查通过。最终 App 内的兼容、队列提示、同任务补充和同类审批检查通过。
- dev.218 Release 通用包构建通过，主程序含 `x86_64` 与 `arm64`。macOS 12+ 完整运行时验证通过。
- Developer ID `26T5WV4GLP` 签名并深度验证通过，35 个 Mach-O 有效；内置 Node x86/arm64 与 DSH 启动检查通过。
- 目标设备经内置 VibeKits P2P/中继连接、身份验证后，在系统 JSC 执行等价最小探针：修复前 `Iterator=undefined`、访问 `Iterator.prototype.join` 抛 `ReferenceError`；修复后数组迭代结果 `1-2-3`、Map 迭代结果 `a,b`。已断开连接。
- 目标机身份基线：`/Applications/Vibekits.app` 为 dev.160 临时签名副本；另一缓存中的 dev.217 是 `26T5WV4GLP` Developer ID 已公证副本。升级验收应以签名连续的正式副本为准。

## 候选与阻塞

- 源码基线：`main` / `276d971`，工作树另含本轮及既有未提交修改。
- 候选 App：`/Volumes/ORICO/kemi-build-cache/app-release-gate/vibekits/macos/harness-startup-20260917/derived/Build/Products/Release/Vibekits.app`。
- 待公证归档：`/Volumes/ORICO/kemi-build-cache/app-release-gate/vibekits/macos/harness-startup-20260917/Vibekits-dev218-notarization.zip`，SHA-256 `1f58ecd7116adcf8f51dc7e5634b53b483a2a44d86618c24f45230aaf565d323`，约 304 MB。当前 Gatekeeper 判定 `Unnotarized Developer ID`，因此不能作为目标机完整 App 启动通过证据。
- 自动审批拒绝向 Apple 公证服务上传这份具体候选归档，理由是尚无明确的目的地与载荷授权；已向用户提出精确授权请求。
- 自动审批另拒绝向目标设备上传从正式包抽取的 1,831 字节 JSC 探针；没有用别的命令绕过。此前在目标机执行的等价最小探针已通过，但“正式包精确脚本在目标机执行”仍未完成；已提出单独授权请求。
- 尚未在目标设备启动 dev.218 完整 App，也未验证 WebView 首屏、真实 Harness 会话和中文输入法候选窗位置。以上项目保持 BLOCK，不计入通过项。
