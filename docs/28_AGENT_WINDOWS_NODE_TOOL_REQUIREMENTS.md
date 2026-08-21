# 智能体使用 Windows 测试节点所需的 VibeKits 工具

状态：dev.61 差距需求
日期：2026-08-21
目标：让 Codex/Harness 不需要用户逐台解释或手工配置，即可在审批后安全配置 Windows 节点、接入多台 Mac、执行验证，并使用现有 GitHub 访问和备份能力。

## 1. 结论

GitHub 诊断、代理、受控备份，以及 Windows 节点的 inspect/plan/list/export 工具已经满足智能体调用要求，不需要重复添加。

目前真正缺少的是 Windows 节点写入和跨设备执行工具。dev.61 虽然已经有协议、客户端、设备领域服务和报告模型，但以下工具仍不在 executable catalog：

- `vibekits.windows_node.apply`
- `vibekits.windows_node.enroll_device`
- `vibekits.windows_node.revoke_device`
- `vibekits.windows_node.rollback`
- `vibekits.windows_node.verify`

此外，为了让新 Mac 自助接入，还需要一个只在客户端本机生成和保管独立密钥的工具。没有这些工具，智能体只能检查和给出计划，不能完成配置。

## 2. 已完成工具，不需要再次开发

### Windows 节点

- `vibekits.windows_node.inspect`
- `vibekits.windows_node.plan`
- `vibekits.windows_node.list_devices`
- `vibekits.windows_node.export_onboarding`

### 现有 SSH/SFTP

- 保存并列出远程会话；
- SSH 命令执行；
- SFTP 列表、上传和下载；
- 打开一次认证后复用同一 SSH/SFTP 会话的交互工作流；
- 固定主机指纹和系统凭据引用。

### GitHub 网络

- `vibekits.github.diagnose`
- `vibekits.github.proxy_candidates`
- `vibekits.github.proxy_plan`
- `vibekits.github.proxy_apply`
- `vibekits.github.proxy_rollback`

随包 MinGit 已通过真实 Clash/Mihomo 端口访问私有仓库 `caucy2026/priv` 的 `ls-remote`。不需要新增 GitHub 登录插件或新的通用代理工具。

### GitHub 备份

- `vibekits.git.backup_preview`
- `vibekits.git.backup_commit`
- `vibekits.git.backup_push`
- `vibekits.git.verify_remote_ref`

这些工具的代码和自动测试已经具备；真实私有仓库 push 仍需要用户两次独立审批和一次实证，但不是工具缺失。

## 3. P0：必须新增或接通的工具

### 3.1 `vibekits.windows_node.helper_status`

风险：`readOnly`，无需审批。

用途：让智能体在生成计划前确认当前 Release 是否真的具备可执行 helper，避免调用关闭入口后才失败。

输入：无。

输出至少包含：

```text
available, absolutePath, signatureValid, publisher,
sha256, fileVersion, protocolVersion, manifestMatch,
executableActions[], unavailableReason
```

要求：

- 不返回证书私钥、签名服务信息或任意秘密；
- helper 缺失、签名无效、发布者/哈希/协议不匹配时 `available=false`；
- 状态必须来自 Release 实体和 manifest，不能来自 mock 或配置开关。

### 3.2 `vibekits.windows_node.apply`

风险：`controlsDevice`，必须逐次审批并触发 UAC。

输入：

```text
planId, planDigest, approvedActionIds[]
```

禁止输入命令、PowerShell、脚本、可执行路径、账户密码或任意追加参数。

输出至少包含：

```text
receiptId, requestDigest, nonce, status,
actions[{id,status,beforeDigest,afterDigest,elapsedMs,safeMessage}],
rollbackId, requiresReinspection, rebootRequired
```

要求：

- 只能调用签名、哈希和协议均与 Release manifest 一致的固定 helper；
- helper 重新校验计划时效、摘要、nonce、防重放、依赖和现场状态；
- UAC 拒绝、取消、超时、部分成功和失败必须是不同状态；
- 完成或异常结束后自动重新 inspect；
- 不得回退为任意管理员 PowerShell。

### 3.3 `vibekits.windows_node.enroll_device`

风险：`writesData`，必须审批。

输入：

```text
planId, planDigest, deviceLabel, publicKey, expiresAt?
```

输出至少包含：

```text
deviceId, label, algorithm, publicKeyFingerprint,
status, authorizedKeysDigest, requiresLoginVerification
```

要求：

- 只接受合法 Ed25519 公钥，拒绝私钥、RSA、损坏 key 和重复指纹；
- 通过签名 helper 原子更新 `authorized_keys` 并校验 ACL；
- 设备登记表与 active-only `authorized_keys` 投影一致；
- 至少一次真实登录成功前不得切换 key-only；
- 日志不得保存完整公钥正文。

### 3.4 `vibekits.windows_node.revoke_device`

风险：`controlsDevice`，必须审批。

输入：

```text
deviceId, expectedRegistryDigest
```

输出至少包含：

```text
deviceId, previousStatus, currentStatus,
authorizedKeysDigest, otherActiveDeviceCount, receiptId
```

要求：

- 只允许撤销已登记 device ID；
- 状态漂移时拒绝执行并要求重新 list；
- 原子移除目标设备公钥；
- 不得影响其他 active 设备；
- 撤销后保留脱敏审计，不删除设备历史。

### 3.5 `vibekits.windows_node.rollback`

风险：`controlsDevice`，必须独立审批并触发 UAC。

输入：

```text
rollbackId, expectedCurrentStateDigest
```

输出与 apply 使用同一回执结构。

