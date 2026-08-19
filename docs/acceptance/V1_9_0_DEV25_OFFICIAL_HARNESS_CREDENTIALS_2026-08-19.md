# v1.9.0-dev.25 官方 Harness 凭据设置验收

日期：2026-08-19

## 官方基线

- 内置版本：`@deepseek-ai/dsh@0.1.0-rc.7`。
- 官方凭据优先级：继承的进程环境（只读）高于 `$DSH_HOME/.credentials.yaml`（可写）。
- 官方交互：Settings → Models → DeepSeek → Edit 中填写 API Key，保存后由凭据服务热更新。

## 本版纠偏

- Web 启动不再传入 `DEEPSEEK_API_KEY`，API Key 输入框必须可编辑。
- Web 启动不再传入 `DEEPSEEK_BASE_URL`、`DEEPSEEK_MODEL`，模型配置由官方设置页管理。
- Vibekits 不再自行创建默认模型设置；官方基础配置已经提供 `deepseek-v4-flash` 与 `deepseek-v4-pro`。
- 旧系统凭据一次迁移到官方可写凭据文件，且不覆盖用户已在官方页面保存的新 Key。
- App 显示版本、pubspec 与 Windows Release 版本必须统一为 `1.9.0-dev.25+35`。

## 验收记录

| 验证 | 结果 |
|---|---|
| `flutter analyze --no-pub` | 通过，0 问题 |
| 凭据迁移定向测试 | 1/1 通过；首次迁移成功，官方已有值不覆盖 |
| `flutter build windows --release --no-pub` | 通过，76.3 秒 |
| EXE FileVersion / ProductVersion | 均为 `1.9.0-dev.25+35` |
| EXE SHA-256 | `922F4B0BB059966911B09F20D4E356583EF5B1E2908E917369C06600C772A1D3` |
| Dart `data/app.so` SHA-256 | `9B9F770FB45F690CAECA7A7BF1CE574559A7A582519893EDD7E65ADB13C57F78` |
| 旧系统凭据 | 已删除，未读取或输出 Key 值 |
| 官方凭据文件 | 已存在且包含 `DEEPSEEK_API_KEY` 条目，值未输出 |
| API Key 输入框 | 可聚焦、可编辑，提示“已配置——输入新值可替换” |
| 重启持久化 | 关闭并重启 App 后仍显示已配置，输入框仍可编辑 |
| 工作区/会话恢复 | 重启后 `vibekits` 工作区及原会话列表仍在 |
| 当前模型 | Composer 正常显示 `DeepSeek-V4-Flash High`，不再为空 |

## 截图证据

- `screenshots/v1_9_0_dev25_harness_api_key_after_restart.png`：重启后 Key 输入框获得焦点，版本号为 `v1.9.0-dev.25+35`。
- `screenshots/v1_9_0_dev25_harness_restarted.png`：重启后工作区和会话恢复。
- `screenshots/v1_9_0_dev25_harness_model_picker.png`：官方模型/推理等级选择入口。
