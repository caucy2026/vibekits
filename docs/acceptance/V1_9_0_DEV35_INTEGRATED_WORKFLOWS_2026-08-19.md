# v1.9.0-dev.35 跨工具任务链验收

日期：2026-08-19  
平台：Windows x64  
版本：`1.9.0-dev.35+45`

## 1. SSH 与 SFTP 一次认证

流程：Harness 调用 `vibekits.remote.open_interactive` → App 立即切换到远程工作台并填入主机/用户名/端口 → 用户在 App 安全输入框输入一次密码 → SSH 登录 → 同一个 `RemoteSftpSessionHandle` 打开 SFTP channel → 双栏文件界面。

验证结果：

- Harness 工具参数和返回值不包含密码。
- 已保存的匹配会话自动复用用户名、端口、私钥路径、系统凭据和已确认主机指纹。
- 新目标没有用户名时保留明确提示，不猜测 root 或当前 Windows 用户。
- SFTP connector 收到的对象与已登录 SSH session 是同一个实例。
- SFTP 打开后没有第二个密码框；关闭文件区不关闭 SSH 终端。
- 切换新目标时已有其他终端标签继续运行。

## 2. 截图、OCR 与 Harness

流程：Harness 调用 `vibekits.ocr.capture_screen` → 当前 Harness 页切换到截图 OCR → 用户框选屏幕区域 → 内置 PP-OCRv6 tiny 在本地 Isolate 推理 → 结构化结果返回原 Harness 工具调用。

返回内容：图片路径、全文、逐行文字、置信度、坐标、图片宽高、推理耗时和运行时。图片不上传；取消或失败返回真实错误，不伪造空成功。

## 3. 自动验证

| 项目 | 结果 |
|---|---:|
| Harness 工具桥 | 16/16 |
| 远程工作区 Widget | 14/14 |
| 合计 | 30/30 |
| 定向 Flutter Analyze | 0 问题 |
| Windows Release 构建 | 通过 |
| Release 自包含资产 | 17/17 |

覆盖：工具目录、权限审批、意图导航、目标更新、一次密码、SSH/SFTP 会话复用、SFTP 关闭、截图 OCR 结果回传、失败/取消与凭据脱敏。

## 4. 功能审计结论

完整任务链和后续缺口记录在 `docs/20_INTEGRATED_DEVELOPER_WORKFLOWS.md`。下一批 P0 是 ADB 专用链和串口长会话，而不是新增孤立菜单。

本机没有可控 SSH/SFTP 服务、Android 真机或物理串口，因此真实网络、断网、大文件传输和硬件回环仍按 E-08/E-07/E-01 补证；模拟/Widget 结果不替代实机证据。
