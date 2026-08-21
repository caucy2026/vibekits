# v1.9.0-dev.58 Windows 节点与 GitHub 备份验收

日期：2026-08-21
输入规格：`VIBEKITS_WINDOWS_TEST_NODE_AND_GITHUB_BACKUP_TOOL_REQUIREMENTS.md`

## 自动闭环结果

| 能力 | 证据 | 结果 |
|---|---|---|
| ToolSpec / Harness 合同 | 已实现 ID 进入 executable catalog；依赖签名 helper/跨设备实证的 ID 只进入 full catalog | PASS |
| Windows 节点领域 | D 盘不足、根路径越界、OpenSSH capability/真实状态矛盾、稳定 action、摘要篡改拒绝 | PASS |
| Windows 本机探测 | 当前 Windows 真实执行只读 PowerShell 探测并解析 15 类结构化检查，无写操作 | PASS |
| Windows 节点 UI | 体检 → 检查明细 → 变更计划；执行入口明确禁用且说明签名 helper 门禁 | PASS |
| GitHub 代理 | 非 7890 loopback 发现、HTTPS/Git 候选状态、host-scoped 计划、应用失败恢复旧值 | PASS |
| Git 备份安全 | `.env`/秘密阻断、状态摘要失效、文件集合约束、commit/push 分离、禁止隐式 push | PASS |
| Git 远端核验 | 本地 bare remote 真 commit、真 push、`ls-remote` SHA 一致 | PASS |
| 既有 SSH/SFTP | 会话、主机指纹、一次认证联动 SFTP、取消、端口转发回归 | PASS |
| Windows Release | `vibekits.exe` 文件/产品版本 `1.9.0-dev.58+68`；22 项随包运行时、Git 2.55.0、Harness Node 语法核验 | PASS |
| Release 启动 | 最终 EXE 启动后进程 `Responding=True`，路径来自 Release 目录 | PASS |

本轮定向 Flutter 测试共 49 项（含真实 Windows 只读 smoke），全部通过。定向静态检查 0 问题。

## 安全边界核对

- 不接受 remote URL，只接受仓库已有 remote 名称。
- 不提供 force、force-with-lease、删远端 ref、改 tag 或绕过 hooks。
- 密码、Token、私钥、CA 私钥不进入参数、结果、日志或项目文件。
- GitHub 修复仅写 `http.https://github.com.proxy`；验证失败自动恢复。
- Windows 系统写操作不回退到任意管理员 PowerShell。签名、版本化、白名单 helper 未交付前，apply/rollback 保持不可执行。

## 尚未满足的真实发布门禁

以下项目不能由本机模拟测试替代，因此本版本不得宣称需求全文“完整完成”：

1. Windows Release 内签名 UAC helper、nonce/回执和精确系统回滚；
2. 两台不同 Mac 使用独立密钥连接同一 Windows 节点，并验证单设备撤销；
3. 1 GiB SFTP 中途取消、50% 断网重试、双向 SHA-256 和无临时残留；
4. 用户私有 GitHub 仓库在明确 commit/push 两次审批后完成远端 SHA 核验；
5. 对应截图、日志、哈希与 `WorkflowArtifact` 进入正式发布证据。

验收智能体必须把以上项目标记为 `BLOCKED / 待实证`，不得用本地 bare remote、localhost 或 Mock 冒充。
