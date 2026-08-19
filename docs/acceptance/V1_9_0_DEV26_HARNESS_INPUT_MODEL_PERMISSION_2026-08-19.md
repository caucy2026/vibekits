# v1.9.0-dev.26 Harness 输入、模型与权限验收

日期：2026-08-19

## 验收目标

- API Key 输入框支持系统剪贴板粘贴，不要求手工逐字输入。
- 模型按钮的二级菜单列出官方 DeepSeek V4 Flash/Pro。
- 推理等级二级菜单列出官方适配器提供的 Off/Low/High/Max。
- 中文界面不再显示 `Workspace Write`，内部权限值和官方审批语义不变。
- 兼容修改由运行时准备脚本稳定复现，不依赖被 Git 忽略的本机 npm 目录。

## 实现约束

- 粘贴内容仅发送给当前获得焦点、未禁用且非只读的 Web input/textarea。
- 剪贴板值不进入日志、普通设置或命令参数。
- 模型和推理等级仍来自官方 `sessions.models` 目录，不在 Flutter 中伪造列表。
- 权限只改显示名：`workspace-write` 仍是实际传给官方沙箱的机器值。

## 验收记录

- Windows Release 构建通过，产物版本为 `1.9.0-dev.26+36`。
- 实际点击“模型”二级菜单后同时显示 `DeepSeek-V4-Flash` 与 `DeepSeek-V4-Pro`，当前项有勾选标记；菜单没有再因 WebView2 空焦点自动关闭。
- 实际点击“推理等级”二级菜单后显示 `Off`、`Low`、`High`、`Max`，当前 `High` 有勾选标记。
- 会话输入区权限显示为“工作区读写”，Settings → 通用设置中的默认权限也显示为“工作区读写”；机器值仍为 `workspace-write`。
- API Key 粘贴链路已编入 Release：Windows `Ctrl+V` / macOS `Cmd+V` 仅向当前可编辑 Web 字段派发 React 可识别的 `input` 事件；剪贴板正文不写日志、不进入 App 设置或构建产物。
- 运行时补丁对源码目录和 Release 目录各重复执行一次均成功；Flash/Pro 与推理等级数据继续来自官方 DeepSeek provider adapter。
