# dev.227 派生会话摘要与删除入口复验

日期：2026-09-23。对象：Mac 隔离实例，应用标识 `com.caucy.vibekits.continuationtest`，独立数据根目录位于外盘构建缓存；原 VibeKits 远程仿真实例未被关闭或覆盖。

## 发现与修复

- 原派生关系已保存摘要，但空白会话界面不显示。现增加“交接摘要”入口，可查看完整摘要。
- 派生会话在首次消息前可能只显示官方空白行，官方操作按钮尚未渲染；临时复制行也没有 React 菜单事件。现为这两种状态提供按真实派生会话 ID 绑定的独立删除入口。官方按钮出现后撤下自有按钮，避免重复。
- Harness 工作区 ID 被当作相对路径规范化，依赖启动目录；模型扩展校验真实工作区 ID 时拒绝注入摘要。现将 UUID 型工作区 ID 规范为 `/<id>/`，并兼容已有的错误路径记录。Harness 核心运行时未修改。

## 隔离实例实测

- 点击派生会话“交接摘要”，完整摘要可见；侧栏操作菜单出现“删除会话”，确认框明确标出 `PAD63_OK response request 2`。取消确认后，派生及来源记录均保留。未执行真实用户数据删除。
- 修复前，对同一派生会话两次提问，模型均回答未收到交接摘要。诊断确认扩展已加载，但工作区 ID 校验使注入内容长度为零。
- 修复后再问，模型无需工具即可回答来源任务为 20 页 KEMI 远程办公中文产品介绍 PPT，以 PPTX 主文件和同名 PDF 预览版交付；该事实与交接摘要一致。派生会话首次成功回复后生成 consumed 标记。
- 首轮标记生成后再问摘要中的另一事实，模型无需工具即可回答中文正文字体为“微软雅黑”。标记只记录首次成功回复，不再关闭后续轮次的摘要注入；摘要内容仍只整理一次。
- 隔离实例同时存在两条同名 `PAD63_OK response request 2` 时，原始空白派生行与新测试会话分别显示；原始行能打开自己的删除确认。侧栏匹配已收紧为真实 ID 优先，只有标题唯一且行无 ID 时才按标题兜底，防止同名误绑。确认框打开后取消，未删除用户记录。
- 同名记录来回切换后，“交接摘要”入口分别显示各自不同的摘要开头；消除了按标题前缀取第一条摘要的串会话问题。
- `harness_continuation_context_test.mjs`、`harness_continuation_synthetic_menu_test.cjs` 和 `harness_continuation_store_test.dart` 通过，覆盖旧错误路径和稳定工作区 ID。

最终 Mac 候选：`/Volumes/ORICO/kemi-build-cache/app-release-gate/vibekits/macos/dev227-continuation-summary-delete-20260923/source/build/macos/Build/Products/Release/Vibekits.app`，版本 `v1.9.0-dev.227+2227`，Developer ID `zhen ji (26T5WV4GLP)`，`codesign --verify --deep --strict` 通过。App AOT SHA-256：`e5fdb32ae9455ba9ef6e08b75df3067335fa7c45714a5c2027cfccebb4a0b19c`。打包后的交接扩展和侧栏脚本与当前源码逐字节一致。

供本机并行试用的独立副本：`/Volumes/ORICO/kemi-build-cache/app-release-gate/vibekits/macos/dev227-continuation-summary-delete-20260923/isolated-mac-test-final/Vibekits-Continuation-Test.app`，使用独立应用标识及数据目录；原仿真实例持续运行。四端正式验收仍按 `docs/69_HARNESS_CONTINUATION_REQUIREMENTS.md` 顺序执行。

## 右键菜单回归修复（同日追加）

