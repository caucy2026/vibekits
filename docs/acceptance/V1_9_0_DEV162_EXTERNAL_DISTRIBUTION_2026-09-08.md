# VibeKits dev.162 外部分发复核与重提记录

日期：2026-09-08  
版本：`1.9.0-dev.162+2162`

## 1. Uptodown 后台事实

- 开发者账号可以正常进入控制台。
- VibeKits 后台应用 ID：`1000852511`。
- 应用列表状态：`已拒绝`；详情页状态：`DRAFT`。
- 拒绝通知时间：2026-08-09 14:30。
- 平台原文：`很抱歉，您的应用不符合在 Uptodown 上发布的最低质量标准。`
- 详情页计数：截图 0、描述 0、文件 0；图标未提交。
- KEMI 发送当前状态为 `待修订`。

这些证据说明上次记录中的“未提交”不准确，也说明提交资料没有形成可审核的完整产品页。平台没有明确指出 KEMI 应用中心是拒绝原因，禁止据此臆断或删除产品能力。

## 2. 本轮修复范围

- 使用 1024×1024 正式图标。
- 补齐清晰的英文产品简介、完整功能说明、开发者与官方网站资料。
- 补充能真实展示 Harness、开发工具、应用中心与关于页的产品截图。
- 上传与当前源码一致的 macOS 12+ Universal（x86_64+arm64）Developer ID 签名、公证并 staple 的 ZIP。
- 提交前记录 ZIP 字节数、SHA-256、Apple Submission ID、签名 Team ID 与 Gatekeeper 结论。

## 2.1 macOS Direct 正式候选证据

- App：`bin/candidates/dev162-uptodown/Vibekits.app`
- 最终 ZIP：`bin/candidates/dev162-uptodown/Vibekits-1.9.0-dev.162+2162-macos-universal-notarized.zip`
- ZIP 字节数：`290680125`
- ZIP SHA-256：`d3522b62354dfaa6da2f28918313fa39f51a7fb64d062e752cf1f1239d606820`
- Apple Submission ID：`f8d1fc8f-b149-452f-9009-9be7a3a4d456`
- Apple 公证：`Accepted`
- Stapler：装订及 `validate` 均通过
- Gatekeeper：`accepted`，来源 `Notarized Developer ID`
- 签名：`Developer ID Application: zhen ji (26T5WV4GLP)`，Team ID `26T5WV4GLP`
- 主程序架构：`x86_64 arm64`
- 最低系统：`macOS 12.0`
- 签名后运行时：35 个 Mach-O 深度严格验签通过；Node 22.19.0、x86 Node、JIT 与 DSH 启动验证通过

本候选只用于 Direct/Uptodown 渠道；它不是启用 App Sandbox 的 Mac App Store 包。

## 3. Apple 分发边界

本轮 Uptodown 包属于站外 Direct 渠道，不等同于 Mac App Store 包。Mac App Store 必须使用独立编译渠道，永久移除站外更新和安装其他 App 的能力、启用 App Sandbox，并逐项评估 Harness、Shell、ADB、Git、任意工作区和系统清理能力。不得使用“运行三次后再显示”等审核规避做法。详细方案见 `docs/63_MAC_APP_STORE_DISTRIBUTION_COMPLIANCE_PLAN.md`。

## 4. 发布状态定义

- `已准备`：本地资料与安装包完整，但尚未点击平台最终提交。
- `审核中`：平台返回可追溯提交记录或后台状态明确改变。
- `已发布`：公开产品页可访问且安装包可下载，回下载大小和 SHA-256 与本地一致。
- `已拒绝/待修订`：保持平台原状态，直到新提交被平台受理；不得用本地完成代替平台结果。
