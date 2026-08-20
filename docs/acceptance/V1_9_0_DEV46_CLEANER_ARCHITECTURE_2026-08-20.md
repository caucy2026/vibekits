# v1.9.0-dev.46 清理任务入口与外部规则库验收

日期：2026-08-20  
版本：`1.9.0-dev.46+56`  
范围：CLN-113、CLN-114；CLN-115 仅关闭架构准则，不宣称后续能力已完成

## 1. 本版交付

- 清理竞品研究与后续架构固化到 `docs/24_CLEANER_COMPETITIVE_ARCHITECTURE.md`。
- 清理结果新增推荐清理、软件缓存、大文件 / 下载、不常用软件、深度清理五个任务入口。
- 随包 `assets/cleaner/windows_rules_v5.json` 提供 7 条外部软件规则；解析在后台 Isolate 完成。
- 候选项携带显式风险和影响说明；高风险默认不选，分类批量选择跳过高风险。
- 外部规则只能声明有界目录扫描和 `recycle`；危险动作、重复 ID、未知类别/风险、越界参数逐条拒绝。

## 2. 自动验证

| 验证 | 结果 | 证据摘要 |
|---|---|---|
| 清理定向测试 | PASS，34/34 | 规则解析/拒绝、真实临时目录候选、风险传播、Windows 目录规则、后台发现/取消、五入口横向操作、白名单、分批列表、容量总结、多磁盘与卸载器 |
| `flutter analyze` | PASS | `No issues found`，32.1 秒 |
| Windows Release | PASS | `flutter build windows --release`，140.5 秒 |
| 版本资源 | PASS | FileVersion / ProductVersion 均为 `1.9.0-dev.46+56` |
| 规则资产 | PASS | Release 内 `windows_rules_v5.json` 存在，3937 bytes |
| 启动冒烟 | PASS | 隐藏启动 6 秒，进程未退出且 `Responding=True`；随后只结束本次精确 PID |

定向测试命令：

```text
flutter test test/cleanup_rule_database_test.dart test/cleanup_scanner_test.dart test/cleanup_targets_test.dart test/cleanup_background_runner_test.dart test/cleaner_widget_test.dart --reporter compact
```

Release 可执行文件：

```text
D:\vibecode\vibekits\build\windows\x64\runner\Release\vibekits.exe
```

## 3. 测试发现并关闭的问题

1. 旧 ESTLOG 测试仍要求谨慎日志默认选中，与新风险合同冲突；现已改为 `cautious` 且默认不选。
2. 五入口重组后，旧界面测试仍在默认页寻找软件缓存；现已按真实横向入口切换验证，并覆盖懒加载滚动。
3. 内部高风险类别配合显式 `safe` 时可能显示“推荐”文案；界面现在显示有效风险“需确认”，避免风险标签与选择行为矛盾。

## 4. 未完成边界

- “大文件 / 下载”当前聚合下载建议和重复文件，不等于 MFT/USN 全盘极速大文件索引。
- “不常用软件”当前只显示已安装应用和正式卸载器；没有可靠使用证据时不做“不常用”结论。
- 外部规则当前随 Release 离线发布；签名在线更新、原子回滚和 macOS 外部规则尚未实现。
- 软件身份统一、卸载残留、Restart Manager 占用解释、缓存增长趋势仍按架构文档后续推进。
- 本版未删除任何真实用户文件，也未把竞品专有代码或 UI 复制进项目。
