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

迁移、会话保留、幂等、代理/自定义插件保留、旧 App 根链接不变、错误摘要及本地 URL 校验已有定向测试。
真实旧链接已备份到用户 Harness/module-migration-backups/linked-root-bZK6Ah/node_modules，未删除数据。
旧运行 App 重试后进程不再退出，暴露认证 URL 兼容缺陷，已纳入本次修复。最终新候选 UI 验收与编译结果待补。
首次 Release 编译被缺失官方 Universal GitHub CLI 阻止；已运行项目固定 SHA 校验脚本补齐，不跳过打包门禁。
