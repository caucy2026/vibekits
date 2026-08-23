# 清理算法跨平台拆分与迁移基线

版本：v1.9.0-dev.80
日期：2026-08-23

## 1. 结论

清理器采用“公共决策内核 + 平台目标发现 + 平台执行边界”，禁止用一份路径库覆盖 Windows、macOS 和 Android。平台在清理入口确定并传递到后台 Isolate、规则数据库、决策引擎和删除器；运行期间不能混入另一平台规则。

## 2. 可跨平台复用的功能

| 公共能力 | 复用方式 |
|---|---|
| 候选数据模型 | 路径、大小、归属、风险、依据、修改时间和影响说明使用同一合同 |
| 有界扫描 | 最大深度、最大条目数、年龄、大小、包含/排除模式、符号链接保护 |
| 后台任务 | Isolate、最多两个扫描工作线程、进度、取消和前台响应 |
| 决策与计划 | 自动/推荐/复核/受保护四级决策，安全门优先于释放空间目标 |
| 文件身份复核 | 删除前验证文件仍存在且扫描后未被替换 |
| 报告与审计 | 候选、结果、释放容量、失败原因、时间和规则来源 |
| UI 流程 | 扫描只读、查看详情、确认、执行、取消、报告；平台不支持项明确禁用 |

公共层不得包含 `C:\Windows`、`~/Library`、`/data` 等平台路径，也不得直接调用注册表、回收站、Trash 或 Android 存储 API。

## 3. 必须按平台实现的功能

| 能力 | Windows | macOS | Android |
|---|---|---|---|
| 目标规则库 | Windows 版本/软件目录规则 | 用户 Library、Xcode、Homebrew 等独立目录规则 | 仅 Vibekits 私有 cache/tmp/Harness 调试目录 |
| 系统保护边界 | System32、WinSxS、盘符根目录及系统管理规则 | `/System`、`/Applications`、系统 `/Library`、用户资料 | `/system`、`/vendor`、共享存储和其他 App 沙箱 |
| 删除语义 | Windows 回收站；永久删除需独立确认 | 移到当前用户 `~/.Trash` | 私有缓存直接删除；无回收站，越界一律拒绝 |
| 容量与磁盘 | Win32 卷枚举和全盘占用分析 | 后续接入 macOS 卷/系统数据适配器 | 只展示 App 存储；不伪装成系统全盘分析 |
| 软件清单/卸载 | 注册表、安装路径、卸载命令 | 后续使用 bundle/LaunchServices 适配器 | 后续使用 PackageManager 且受系统权限限制 |
| 使用证据 | Prefetch/安装信息等 Windows 证据 | Spotlight/元数据需独立授权与实现 | UsageStats 需用户显式授权，不作为默认权限 |

## 4. 当前实现

1. `CleanupPlatform` 是唯一平台标识，可注入测试。
2. `CleanupTargetDiscovery` 单平台分派：Windows 不再生成 macOS 目标；macOS 不再生成 Windows 目标；Android 只生成 App 私有目标。
3. Windows JSON 规则只在 Windows 界面加载，规则解析器再次核对 `platform` 字段。
4. Android 的共享下载、`/storage/emulated/0`、其他 App 和系统目录不会成为可删除目标。
5. 删除器执行前再次调用平台边界；发现算法即使出错，越界候选仍被跳过。
6. macOS 谨慎规则已正确映射为“需确认”，不再降级成安全规则。
7. 非 Windows 暂停 Windows 式全盘分析，避免用 Windows 目录分类和容量口径产生危险结论。
8. Gradle 缓存不再逐文件清理：仅把 30 天未更新的完整版本目录列为谨慎候选，默认不选，避免破坏 immutable workspace。

## 5. 后续平台适配

- macOS：新增 APFS 容量分类、应用 Bundle 清单、系统数据只读解释和受控 Trash Provider；实机签名构建后开放全盘分析。
- Android：新增 PackageManager/StorageStats 只读统计；只有用户授权后才展示其他 App 占用和系统卸载入口，Vibekits 仍不能删除其他 App 私有文件。
- Windows：保留现有规则数据库、注册表软件清单、卷分析和回收站流程，继续扩充规则时必须标注 Windows 平台。

## 6. 安全门禁

以下任一失败即禁止发布：平台规则混入、Android 越过 App 沙箱、macOS 系统目录进入删除计划、Windows System32/WinSxS 可删除、非 Windows 调用 Windows 全盘分析、删除层未做第二次平台校验。
