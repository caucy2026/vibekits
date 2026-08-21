# dev.61 Windows 测试节点与 GitHub 备份剩余工作

状态：未完成，不能宣称可一键配置多设备节点
盘点日期：2026-08-21
当前基线：`v1.9.0-dev.61+71`
对应规格：`25_WINDOWS_TEST_NODE_AND_GITHUB_BACKUP.md`
安全设计：`27_SECURE_WINDOWS_NODE_INTEGRATION_GUIDE.md`

## 1. 当前可用边界

dev.61 已完成安全协议和领域底座，但没有交付可执行的 Windows 节点 helper。因此当前状态必须按以下边界理解：

| 场景 | 当前状态 | 说明 |
|---|---:|---|
| Windows 节点只读体检 | 可用 | 普通权限检查真实系统状态 |
| 生成幂等变更计划 | 可用 | 只生成计划，不修改系统 |
| 列出设备登记 | 可用 | 读取设备登记数据，不修改 `authorized_keys` |
| 导出 Mac onboarding | 可用 | 只包含连接事实和 host key，不包含秘密 |
| 已手工配置节点的 SSH/SFTP | 可用 | 复用现有远程工作台 |
| apply / rollback | 不可用 | Release 没有签名 helper 实体 |
| enroll / revoke device | 不可用 | 不能安全写入系统 `authorized_keys` 和 ACL |
| 跨设备 verify | 不可用 | 没有真实 Mac 执行器和证据闭环 |
| 多台 Mac 一次配置后长期使用 | 不可用 | 缺少登记、撤销、验证和实机证据 |
| 私有 GitHub 只读访问 | 可用 | 随包 MinGit `ls-remote` 已验证 |
| 私有 GitHub 真实受控 push | 待验收 | 尚未执行两次独立审批和远端 SHA 核验 |

结论：如果 Windows 已经由人工配置好 SSH、账户、防火墙和公钥，Mac 可以连接；如果依赖 VibeKits 从零配置并管理多台 Mac，目前不能工作。

## 2. dev.61 已完成，不应重复开发

- helper 请求/回执协议：action 白名单、规范摘要、15 分钟时效、nonce 防重放、命令参数拒绝；
- App 侧 helper 客户端：签名、发布者、SHA-256、协议版本、UAC 拒绝、取消、超时和回执绑定检查；
- 设备领域服务：独立 Ed25519、重复拒绝、禁用/恢复/撤销、active-only keys、原子清单和 onboarding；
- 跨设备报告模型：11 项必需检查、`WorkflowArtifact`、localhost/缺项/秘密/伪通过拒绝；
- Harness 可执行入口：`windows_node.list_devices`、`windows_node.export_onboarding`；
- GitHub 代理摘要/状态漂移/安全回滚；
- Git 备份隔离、内容竞态阻断、commit/push 分离设计；
- dev.61 Release `vibekits.exe` 已生成；专项回归 31 项通过。

以上是可复用底座，不等于 Windows 管理员动作已经实现。

## 3. 仍需开发的代码和产物

### 3.1 真实 Windows 节点 helper

必须交付独立 helper 工程和 Release 二进制。只有协议类或 mock launcher 不算完成。

helper 必须：

- 只接受版本化 JSON 请求，不接受任意 shell、脚本、命令行或可执行路径；
- 重新验证协议版本、plan ID、plan/inspection/request 摘要、nonce、时效、action 白名单、依赖和现场状态；
- 实现下列原子 action：
  - `windows.openssh.install_or_repair`
  - `windows.sshd.configure`
  - `windows.sshd.start_and_enable`
  - `windows.firewall.apply_lan_rule`
  - `windows.network.mark_private`
  - `windows.local_user.create_standard`
  - `windows.local_user.set_authorized_keys`
  - `windows.acl.apply_test_root`
  - `windows.runtime.install_powershell`
  - `windows.power.disable_ac_sleep`
  - `windows.change.rollback`
- 每个 action 记录脱敏的 before/after 摘要、状态、耗时和错误分类；
- 以绑定 request digest 和 nonce 的 JSON 回执结束；
- 支持精确回滚，但不得自动删除账户、用户数据或卸载系统组件；
- 操作 `authorized_keys` 时使用原子替换并验证仅目标用户、SYSTEM 和 Administrators 具有允许的写权限；
- 防火墙仅允许用户确认的 RFC1918/ULA，IPv4 `/24` 或更窄，Profile 仅 Private。

### 3.2 App 到 helper 的真实 Windows 适配器

当前 `WindowsNodeHelperClient` 依赖注入的是身份检查器和 launcher，仍需生产实现：

- 使用 Windows Authenticode API 验证签名链和预期发布者；
- 计算 helper 文件 SHA-256，并与 Release manifest 固定值比较；
- 使用 Windows `runas`/UAC 启动固定 helper，禁止调用方替换路径；
- 建立有界请求/回执通道，限制大小、编码、超时和输出内容；
- 区分 UAC 拒绝、用户取消、超时、进程失败、无效回执和部分成功；
- 取消或超时后重新执行只读体检，不假定系统没有变化；
- helper 运行期间不得阻塞 Flutter UI 线程。

### 3.3 接通被关闭的 ToolSpec/Harness 工具

以下工具当前只有定义，没有生产 handler，必须在 helper 和真实验证器闭环后才能进入 executable catalog：

- `vibekits.windows_node.apply`
- `vibekits.windows_node.enroll_device`
- `vibekits.windows_node.revoke_device`
- `vibekits.windows_node.rollback`
- `vibekits.windows_node.verify`

