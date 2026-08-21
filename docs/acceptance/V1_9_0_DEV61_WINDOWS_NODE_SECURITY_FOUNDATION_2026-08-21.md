# v1.9.0-dev.61 Windows 节点安全底座验收

## 结论

代码安全底座通过，签名 helper 实体与外部真机证据待外部资源。不可执行入口继续保持关闭，不伪报完整完成。

## 自动验收

| 范围 | 结果 | 覆盖 |
|---|---:|---|
| Helper 协议与客户端 | 6/6 PASS | action 白名单、规范摘要、过期、防重放、命令参数拒绝、签名/发布者/哈希/协议、UAC/取消/超时、绑定回执 |
| 设备生命周期 | 3/3 PASS | 两把独立 Ed25519、重复拒绝、禁用/恢复/撤销、最近连接、原子清单、active-only keys、私网 `/24` |
| 跨设备报告 | 2/2 PASS | 11 项必需检查、WorkflowArtifact、localhost/缺项/秘密/伪通过拒绝 |
| Harness 桥接 | 20/20 PASS | 设备列表、onboarding 实际调用，不含秘密，不触发写入审批 |
| Windows/代理/Git 领域 | 15/15 PASS | Windows 只读真机探测、代理摘要/漂移/回滚、备份隔离/竞态 |

## 可执行目录变化

- 新增可执行：`vibekits.windows_node.list_devices`。
- 新增可执行：`vibekits.windows_node.export_onboarding`。
- 继续不可执行：`apply/enroll_device/revoke_device/rollback/verify`；原因是 Release 尚无可信证书签署的 helper，系统 `authorized_keys`/ACL 不能由普通 App 直接写入。

## 外部验收清单

1. 提供代码签名证书的发布者名称和 CI 签名产物，不提供私钥给仓库。
2. 将签名 helper 的 SHA-256、文件版本和协议版本写入 Release manifest。
3. 在 Windows 管理员 UAC 下执行一次 apply 和精确 rollback。
4. 两台 Mac 使用不同 Ed25519 密钥完成连接、1 GiB 取消、50% 断网和双向 SHA-256。
5. 撤销一台后仅该设备失败，另一台继续成功。
6. 对真实私有仓库分别批准 commit 与 push，并核对远端 SHA。

## 复用资料

其他项目应从 `docs/27_SECURE_WINDOWS_NODE_INTEGRATION_GUIDE.md` 复用分层、协议、设备生命周期、智能体接入和门禁，不能复制任何开发机秘密或把 mock 结果作为真实证据。
