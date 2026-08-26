# v1.9.0-dev.109 Harness 幽灵会话删除验收

## 问题

旧会话在侧栏仍然可见，打开后显示 `session-not-found`，重复点击“删除会话”也无法从列表消失。

## 根因与修复

- DSH 在进程内保存工作区/会话投影；旧实现只修改磁盘，运行中的投影仍会继续提供旧记录。
- 会话目录删除后留下空的临时工作区目录，DSH 下次发现时仍可能生成无效列表节点。
- 新流程先停止 DSH，再删除精确会话、`workspace.json`、`session_projcache.json` 引用和空父目录，最后在原 WebView 中重新启动并刷新列表。
- 启动维护仅删除名称严格匹配 `--*vibekits_harness_native_*--` 的旧 VibeKits 验收目录；真实工作区不在匹配范围内。

## 验收结果

| 项目 | 结果 |
| --- | --- |
| 旧 VibeKits 自测会话目录 | 15 → 0 |
| 保留真实工作区目录 | 2 |
| 有效会话索引 | 2 |
| 精确删除与路径防越界单测 | 通过 |
| 空工作区清理单测 | 通过 |
| 自测目录/真实目录隔离单测 | 通过 |
| Harness 启动配置回归 | 通过 |
| Windows Release | `v1.9.0-dev.109+119` 构建成功 |
| 前台 APP | 进程正常响应 |
| 本次 DSH 后端就绪 | 3,934 ms |

Release：`D:\vibecode\vibekits\build\windows\x64\runner\Release\vibekits.exe`
