# VibeKits 1.9.0-dev.204 仅凭 ID 仿真授权闭环门禁

日期：2026-09-13

## 用户合同

1. 被控端只需打开一次“远程仿真”，控制端只输入统一设备 ID；不得要求用户手工交换 SSH 地址、端口、账号、密码或密钥。
2. RustDesk 直连不可用时必须自动使用 HBBR，两个路径都必须支持 MCP、SSH 命令与 SFTP 文件传输，断开后不遗留隧道。
3. 首次批准写入受限 SSH 公钥后，同一个控制设备在授权未撤销期间可继续安装、启动、停止、读取日志和安全卸载测试软件，不逐项重复弹窗。
4. 关闭远程仿真必须撤销 VibeKits 管理的授权；普通 LAN MCP、伪造 peer ID 或其他控制设备不得继承权限。
5. 远程协助的项目、会话、历史、命令、反馈和停止仍须完成真实双机验收；本机自动测试不得冒充真机通过。

## dev.203 真机故障与 dev.204 修复

目标 `4456560334` 在 dev.203 上已经证明 RustDesk 数据面可用：默认 P2P/自动回退与强制 HBBR 都能取得 204 项 MCP 工具目录、读取状态和进程。真实 SSH 主机返回 OpenSSH 10.0 与 Ed25519 指纹 `SHA256:SYx46z2xZOPrBIPfKyJAGX0XenbuKFvqZpVpVezETVs`。

第一处失败是 OpenSSH 参数 `UserKnownHostsFile` 指向包含空格的 `Application Support` 路径时没有作为一个参数引用。`ssh-keyscan` 明确报告已加入主机，但预期 known_hosts 文件为空，随后控制端误报“无法读取隧道后的 SSH 主机密钥”。dev.204 统一生成带双引号的 OpenSSH 选项并覆盖含空格的真实路径回归。

修复后，目标 `4456560334` 的默认路径和强制 HBBR 路径均真实通过：204 项目录、目标状态、目标进程、严格主机指纹校验、SSH 命令、28 字节 SFTP 上传和远端 SHA-256 回读。

第二处失败发生在完整 App 生命周期的敏感调用：原生连接表查询可能遗漏寿命很短的 HTTP 转发行，导致目标再次等待批准，而控制端 8 秒响应超时早于目标端批准窗口。dev.204 在首次 SSH 批准后，把控制设备 ID 写入 VibeKits 自己管理的 `authorized_keys` 标记；后续敏感调用仅在活动原生连接或这个精确受管标记命中时继承授权。标记随关闭开关/撤销公钥一起删除，不扩大到其他 peer。

## 已通过证据

- 源码提交：`f481ef8 fix(remote): complete id-only ssh bootstrap`。
- 版本：`1.9.0-dev.204+2204`；Info.plist：`1.9.0.204 / 2204`。
- 相关生产代码静态分析：0 issue。
- SSH 控制器、目标运行时、系统 SSH 授权和 LAN MCP 专项：23/23 通过。
- 全量 Flutter 回归：865 passed、20 个明确的真实设备/联网条件 skipped、0 failed；macOS/Windows 共用 Harness、远程管理不替换工作区、插件组合、会话删除和跨项目移动等共享契约包含在本轮通过项中。
- dev.203 目标真机实测：默认路径与强制 HBBR 均通过 204 项目录、状态、进程、SSH、SFTP 和 SHA-256；该证据只证明 dev.204 修复前的数据面与主机指纹路径，不替代 dev.204 的敏感生命周期复验。
- Universal Release：主程序 `x86_64 + arm64`，内置 Harness/ADB/7-Zip/Git/GitHub CLI 完整打包。
- Developer ID：`Developer ID Application: zhen ji (26T5WV4GLP)`；36 个 Mach-O 深度严格验签通过。
- Apple 公证：`Accepted`，Submission ID `7e4a9856-72a5-4942-938e-ce576910099b`；staple、Gatekeeper `Notarized Developer ID` 和签名后本地 Harness 实启均通过。
- 最终 ZIP：`/Volumes/ORICO/kemi-build-cache/vibekits-dev204/run-20260913-id-only-fix/delivery/Vibekits-1.9.0-dev.204+2204-macOS-universal-notarized.zip`。
- ZIP 大小：311,507,939 bytes；SHA-256：`aa9e7df43bcf2601b90f7782770ec187e852f9e744ea648f63e790133e1c1403`。

## 仍未完成的真实门禁

目标 `4456560334` 必须安装上述精确 dev.204 包后，连续执行两遍安装、清单、启动、进程、Unified Log、停止和安全卸载，第二遍不得再次弹出 VibeKits 授权；最后确认 MCP/SSH 隧道和临时文件清零。

远程协助的首次证书配对、项目/会话/历史同步、发送、增量反馈、独立停止和断开仍需真实双机证据。63 当前离线，不能用 75 或自动测试代替；Windows 58 还需同步 dev.204 并完成共享逻辑与真机运行回归。上述证据全部取得前，不声称整项远程协助/仿真发布门禁完成。
