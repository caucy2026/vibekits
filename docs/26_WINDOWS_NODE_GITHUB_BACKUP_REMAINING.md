# Windows 测试节点与 GitHub 备份剩余工作

状态：代码安全底座已补齐，真实外部证据未完全满足
盘点日期：2026-08-21
基线版本：`1.9.0-dev.61+71`
对应规格：`25_WINDOWS_TEST_NODE_AND_GITHUB_BACKUP.md`

## 1. 当前结论

现有实现已经完成只读体检、幂等计划、GitHub 回环代理发现与 GitHub host-scoped 配置、受控 Git 备份领域逻辑、Harness/UI 接入、自动测试和 Windows Release 构建。随包 MinGit 已能通过当前 Clash/Mihomo 和系统凭据只读访问私有仓库 `caucy2026/priv`。

但当前版本仍不能宣称需求全文完成。最关键的缺口是 Windows 系统变更入口仍因缺少签名 UAC helper 而禁用，多设备登记/撤销尚未形成可执行闭环，也没有两台 Mac 到同一 Windows 节点的真实证据。

## 2. 必须完成的产品能力

### 2.1 NODE-003：签名 UAC helper 与精确回滚

交付一个独立、版本化、可验证签名的 Windows helper：

- 主 App 保持普通权限，只在执行已审批计划时触发 UAC；
- helper 只接受版本化 JSON、短期 plan ID、摘要、随机 nonce 和预定义 action ID；
- 禁止接收任意 PowerShell、CMD 或 shell 文本；
- 白名单覆盖 OpenSSH、sshd、LAN 防火墙、Private 网络、标准账户、公钥、`D:\KEMI-Test` ACL、PowerShell、电源和 rollback；
- 每个动作保存修改前值、修改后值、结果和一次性回执；
- App 验证 helper 的发布者签名、文件哈希、协议版本、计划摘要和回执；
- UAC 拒绝、部分成功、超时、取消、重启要求和回滚失败必须分别报告；
- 删除账户、删除用户数据和卸载系统组件不得进入自动回滚。

验收标准：`windows_node.apply` 与 `windows_node.rollback` 进入 executable catalog；篡改、重放、过期、未知 action、错误签名和状态漂移全部被拒绝；真实 Windows 管理员配置和回滚各成功一次。

### 2.2 NODE-007/008：多设备身份生命周期

- 创建并维护非管理员账户 `kemi-test`，不得加入 Administrators；
- 每台 Mac/Windows 客户端使用独立 Ed25519 公钥，禁止共享私钥；
- 提供设备列表、添加、重复指纹拒绝、禁用、撤销和最近连接状态；
- `authorized_keys` 原子写入并校验 ACL；
- 至少一把密钥真实登录成功前，不得关闭密码认证；
- 导出不含秘密的 onboarding 包：主机、端口、用户名、host key 指纹、SSH config 示例和操作说明；
- 撤销一台设备后，其他设备必须保持可连接。

验收标准：`list_devices/enroll_device/revoke_device/export_onboarding` 全部可执行；两台不同 Mac 使用不同密钥连接同一 Windows 节点，撤销其中一台后仅该设备失效。

### 2.3 NODE-010：跨设备真实节点验证

必须从 Mac 而不是 Windows 本机 localhost 执行并保存证据：

1. 固定并核对 Windows host key；
2. 使用设备独立公钥登录；
3. 执行 `pwsh -NoProfile` 并取得版本；
4. 验证工作目录为 `D:\KEMI-Test\work`；
5. 验证远端进程的 TEMP/TMP 指向 `D:\KEMI-Test\tmp`；
6. SFTP 上传、远端 SHA-256、下载、本地 SHA-256 一致；
7. 验证 Windows 防火墙只允许用户确认的 Private `/24` 或更窄网段；
8. 断网恢复后重新核对同一 host key。

结果必须形成 `NodeVerificationReport` 和 `WorkflowArtifact`，包含来源设备标签、检查状态、耗时和证据引用，不包含密码、私钥或文件正文。

## 3. 必须补齐的真实压力与故障验收

### 3.1 SSH/SFTP

- 1 GiB 上传过程中主动取消，服务端没有本轮临时残留；
- 传输约 50% 时断网，操作明确失败且恢复网络后可重试；
- 上传和下载均记录本地/远端 SHA-256 并一致；
- 多台设备同时使用时，会话、进度、取消和证据互不串扰；
- 主机密钥变化必须阻断，不得自动接受。

### 3.2 GitHub 代理

- 从真实 `verge-mihomo`/Clash 监听发现非固定端口；
- 通过 VibeKits UI/Harness 预览并应用 GitHub host-scoped proxy；
- 停止代理后显示配置失效；
- 端口变化后旧计划被拒绝，重新探测可恢复；
- 应用验证失败时恢复旧值，用户后来修改的值不得被旧 rollback 覆盖。

当前只读 `ls-remote` 已通过，不需要重复证明账号登录；仍需补的是产品内 apply/rollback 的真实操作证据。

### 3.3 私有 GitHub 受控备份

在专门的可回收测试分支完成一次真实闭环：

