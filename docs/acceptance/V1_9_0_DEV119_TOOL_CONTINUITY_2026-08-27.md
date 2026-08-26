# v1.9.0-dev.119 工具连续使用验收

## 验收目标

工具不能只在第一次打开时可用。重复进入必须恢复非敏感状态；SSH、数据库等多目标必须并存；密码只进入系统凭据库；Harness 必须读取同一份能力和历史规则。

## 本轮结果

- SSH/SFTP：复核成功连接会自动保存主机、用户、端口、主机指纹和最近使用时间；密码进入平台安全凭据库；多个终端会话可并存；已认证 SSH 会话直接复用于 SFTP。
- API：保存最近 30 个方法、URL 和非敏感头；正文、Authorization、Cookie、API Key、Token、Secret 不进入普通设置。
- ADB：保存最近 20 个无线地址和 50 条命令；命令仍严格绑定所选设备序列号。
- 串口：保存最近 50 条发送内容；完整串口参数继续恢复。
- 网络抓包：修正已有工作区未出现在独立工具列表的问题。
- 19 个独立工作区全部登记 `repeatUse / multiTarget / secretHandling` 使用合同，`vibekits.system.capability_check` 可直接返回给 Harness；新增工作区漏登记会使测试失败。

## 防回归证据

- 工具、UI 与合同测试：29/29 通过。
- 设置持久化测试：3/3 通过。
- 目标文件 Flutter Analyze：0 问题。
- Windows Release 构建成功，产物为 `build/windows/x64/runner/Release/vibekits.exe`。
- ADB/串口专项额外验证：历史保存回调收到真实输入；历史存储抛错时，真实连接、命令和发送仍继续成功。

## 未伪装为完成的项目

下列项目已进入 `39_TOOL_REAL_USAGE_SCENARIO_MATRIX.md`，仍需逐项实现和真实设备验收：串口多 USB 独立配置、ADB 设备别名、Git 最近仓库、PCAP 最近文件/过滤器、音频最近文件与多文件对比、虚拟机配置模板、资源诊断趋势报告。
