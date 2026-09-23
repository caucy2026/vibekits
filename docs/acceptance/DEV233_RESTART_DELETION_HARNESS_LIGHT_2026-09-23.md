# dev.233 Mac 重启、派生删除与 Harness 状态灯复验

日期：2026-09-23。范围：VibeKits Mac，本机现有正式数据与独立构建候选。

## 已核实

- 正式 VibeKits 重启前后，已删除的派生会话 `session-d344fefe-4f34-4e86-8e68-7a86f838b6d9` 在 Harness 数据目录的路径和 `continuations.json` 内容中均不存在；来源会话 `session-113210fb-6d38-4393-8771-3a670d97996e` 保留。关系文件 SHA-256 重启前后及再次复核均为 `73b7a20df7eea8034a7455ae5d7d5123fb2e56baab050b0172cf5289751c6f1a`。重启后的侧栏未显示被删除的 PAD63 派生行。
- 现有侧栏另有派生行 `远程仿真只读取 Mac 信息 4`，其“来源会话已删除”提示对应另一条来源数据，不是上述已删除会话恢复。
- Harness 顶部标签原有红色 `Badge` 只代表代理运行。现在连接状态由已认证的远程协同、远程控制会话、远程仿真控制端或目标端任一路径驱动；连接时显示绿色，断开后恢复原运行提示。未改变远程状态栏中独立的错误提示。
- 新增状态灯回归及派生摘要超时后复用同一子会话 ID 的协调器测试。冻结源码上的 16 项定向 Flutter 测试通过；涉及文件的 `flutter analyze` 通过。
- 冻结源码独立构建成功：`1.9.0.233+2233`，`com.caucy.vibekits`，Universal `x86_64 arm64`，macOS 12+。候选位于 `/Volumes/ORICO/kemi-build-cache/app-release-gate/vibekits/macos/dev233-harness-light-20260923/source/build/macos/Build/Products/Release/Vibekits.app`。Developer ID Application `zhen ji (26T5WV4GLP)` 签名后在可访问证书的宿主环境验证通过。App AOT SHA-256 为 `4b9b3597d587881b652999e50656ef3ac720ab26a2091408c3a9bad672c06ae0`。
- 使用不同 bundle ID 的独立 QA 副本 `com.caucy.vibekits.harnesslightqa` 已实机启动并显示 `v1.9.0-dev.233+2233`；无连接时顶部状态灯保持非绿色。此副本为临时 ad hoc 签名，不能用于正式发布。正式 Developer ID 候选未被 QA 操作改动。
- 原正式实例的远程仿真 `6192992780` 已重新连接，返回 `connected: true`、`transport: p2p_or_relay`。该活跃测试目前继续运行。

## 发布判定：BLOCK

- 尚未在正式签名候选上完成真实远程连接时顶部灯变绿、断开后的回退、完整的派生摘要故障重试、升级安装及长时间稳定性验证。既有 `dev.227` 派生摘要和菜单实测见 `DEV227_CONTINUATION_SUMMARY_DELETE_2026-09-23.md`，不可替代本候选的完整发布门禁。
- 正式候选尚未取得 Apple `Accepted` 公证、staple、Gatekeeper 放行，也未制作最终发布 ZIP。因此没有向 KEMI 商城上传或更新记录。
- 对当前活跃仿真 `6192992780` 的断开操作被自动审批拒绝，理由是会打断正在进行的远程测试，并与先前“不影响它继续测试”的约定冲突；不得改用其他方式间接断开。取得新的明确授权后，才能安排切换正式候选进行涉及该连接的实测，再继续公证与上架门禁。

## 用户授权后的实机切换与发布尝试

用户随后明确允许暂时停止原仿真，关闭旧版，以新版本替代并在验证成功后正式发布。本节记录授权后的新状态；上节的阻塞说明只描述授权前的阶段。