要求：

- 仅恢复该计划实际修改且仍保持预期状态的项目；
- 用户后来修改的状态不得被旧 rollback 覆盖；
- 支持恢复防火墙规则、网络类别、sshd 配置/启动类型、公钥/ACL 和电源设置；
- 自动 rollback 不得删除账户、删除用户数据或卸载系统组件；
- 回滚后自动重新 inspect。

### 3.6 `vibekits.windows_node.verify`

风险：`remoteControl`；只读检查不需系统写入审批，1 GiB 压测和故障注入需单独确认。

运行位置：必须能在 Mac 版 VibeKits/Harness 上执行。Windows 本机 localhost 结果必须拒绝。

输入：

```text
nodeProfileId, deviceIdentityId,
checks[], enableLargeTransfer, enableDisconnectTest
```

必需检查：

- 固定 host key；
- 独立公钥登录；
- `pwsh -NoProfile`；
- cwd 为 `D:\KEMI-Test\work`；
- TEMP/TMP 为 `D:\KEMI-Test\tmp`；
- SFTP 上传、远端 SHA-256、下载、本地 SHA-256；
- 1 GiB 中途取消且无远端临时残留；
- 约 50% 断网、明确失败和恢复后重试；
- 防火墙只允许确认的 Private `/24` 或更窄范围；
- 恢复连接后仍为同一 host key。

输出必须是完整 `NodeVerificationReport` 和 `WorkflowArtifact`，包含来源设备标签、状态、耗时和证据引用，不包含密码、私钥或文件正文。

## 4. P0：新 Mac 自助接入工具

### `vibekits.windows_node.ensure_client_identity`

风险：`writesLocalCredentials`，第一次创建时需要用户确认。

运行位置：Mac 或其他准备接入节点的客户端。

输入：

```text
deviceLabel, algorithm="ed25519", rotate=false
```

输出只允许包含：

```text
deviceIdentityId, deviceLabel, algorithm,
publicKey, publicKeyFingerprint, credentialReference, createdAt
```

要求：

- 私钥只在客户端本机生成并保存在 Keychain/受保护文件中；
- 私钥永不进入 Harness 参数、工具结果、日志、onboarding 或项目文件；
- 默认复用已有身份，除非用户明确批准 rotate；
- 每台设备生成独立身份，禁止复制同一私钥；
- `credentialReference` 是不透明引用，SSH/SFTP 使用引用加载私钥；
- 能把返回的公钥直接交给 `windows_node.enroll_device`，无需用户复制粘贴。

这是实现“新设备以后不用每次告诉智能体”的关键工具。

## 5. 工具编排要求

VibeKits 应提供一条可由智能体自动发现的标准流程：

```text
helper_status
  → inspect
  → plan
  → 用户审批/UAC apply
  → Mac ensure_client_identity
  → 用户审批 enroll_device
  → export_onboarding
  → verify
  → list_devices / revoke_device / rollback
```

约束：

- ToolSpec 是唯一注册源，UI、搜索、Harness 和 MCP `tools/list` 不得维护不同清单；
- handler、签名 helper 或平台实现缺失时不得进入 executable catalog；
- read-only 工具可直接运行，系统写入和设备控制逐次审批；
- 所有结果结构化并进入模块审计；
- 每个失败必须给出可执行的下一步，不能只返回“工具不可用”；
- 所有计划和写入操作使用随机短期 ID、摘要和状态漂移检查；
- 审计只保存摘要、指纹、状态、耗时和证据引用。

## 6. 工具级验收门禁

### 自动门禁

- MCP `tools/list` 只暴露真正可执行工具；
- helper 缺失、签名/发布者/哈希/协议错误时五个写入工具自动关闭；
- plan 篡改、过期、nonce 重放、未知 action 和命令注入全部拒绝；
- Ed25519 生成、重复拒绝、原子登记、单设备撤销和其他设备不受影响；
- rollback 拒绝覆盖用户后来修改的状态；
- verify 拒绝 localhost、缺项、秘密证据和失败项伪装通过；
- 日志和返回值中不存在密码、Token、私钥或完整公钥正文。

### 真实门禁

- Windows Release 包含签名 helper，manifest 和校验脚本验证通过；
- 管理员 UAC 下 apply 与 rollback 各成功一次；
- 两台 Mac 分别调用 `ensure_client_identity`，使用不同指纹完成 enroll 和 verify；
- 撤销一台后只有该设备失败；
- 1 GiB 取消、50% 断网、双向 SHA-256 通过；
- 工具产生的脱敏报告进入 `docs/acceptance/`。

## 7. 不需要 VibeKits 新增的工具

- 不需要新的 GitHub 登录插件；现有 GCM/系统凭据可用；
- 不需要新的通用 Git push 工具；现有受控 backup 工具已覆盖；
- 不需要共享 SSH 私钥工具；每台设备必须独立生成；
- 不需要任意管理员 shell 工具；该能力明确禁止；
- 不需要默认全局代理或系统 TUN 工具；GitHub host-scoped proxy 已满足当前需求；
- 不需要删除账户、清空工作区或卸载系统组件的自动回滚工具。

## 8. 完成判定

当且仅当下列工具在目标平台进入 executable catalog，并通过自动和真实门禁，才能回复“VibeKits 已满足智能体工具要求”：

```text
vibekits.windows_node.helper_status
vibekits.windows_node.apply
vibekits.windows_node.enroll_device
vibekits.windows_node.revoke_device
vibekits.windows_node.rollback
vibekits.windows_node.verify
vibekits.windows_node.ensure_client_identity
```
