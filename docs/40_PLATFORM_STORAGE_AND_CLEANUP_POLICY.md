# 多平台存储与清理策略

## 不可违反的原则

1. 持久数据、可重建缓存和临时调试数据必须分目录，禁止用当前工作目录推导。
2. 密码、API Key 和订阅凭据只能进入平台安全凭据库。
3. 清理器先选择平台策略，再发现路径；任何删除仍需经过平台删除边界二次校验。
4. Windows、macOS、Android 规则不可混用。不支持的能力必须在 UI 和 Harness 中明确说明，不能调用后才报模糊错误。
5. APP 启动时必须对设置、模型、下载、缓存和 Harness 调试目录执行创建、写入、读取、删除探针；配置路径不等于实际可用路径。

## 默认位置

| 数据 | Windows | macOS | Android |
| --- | --- | --- | --- |
| 设置/历史 | Windows 官方应用支持目录（当前为 `%APPDATA%\com.vibekits\vibekits`） | macOS 官方 Application Support 应用目录 | Android 官方 `<app>/files/Vibekits` |
| 模型 | `%LOCALAPPDATA%\Vibekits\Models`，避免大文件进入 Roaming | Application Support 应用目录下 `Models` | `<app>/files/Vibekits/Models` |
| 下载缓存 | Windows 官方应用缓存目录下 `downloads` | macOS 官方应用缓存目录下 `downloads` | `<app>/cache/Vibekits/downloads` |
| Harness 调试 | `vibekits.exe` 同级 `tmp` | `~/Library/Logs/Vibekits/Harness` | `<app>/cache/Vibekits/Harness` |
| 密码/Key | Windows Credential Manager | macOS Keychain | Android Keystore |

旧版 Windows、macOS、Android 设置会从原 LocalAppData、工作目录或临时目录读取一次并迁移到新的持久目录，SSH、ADB 等历史不会因升级丢失。

## 清理能力差异

### Windows

- 支持多个本地磁盘、系统盘完整占用分析、已安装软件清单与正式卸载器。
- 扫描 Windows 系统缓存、应用缓存、开发缓存和日志。
- System32、WinSxS、磁盘根等保护边界永不直接删除。

### macOS

- 只扫描当前用户 `Library/Caches`、`Library/Logs`、开发工具缓存和规则明确的应用缓存。
- 谨慎项目进入废纸篓；不伪装成 Windows 式全盘分析，不扫描系统目录，不显示 Windows 卸载入口。

### Android

- 只扫描 Vibekits 私有 cache/tmp、Harness 日志和调试截图。
- 不访问其他应用、系统目录、共享存储或 Download；应用沙箱外候选即使被错误发现也会被删除器拒绝。

Harness 调用 `vibekits.system.capability_check` 后，可从 `platform.storageLocations` 和 `platform.cleanup` 获得当前环境的真实位置与能力边界。

## 不可写目录降级

1. 持久数据优先使用系统应用支持目录，不可写时切换到用户文档目录。
2. 只有两个持久目录都不可写时才使用临时应急目录，并在设置界面与 Harness 能力结果中明确标记数据可能丢失。
3. 缓存和下载目录不可写时切换到系统临时缓存，不影响设置、历史和凭据。
4. Windows 安装目录下的 `tmp` 不可写时，Harness 调试目录自动切换到应用缓存；禁止因安装在 `Program Files` 导致智能体无法启动。