- 通过内置仿真桥确认 `6192992780` 原连接为 `connected: true`、`transport: p2p_or_relay`，按授权断开。关闭 dev.227 后以相同正式 bundle ID 启动 dev.233，桥接进程的可执行文件路径指向本节候选包。
- 在 dev.233 内重新连接 `6192992780`，工具结果 `connected: true`、设备身份已核验、`transport: p2p_or_relay`。实机截图可见 Harness 标签小灯变绿、远程状态栏显示绿色 `远程仿真中 · 6192992780`。并列的红色 `远程仿真异常` 来自**本机作为被仿真目标**的独立服务；它不表示连出的 `6192992780` 失败。随后为签名公证按授权断开该连接。
- 同一 dev.233 界面仍显示现存派生会话的交接摘要入口，打开可见具体来源与整理内容。右键菜单准确显示重命名、分叉、归档、派生、删除五项，Escape 关闭。此前删除的 `session-d344fefe-4f34-4e86-8e68-7a86f838b6d9` 在新版本启动后仍无路径或关系记录；关系文件 SHA-256 保持 `73b7a20df7eea8034a7455ae5d7d5123fb2e56baab050b0172cf5289751c6f1a`。打包 Node 的摘要注入、五项菜单和进度重试三项测试均通过。
- 旧版 dev.227、两个独立 dev.227 QA 应用及中间自动注册的 dev.233 作业已按精确 launchd 标签停止；保留它们的数据和包文件。随后从冻结源码重建并启动 dev.233，本机只剩一个 `com.caucy.vibekits` 应用作业，Harness 重试后正常显示工作区。
- 旧版与重签前新版具有相同 `com.caucy.vibekits`、Team `26T5WV4GLP` 和完整 designated requirement。标准签名脚本第一次在嵌套库上报 `A timestamp was expected but was not found`。为处理偶发时间戳失败，`tool/sign_macos_developer_id.sh` 增加每个签名目标最多四次的有限重试；仍在 App.framework 报 `The timestamp service is not available`。独立的临时可执行文件时间戳探针也失败，`http://timestamp.apple.com/ts01` 连接超时。`notarytool history` 可正常查询，说明公证凭证可用，但尚未提交本候选。
- 失败后的部分重签包经 `codesign --verify --deep --strict` 判定 sealed resource 无效，已从冻结源码重建为**仅供本机测试**的包；该包不是 Developer ID 正式签名产物，不能作为商城包。当前必须等待 Apple 时间戳服务恢复，再完成完整重签、Harness 签名启动检查、Apple `Accepted` 公证、staple、Gatekeeper、最终 ZIP 和商城/CDN/安装升级验收。**正式发布状态仍为 BLOCK，商城未更新。**

## 五项右键菜单逐项验收（最新本机编译）

- **重命名：PASS。** 本轮测试派生会话 `session-b0315ad3-2944-400e-994a-88bd368545f7` 重命名为 `QA 右键验收 2026-09-23`。首次发现 Harness 正式会话标题已持久化，但派生关系快照仍为旧标题，侧栏显示滞后。现已在发布关系前用官方 `session.list` 校正并持久化标题；重编、重启后侧栏正确显示新名称。新增关系存储回归测试通过。
- **分叉：PASS（有历史消息的原会话）。** 对 `PAD63_OK response request` 执行后，工作区生成新的分叉会话行。对空白派生子会话执行时未生成新会话，作为官方 Harness 无消息分叉的边界情况记录；若需空白会话也能分叉，应另行定义行为。
- **归档：PASS。** 对上述新分叉会话 `session-79b47011-c080-47b1-835b-00aec7584baf` 执行后，该行从工作区侧栏消失，界面回到未选择工作区的空白态；Harness `workspace.json` 的 `archivedSessionIds` 持久记录了该 ID。原始 PAD63 会话及派生会话保留。
- **派生：PASS。** 首次实测发现摘要抽取把模型的英文 `reasoning` 当作最终摘要。已改为只读取 `assistant/message.content` 的最终 `text` 部分；新生成的 `session-84b013cc-f89e-495e-8239-3a89f4299dd8` 的关系存储及界面均显示中文最终交接摘要，来源关联正确，详情弹窗可打开。旧的 QA 测试子会话保留历史错误摘要，待确认删除；不会自动改写历史记录。
- **删除：PASS。** 用户针对 QA 测试子会话确认后，删除菜单的确认框准确显示 `QA 右键验收 2026-09-23`；此前还验证了取消按钮不会删除。实际删除后侧栏行、主会话目录、工作区索引及派生关系均消失。进一步发现 `session_projcache/sessions` 内仍留有该 ID 的标题缓存；现已修复删除流程和 `containsSession` 的完整性检查，精确清除这条测试缓存。重编并重启后，测试会话未恢复，来源会话及新生成的中文摘要派生会话保持可见。新增残留缓存回归测试通过。
- 目标 Flutter 回归 20 项通过，Node 菜单契约测试通过，改动文件 `flutter analyze` 无问题。最新可运行本机包仍是 ad hoc 构建，**不是正式签名发布包**。
- 2026-09-23 再次用隔离可执行文件执行 Developer ID `codesign --timestamp` 仍报 `The timestamp service is not available`，故 Apple 公证、上架均未开始。正式发布判定保持 **BLOCK**。
