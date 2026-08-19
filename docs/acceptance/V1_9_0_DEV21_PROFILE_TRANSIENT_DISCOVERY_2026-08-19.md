# Vibekits 1.9.0-dev.21 Windows 跨用户瞬态目录发现验收

版本：`1.9.0-dev.21+31`

## 问题与结论

旧算法只处理当前用户的 `%APPDATA%/%LOCALAPPDATA%` 和已知固定规则。它不会在用户未点名时识别 `C:\Users\Default\AppData\Roaming\ESTLOG`，系统盘报告也只会把整个 `Users` 归类为正常用户数据。

本版本增加通用发现器，不硬编码 ESTLOG：

- 枚举系统盘 `Users` 下所有真实配置目录，包括 `Default`。
- 只查看 `AppData/Roaming`、`AppData/Local` 的应用层和下一层目录，不做无界全文扫描。
- 目录名明确为 cache/log/temp/crash，或目录直接存在日志/转储扩展名时才建立扫描目标。
- 日志目标只列出超过 7 天的 `.log/.etl/.dmp/.hprof/.trace/.tmp/.bak`。
- `.db/.sqlite/.json/.yaml/.ini/.conf/.config` 明确排除。
- 自动发现目标参与后台扫描，但候选类别为高风险，默认不勾选，只允许用户复核后通过既有回收站流程清理。

## 闭环证据

- 真实路径 `C:\Users\Default\AppData\Roaming\ESTLOG` 存在，但检查时为空，因此没有虚报候选。
- 临时系统盘夹具创建同一路径结构：10 天前 `encrypt-service.log` 被自动发现；`settings.json` 和当前 `current.log` 均未进入候选；候选 `defaultSelected == false`。
- `flutter analyze` 0 问题。
- 清理目标、后台扫描与清理界面定向回归 22/22 通过。
