# v1.9.0-dev.24 ESTLOG 与系统盘占用验收

日期：2026-08-19  
平台：Windows 10 x64（系统盘 `C:`）

## 1. 真实容量

| 项目 | 字节 | GiB |
|---|---:|---:|
| 总容量 | 85,899,341,824 | 80.00 |
| 已使用 | 78,665,613,312 | 73.27 |
| 剩余 | 7,233,728,512 | 6.74 |

目录树扫描使用文件逻辑长度定位来源。Windows 组件存储存在 NTFS 硬链接，同一物理数据可从多个目录看到，因此下列目录逻辑量不能相加后当作物理占用。

## 2. 根目录占用来源

| 来源 | 目录逻辑量 | 判断 | 建议 |
|---|---:|---|---|
| `C:\Windows` | 31.15 GiB | 系统必需，含硬链接重复计数 | 不手工删除；仅使用 Windows 官方维护入口 |
| `C:\Users` | 27.06 GiB | 用户数据与应用配置，最值得细分 | 只清缓存/日志/过期构建物，不整目录删除 |
| `C:\Program Files` | 10.65 GiB | 已安装 64 位程序 | 不直接清文件；卸载不用的软件 |
| `C:\Program Files (x86)` | 8.86 GiB | 已安装 32 位程序/SDK | 不直接清文件；卸载不用的软件或 SDK |
| `C:\ProgramData` | 4.48 GiB | 服务数据与安装维护缓存 | 逐软件识别；不要删除 Package Cache |
| `C:\Recovery` | 2.09 GiB | Windows 恢复环境 | 保留 |
| `C:\ESTLOG` | 37.49 MiB | EST 加密软件旧日志 | 24 小时前 `.log` 可在确认页清理 |

DISM `/AnalyzeComponentStore` 的只读结果：组件存储资源管理器显示 7.09 GB，实际 7.04 GB；可回收包 1 个，但 Windows 给出“不建议清理”。`WinSxS` 不进入手工删除范围。

## 3. 用户目录进一步拆分

| 来源 | 逻辑量 | 分类 |
|---|---:|---|
| `AppData` | 20.60 GiB | 混合：应用本体、配置、缓存、日志 |
| `.cache` | 1.97 GiB | 多数可再生，但需要关闭对应工具并接受重新下载 |
| `.gemini` | 1.65 GiB | 主要是智能体项目 Git 历史/会话，不按缓存删除 |
| `.codex` | 0.89 GiB | 插件、沙箱运行时、会话与少量临时文件混合 |
| `.vscode` | 0.77 GiB | 扩展与配置，不能整目录清理 |
| `.gradle` | 0.54 GiB | 可再生构建缓存，清后首次构建变慢 |

已定位的重点样本：

- 用户 Temp 总逻辑量约 2.27 GiB，但超过 24 小时的文件只有约 0.41 GiB；其余主要是当天仍可能活动的 Flutter 临时构建目录，当前不选。
- 企业微信 `upgrade` 约 1.53 GiB，是升级程序与版本包；可作为“关闭软件后谨慎复核”项，不能按通用缓存默认删除。
- VS Code `workspaceStorage` 约 0.98 GiB，其中 7 天前约 0.93 GiB；它包含工作区状态，不是纯缓存，清理会丢失工作区上下文。
- `secoresdk\360se6` 约 1.43 GiB，包含浏览器/安全组件和多个版本；不能整目录当垃圾。其中 `.old` 版本约 0.56 GiB，仍需确认所属软件当前版本和进程状态。
- Antigravity `brain` 约 1.55 GiB，主体为任务内部 Git 对象；不是调试截图缓存。可识别的 `.tempmediaStorage` 图片约 42.6 MiB。
- npm cache 约 0.21 GiB、`.dartServer` 约 0.28 GiB、Antigravity updater 约 0.26 GiB、Puppeteer 运行时缓存约 0.67 GiB、Pub 包缓存约 0.56 GiB；均可再生，但清理后可能重新下载或降低首次启动/构建速度。

## 4. ESTLOG 闭环

- 路径：`C:\ESTLOG`
- 实际文件：24 个，均为 `.log`
- 符合“超过 24 小时”规则：24 个
- 候选总量：39,313,476 字节（37.49 MiB）
- 最大文件：`emlsnd.log` 19.90 MiB、`tiface.log` 15.96 MiB
- 规则默认参与扫描并默认选中候选；清理仍经过确认页，未在本次研发验收中直接删除真实文件。

## 5. 自动验收

- `flutter analyze`：0 问题
- `cleanup_targets_test.dart`、`system_drive_analyzer_test.dart`、`cleaner_widget_test.dart`：26/26 通过
- 覆盖：旧目录版本自动迁移、ESTLOG 年龄/扩展名边界、独立 Isolate/取消、真实容量摘要、目录逻辑量与硬链接重复计数报告。
- Windows Release 构建成功；`FileVersion` / `ProductVersion` 均为 `1.9.0-dev.24+34`。
- EXE SHA-256：`BBE31C1E67C4C0D6205ADB01800F38BB8643A513F8E8820BA8978655DE7547E2`。
- Release 隐藏启动后进程可响应；测试结束后精确结束本次 PID，构建目录下 Harness/Node 子进程残留为 0。隐藏启动没有可交互主窗口，因此该项不作为“用户点击关闭”证据。
