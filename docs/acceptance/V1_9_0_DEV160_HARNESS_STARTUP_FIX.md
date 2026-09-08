# dev.160 Harness 启动兼容修复

## 现场原因（2026-09-08）

08:55 日志 exitCode=1：官方 DSH 拒绝普通 fallback 模块目录。进一步检查发现 profiles/node_modules 根链接指向旧安装包内部，因此不是简单的缺少 Node。现场运行的是缓存中的 dev.158。

## 修复

- 启动前迁移旧模块根链接：仅重命名链接备份，创建用户可写目录，不遍历修改签名 App。
- 对独立可写目录中与内置包同名的旧复制依赖保留备份；保留官方代理、已有符号链接及第三方独有插件；不碰会话、项目和凭据。
- Web/原生启动共用迁移代码；Windows/macOS 共用 Dart 实现。
- 接受官方 stdout 宣告的认证 URL，只接受预期本地 host/port；不关闭官方认证。日志按完整行脱敏 token。
- HTTP 401/403 不再被当作控制台已就绪。错误展示优先真正 Error，不再仅显示 Node 版本。
- 版本与 LMCP 元数据统一升为 1.9.0-dev.160+2160。

## 验证状态

迁移、会话保留、幂等、代理/自定义插件保留、旧 App 根链接不变、错误摘要及本地 URL 校验已有定向测试。与 deepseek_harness_test、harness_runtime_log_store_test 联合执行共 29 项通过；本轮源码定向 analyze 无问题。
真实旧链接已备份到用户 Harness/module-migration-backups/linked-root-bZK6Ah/node_modules，未删除数据。
旧运行 App 重试后进程不再退出，暴露认证 URL 兼容缺陷，已纳入本次修复。最终新候选 UI 验收与编译结果待补。
首次 Release 编译被缺失官方 Universal GitHub CLI 阻止；已运行项目固定 SHA 校验脚本补齐，不跳过打包门禁。

修复分支 `fix/harness-dev160-startup` 已推送，代码提交 `f59070e` 和 `9dcb485`；远端 main 同期新增同事提交，未强推覆盖。

## 最终本机结果

- 最终代码 macOS Release 编译成功（752.8 MB）。
- Developer ID 签名验证成功，35 个 Mach-O；签名运行时检查：ARM/Intel Node v22.19.0、JIT allowed、DSH launchable。
- 用精确路径 `build/macos/Build/Products/Release/Vibekits.app` 启动；真实截图显示 dev.160+2160、官方“探索未知之境”控制台、工作区及输入框，启动错误与认证提示均消失。
- 旧普通依赖冲突以及认证入口问题完成本机启动闭环；没有发送模型任务或执行 LAN 控制。
- 未完成本版本 Apple 公证、完整 Intel 真机/Windows 验收或商城发布，候选未覆盖 bin 中正式版本。