1. `backup_preview` 显示准确文件集合且秘密扫描通过；
2. 用户第一次审批后创建 commit，但当前工作分支、HEAD、index 和工作区不变；
3. 用户第二次独立审批后 push 到计划生成的 `backup/<device-or-project>/<date>`；
4. `ls-remote` 返回的远端 SHA 与计划 commit SHA 一致；
5. 重试不得重复 commit；禁止 force、删 ref、改 tag 和绕过 hooks；
6. 测试结束后是否删除远端测试分支由用户另行明确审批。

当前只完成私有仓库只读访问和本地 bare remote push 测试，未执行真实私有仓库 push。

## 4. 发布证据与门禁

完成以上能力后必须归档：

- helper 签名验证、文件哈希、协议版本和白名单清单；
- Windows 配置前后节点报告及精确回滚报告；
- 两台 Mac 的不同设备指纹、连接结果和单设备撤销结果；
- 1 GiB 取消、50% 断网、双向 SHA-256 和无残留证据；
- GitHub proxy 应用/失效/恢复记录；
- 私有仓库 preview、两次审批、commit SHA、远端 SHA；
- Windows Release 资产校验、自动测试、静态分析和启动证据；
- 对应 UI 截图或录屏及脱敏后的模块审计记录。

只有上述证据进入 `docs/acceptance/` 后，才能把 NODE-001～010、NET-001～003 和 GIT-001～003 标记为完整通过。

## 5. 不阻塞首个多设备版本的后续能力

以下能力有价值，但不应阻塞使用独立公钥的首个多设备版本：

- NODE-009 SSH CA、短期证书、KRL 和外部签发服务；
- NET-004 系统级 WinINet/WinHTTP/PAC/TUN 切换；
- P4 业务项目提供的签名 `KemiWindowsTestAgent` 编排。

这些能力未完成时必须保持不可执行或明确标记为扩展项，不得退化为共享私钥、任意管理员脚本或全局代理。

## 6. 建议实施顺序

1. 签名 UAC helper、协议、白名单和回滚测试；
2. 单设备公钥登记与 Windows 真机 apply/verify/rollback；
3. 多设备登记、onboarding 和单设备撤销；
4. 两台 Mac 的 SSH/SFTP、断网和大文件实证；
5. 产品内 GitHub proxy apply/rollback 实证；
6. 私有仓库受控 push 与远端 SHA 实证；
7. 汇总发布证据并更新需求总账和验收记录。

## 7. 完成判定

完成不是“代码入口存在”，而是以下条件同时成立：签名 helper 已随包、Windows 系统配置可安全执行和精确回滚、至少两台 Mac 独立接入且可单独撤销、SFTP 故障场景通过、真实私有 GitHub 备份通过、证据归档完成。

## 8. 2026-08-21 dev.61 续研结果

### 已完成并自动验收

- 新增版本化 helper 协议：固定 action ID 白名单、计划/体检 SHA-256、短期 nonce、15 分钟上限、防重放、禁止 `command/cmd/script/shell/executable/arguments/powershell` 参数和请求绑定回执。
- 新增 helper 客户端安全门禁：执行前必须同时验证 Authenticode 状态、发布者、Release 固定 SHA-256 和协议版本；UAC 拒绝、取消、超时、进程失败、回执无效保持不同错误状态。
- 新增 Ed25519 设备生命周期：严格解析 OpenSSH Ed25519 blob，重复指纹拒绝，禁用、恢复、撤销和最近连接记录；设备清单原子保存，`authorized_keys` 只输出 active 设备，撤销一台不会影响其他设备。
- 新增无秘密 onboarding：固定 host key、`StrictHostKeyChecking yes`、Private IPv4 `/24` 或更窄网段；拒绝 localhost、宽网段、私钥、RSA 和损坏公钥。
- `windows_node.list_devices` 与 `windows_node.export_onboarding` 已进入 Harness executable catalog，并完成真实桥接调用；登记、撤销仍保持不可执行，直到签名 helper 能原子同步系统 `authorized_keys` 和 ACL。
- 新增 `NodeVerificationReport` 与 `WorkflowArtifact`：强制记录来源设备、平台、固定 host key、11 个跨设备检查、耗时和脱敏证据引用；localhost、缺项、秘密证据和“有失败却标记通过”均拒绝。
- GitHub 代理代码补齐计划摘要校验、端口/状态漂移拒绝和“用户后来修改的配置不被旧 rollback 覆盖”；受控 Git 备份补齐不推进当前分支/HEAD、不清空工作区和内容变化使旧 preview 失效。相关 Windows/代理/Git 测试通过。

### 仍需外部输入，不能用模拟测试替代

1. 可信代码签名证书及预期发布者名称，用于签署真正执行系统动作的 helper；仓库不得保存签名私钥。
2. 两台真实 Mac 各自生成独立 Ed25519 密钥，并从局域网完成 1 GiB 取消、50% 断网、双向 SHA-256、host key 固定和单设备撤销。
3. 用户对真实私有仓库测试分支的两次独立外部写入批准：先 commit、再 push；当前消息不视为这两次批准。

在以上三个外部前提到位前，`apply/enroll/revoke/rollback/verify` 保持不可执行是安全门禁，不属于 UI 漏做。可复用设计和接入步骤见 `27_SECURE_WINDOWS_NODE_INTEGRATION_GUIDE.md`。