派生会话此前使用的自有菜单只包含“删除会话”，遮盖了原有操作。现按官方顺序恢复“重命名、分叉会话、归档会话”，再附加“派生会话、删除会话”；前三项调用官方 Harness 对应回调，目标 ID 均取被点击的派生行。`harness_continuation_synthetic_menu_test.cjs` 对五项逐一验证，另外 `harness_continuation_progress_dom_test.cjs` 与 `harness_continuation_context_test.mjs` 通过。隔离版曾因数据根目录回退而显示空工作区；接回其独立测试数据后，实际右键 `PAD63_OK response request 2` 可见五项，点击“重命名”打开原生对话框，标题准确显示 `PAD63_OK response request 2`，随后取消，未改动会话。原有仿真实例仍运行。

## 右键菜单重复与关闭回归复验（同日追加）

用户截图显示补充菜单的“派生会话、删除会话”重复出现，并且弹层不易关闭。原因是官方菜单装饰器把同名动作再次附加到自有菜单；自有菜单此前也没有外部点击和 Escape 的关闭处理。现官方装饰器只处理官方菜单，自有菜单不再被二次装饰；两者均保持五项。自有菜单定位收束在侧栏内，外部点击与 Escape 都关闭菜单。隔离 Mac 实测：普通会话右键显示五项；截图对应的补充菜单右键显示五项，重复打开不增项，点空白处和按 Escape 均关闭。`harness_continuation_synthetic_menu_test.cjs` 覆盖自有菜单不被二次装饰、无 `role=menu` 的官方菜单仍能补齐两个动作以及两种关闭方式；相关进度与摘要测试也通过。最终候选版本仍为 `1.9.0.227+2227`，Developer ID 签名与 `codesign --verify --deep --strict` 通过，打包脚本与源码逐字节一致。

## 当晚独立实例复验

另以 `com.caucy.vibekits.continuationqa` 建立独立 Mac 应用和数据副本，未切换正在运行远程仿真的 `continuationtest` 实例，也未恢复已由用户确认删除的正式会话。从已有来源 `PAD63_OK response request` 派生 `PAD63_OK response request 3`，真实子会话 ID 为 `session-56022e5b-7897-43b7-9a5b-5bf02b5b935b`。点击后立即出现新会话和整理进度；完成后关系文件有 2210 字符交接摘要，首次提问前可在界面打开全文，子会话起初没有复制来源聊天时间线。来源卡片可跳回原会话，原消息和附件仍在。

实际模型首轮答出来源中的 20 页、PPTX/PDF、Arial Unicode MS；重启应用后第二轮答出 `make_kemi_ppt.py` 及尚未用 PowerPoint/Keynote 打开校验。重启前后交接摘要 SHA-256 均为 `1326d5b9cb11726eeb28c33d180896824665f697117c9a1c18061ff23782d451`，关系记录仍为一条，证明本轮未重新整理。新会话右键准确显示重命名、分叉、归档、派生、删除五项，无重复；Escape 和菜单外点击均关闭。删除确认框准确显示 `PAD63_OK response request 3`，取消后子会话及来源保留。此前经用户确认的正式子会话删除和重启不复活另有实际记录；本轮没有再执行不可恢复的删除。

打包 Node 运行 `harness_continuation_synthetic_menu_test.cjs`、`harness_continuation_progress_dom_test.cjs`、`harness_continuation_context_test.mjs` 均通过。Mac 候选包按现有 `tool/sign_macos_developer_id.sh` 重签，在可访问 Developer ID 身份的授权环境中 `codesign --verify --deep --strict` 通过；受限沙箱中直接运行 `codesign` 报无效，属于该验证环境不能直接用来判定交付包损坏。

结论：Mac 正常派生、摘要显示和注入、菜单、来源返回及重启持久性本轮实测通过，可供继续试用；完整稳定性门禁仍为 **BLOCK**。当前候选尚未在真实应用内完成“子会话已创建后模型整理超时 → 可见失败 → 点击重试复用同一 ID”的故障链路、长时间 soak，以及其余三端真机验收，不能称四端全部验收通过。