接通要求：

- apply/rollback 只接受短期 plan ID 和摘要；
- enroll 只接受合法 Ed25519 公钥、设备标签和可选到期时间，不接受私钥；
- revoke 只接受已登记 device ID；
- 写入工具必须经过一次性审批并进入模块审计；
- verify 只接受另一台真实设备产生的完整报告，localhost 永远拒绝；
- handler 未接通、helper 缺失或签名资源无效时继续保持不可执行。

### 3.4 Release 供应链门禁

Release 目前没有 helper 资产和身份清单，必须补齐：

- 将固定路径的 helper 加入 Windows Release 构建；
- manifest 记录 helper 相对路径、协议版本、文件版本、SHA-256 和预期发布者；
- `verify_windows_bundle.ps1` 检查 helper 存在、版本、哈希和 Authenticode；
- 缺失、未签名、证书不可信或任何值不一致时构建/发布失败；
- `tool/release_acceptance_manifest.json` 登记 Windows 节点完整工作流、自动测试和真实证据；
- 生成第三方组件/许可证记录；若 helper 为自研，应记录源码版本和构建来源。

## 4. 需要用户或组织提供的外部资源

这些不是 mock 能解决的项目：

1. Windows 可信代码签名证书或组织 CI/HSM 签名服务；
2. 证书的预期发布者名称和可验证证书链；
3. 一台允许 UAC 管理员操作的目标 Windows 真机；
4. 至少两台不同 Mac，每台本机生成独立 Ed25519 密钥；
5. 可控制断网的局域网环境；
6. 一个允许创建可回收 backup 分支的私有 GitHub 测试仓库。

签名私钥、Mac 私钥、GitHub Token、Windows 密码和 SSH CA 私钥不得进入仓库、VibeKits、Harness 参数或验收文档。

## 5. 必须完成的真实验收

### 5.1 Windows apply 与 rollback

1. 普通权限 App 完成 inspect 和 plan；
2. 用户确认计划并接受 UAC；
3. helper 完成 OpenSSH、sshd、防火墙、Private 网络、`kemi-test`、公钥、`D:\KEMI-Test` ACL、PowerShell 和电源动作；
4. 再次只读体检确认目标状态；
5. 执行精确 rollback；
6. 核对计划外系统状态没有变化；
7. 保存 UAC、helper 回执、前后报告和 rollback 证据。

### 5.2 两台 Mac 独立接入和单设备撤销

- 两台 Mac 使用不同 Ed25519 公钥和不同设备标签；
- 分别固定同一个 Windows host key 并完成公钥登录；
- 均验证 `pwsh -NoProfile`、`D:\KEMI-Test\work` 和远端 TEMP/TMP；
- 撤销 Mac A 后，Mac A 必须失败，Mac B 必须继续成功；
- 禁止复制同一私钥到两台 Mac。

### 5.3 SSH/SFTP 故障与完整性

- 双向上传/下载并核对本地与远端 SHA-256；
- 1 GiB 上传中途取消，服务端无本轮临时残留；
- 约 50% 时断网，明确失败，恢复后可重试；
- 恢复连接时重新核对相同 host key；
- 两台设备并发时会话、进度、取消和证据不得串扰。

### 5.4 GitHub 真实写入

- 通过产品内流程完成 proxy plan/apply/失效检测/rollback；
- 对私有仓库执行 `backup_preview`，秘密扫描无 blocker；
- 第一次独立审批创建 commit；
- 第二次独立审批 push 到专用 backup 分支；
- `ls-remote` SHA 与计划 commit SHA 一致；
- 当前分支、HEAD、index 和工作区保持不变；
- 是否删除远端测试分支必须另行取得用户审批。

## 6. 验收证据要求

最终 `docs/acceptance/` 记录至少包含：

- helper 文件版本、SHA-256、签名状态、发布者和协议版本；
- Release 校验输出；
- Windows 配置前、配置后和回滚后的节点报告；
- 两台 Mac 的设备标签、公钥指纹、host key 指纹和连接结果；
- 单设备撤销结果；
- 1 GiB 取消、断网重试、双向 SHA-256 和无残留证据；
- GitHub proxy 应用/失效/恢复记录；
- Git commit SHA、远端 ref SHA 和两次审批记录；
- UI 截图或录屏以及脱敏模块审计记录。

证据不得包含密码、Token、私钥、公钥完整正文、代理订阅、测试文件正文或完整敏感命令输出。

## 7. 建议实施顺序

1. 实现 helper 二进制和原子 action；
2. 实现 Authenticode、哈希、UAC launcher 和回执通道；
3. 接通 apply/rollback，并在 Windows 真机完成配置与回滚；
4. 接通 enroll/revoke 和 `authorized_keys` 投影；
5. 接通跨设备 verify；
6. 将已签名 helper 和 manifest 纳入 Release 强制资产；
7. 用两台 Mac 完成连接、撤销、1 GiB、断网和 SHA-256；
8. 完成私有 GitHub 两次审批 push 和远端 SHA；
9. 归档证据，更新需求总账和发布清单。

## 8. 完成定义

只有同时满足以下条件才能回复“已经满足”：

- 签名 helper 实体随 Windows Release 交付并通过强制校验；
- apply/enroll/revoke/rollback/verify 均进入 executable catalog；
- Windows 管理员 apply 和精确 rollback 实测通过；
- 两台 Mac 独立密钥接入、单设备撤销和 SFTP 故障测试通过；
- 私有 GitHub commit/push 两次审批及远端 SHA 通过；
- 所有脱敏证据进入正式验收文档。
