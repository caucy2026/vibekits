# 安全 Windows 测试节点复用指南

版本：1.0
适用：需要把普通权限桌面 App、安全 UAC helper、SSH 多设备身份和智能体工具调用组合起来的项目。

## 1. 最高准则

1. 主 App 保持普通权限；只有用户确认过的短期计划可触发 UAC。
2. helper 只接受固定协议和预定义 action ID，永远不接受 shell、命令行、脚本或任意可执行路径。
3. 候选、计划、执行、回执、验证是五个独立事实；UI 入口存在不等于系统动作成功。
4. 每台设备使用独立 Ed25519 公钥；私钥不进入节点、App、Harness、日志或 onboarding。
5. 远程 host key 必须固定；变化立即阻断，不自动接受。
6. 外部写入使用分离审批；Git commit 与 push 不能合并成一次授权。

## 2. 推荐分层

| 层 | 职责 | 禁止事项 |
|---|---|---|
| 普通权限 App | 只读体检、生成计划、展示差异、收集用户批准 | 直接执行管理员脚本 |
| Helper 协议 | plan ID、摘要、nonce、时效、action IDs、参数、回执 | 任意命令/参数透传 |
| 签名 Helper | 重新核验现场状态、执行单个原子动作、保存前后状态 | 删除用户数据、卸载系统组件 |
| 设备注册表 | 公钥指纹、状态、最近连接、原子 `authorized_keys` 投影 | 保存私钥或共享密钥 |
| 跨设备验证器 | host key、SSH/SFTP、SHA-256、故障注入、证据引用 | localhost 冒充外部设备 |
| Harness 适配器 | 从单一 ToolSpec 发现并调用已闭环能力 | 宣传不可执行工具 |

## 3. Helper 请求合同

请求至少包含：

```json
{
  "protocolVersion": 1,
  "operation": "apply",
  "planId": "短期随机ID",
  "planDigest": "64位SHA-256",
  "inspectionDigest": "64位SHA-256",
  "nonce": "一次性随机值",
  "issuedAt": "UTC ISO-8601",
  "expiresAt": "UTC ISO-8601，最长15分钟",
  "actionIds": ["windows.sshd.start_and_enable"],
  "parameters": {},
  "requestDigest": "规范化JSON的SHA-256"
}
```

helper 必须重新检查：协议版本、签名调用方、时效、nonce 未使用、摘要、action 白名单、依赖、现场状态未漂移。回执必须绑定请求摘要和 nonce，并为每个动作记录 before/after 摘要、状态、耗时和脱敏说明。

## 4. 签名与发布

- 构建产物只保存 helper 公钥身份：预期发布者、SHA-256、文件版本和协议版本。
- 代码签名私钥保存在 CI/HSM 或组织证书服务，不进入源码、安装包或开发日志。
- App 在每次执行前核验 Authenticode、发布者、固定哈希和协议；任一不一致即拒绝启动。
- Release 校验脚本必须确认 helper 存在、签名有效、版本和哈希与 manifest 一致。

## 5. 多设备生命周期

1. 客户端本机生成独立 Ed25519 密钥。
2. App 只接收公钥，解析 OpenSSH blob 并计算 SHA-256 指纹。
3. 重复指纹一律拒绝；标签不能替代身份。
4. 注册表原子写入，系统 `authorized_keys` 是 active 设备的确定性投影。
5. 禁用可恢复；撤销保留审计记录但从投影删除。
6. helper 原子替换系统文件并校验 ACL；失败恢复旧文件。
7. 至少一把密钥真实登录成功前，密码认证门禁保持开启。

## 6. 跨设备验收

每台来源设备生成一个 `NodeVerificationReport`，至少覆盖：固定 host key、公钥登录、`pwsh -NoProfile`、工作目录、TEMP/TMP、SFTP 上传/下载 SHA-256、1 GiB 取消无残留、约 50% 断网失败与重试、防火墙范围、断网恢复后相同 host key。

报告只保存设备标签、状态、耗时和证据引用，不保存密码、私钥或文件正文。两台设备均通过后撤销其中一台，必须证明被撤销设备失败而另一台继续成功。

## 7. 智能体工具接入规则

- ToolSpec 是唯一能力清单；新功能必须同时提供 `id/description/risk/inputSchema/handler/test`。
- read-only 工具可直接调用；系统写入、设备控制和外部 push 必须进入审批层。
- handler 未接通或签名资源不存在时，工具只进入 full catalog，不进入 executable catalog。
- 每次调用记录模块日志；默认开启，可关闭和删除；日志只记录参数摘要、目标、状态和证据引用。

## 8. 最小自动门禁

- 协议：未知 action、篡改摘要、过期、重放、命令参数注入全部拒绝。
- 二进制：错误签名、发布者、哈希、协议版本全部拒绝且不得启动 helper。
- 设备：私钥/RSA/损坏 key、重复指纹、过宽 CIDR 拒绝；撤销单设备不影响其他设备。
- 回执：请求摘要、nonce、动作集合和 before/after 证据必须匹配。
- 验证：localhost、缺项、秘密证据、失败项伪装整体通过全部拒绝。
- GitHub：代理状态漂移拒绝，失败恢复旧值，后来修改的值不被旧 rollback 覆盖。
- Git：preview 后内容变化使计划失效；备份 commit 不改变当前分支、HEAD、index 或工作区。

## 9. 不能由自动测试替代的证据

- 组织可信代码签名证书签署的真实 helper。
- 真实 Windows 管理员 apply/rollback 前后报告。
- 两台不同外部设备的独立密钥和故障注入。
- 真实私有仓库的 commit/push 两次审批与远端 SHA。

这些证据缺失时必须在发布报告中明确列为外部门禁，不能用 mock、localhost 或 UI 截图替代。
