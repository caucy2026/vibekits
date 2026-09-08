# 2026-09-08 Harness 启动失败复现证据

## 现场事实

13:21 日志报错：profiles/node_modules/@deepseek-ai/dsh 既不是 symlink，也不是官方 dsh-managed module proxy，官方启动器退出，exitCode=1。Node.js v22.19.0 是异常尾行，不是根因。

13:22 后续日志打印过启动地址，但本轮检查该 PID/端口已不在运行；不能据此宣称当前 UI 已恢复。

## 本轮真实运行验证

脚本：tool/verify_harness_legacy_startup.dart。

运行时：.tmp/cloud-main/build/macos/Build/Products/Release/Vibekits.app 内置 Node 与官方 DSH，不重新构造模拟 Web 服务。

步骤：在独立临时 DSH_HOME 构造旧版同名普通包 → 启动官方 CLI 复现报错 → 执行当前 migrateHarnessLegacyModules → 再启动并 HTTP 检查 → 停止该测试子进程并重复启动。

实际结果（脚本退出码 0）：

- conflictReproduced: true
- backedUpPackages: 1
- startupAfterMigration: true
- secondStartup: true
- userDataModified: false
- modelRequests: 0

原始 JSON：/var/folders/rz/9rnd37v141l9hbwmd4j4l_1h0000gn/T/vibekits-startup-proof-ITLJtS/result.json。

测试结束后关闭了脚本自己启动的进程，保留隔离配置及冲突包备份。未关闭其他用户进程，未修改用户聊天/插件目录。

## 未通过的门禁

这是“官方运行时 + 当前迁移函数”的真实进程启动验证，不是重新编译 App 后的 UI 点击验收。此前出错包为什么未成功应用迁移，仍需结合构建来源/运行时路径核查；当前源码与 .tmp/cloud-main 源码都有迁移调用，不能据此猜测二进制构建内容。

远程协助完整 UI、ID 寻址/配对/中继、63 双机操作仍未完成，本证据不能替代这些验收。

## 后续真实 UI 验证（同日 13:42 起）

通过 Computer Use 打开精确 .tmp/cloud-main/build/macos/Build/Products/Release/Vibekits.app，实际显示 v1.9.0-dev.161+2161，官方 Harness 首页成功呈现。随后真实点击：侧栏展开 → 设置弹窗 → 插件管理页 → 关闭弹窗，均有可见页面变化；未发送模型消息、未安装插件、未修改权限。

最新启动日志：harness-web-2026-09-08T05-42-10.299140Z.log。该源码目录 HEAD 为 84bd7c5，存在其他工作者未提交改动；主工作区仍为 dev.160，不能混称同一候选。

重要：对该 App 执行 codesign --verify --deep --strict 返回 invalid signature（arm64，代码或签名已被修改）。因此仅记录启动/点击诊断通过，不算签名验收或正式发布通过。未将该候选复制到 bin，未覆盖其源码或重签其他工作者的候选。
