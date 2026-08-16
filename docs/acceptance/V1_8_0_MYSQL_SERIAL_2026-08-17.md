# v1.8.0 MySQL/MariaDB 与串口调试验收

日期：2026-08-17  
版本：`1.8.0+10`  
平台：Windows x64（macOS 工程基线已更新，未在本机编译）

## 交付范围

- PostgreSQL/MySQL/MariaDB 统一远程连接、对象浏览、分页和只读 SQL。
- 最近连接和系统安全凭据复用/删除；数据库操作独立 Isolate、超时和停止。
- 串口枚举/手输、可编辑波特率、完整帧格式、文本/HEX、行尾、发送历史、RX/TX 日志与保存。
- 串口会话独立 Isolate，100ms 接收聚合、日志上限、关闭与销毁释放。

## 自动验证

| 检查 | 结果 |
|---|---|
| `dart format lib test` | 通过 |
| `flutter analyze` | `No issues found` |
| 数据库/串口/设置定向测试 | 16/16 通过 |
| `flutter test --reporter expanded` | 271/271 通过 |
| Windows Release 构建 | 通过，78.8 秒 |
| Release 隐藏启动 5 秒 | 携带 `README.md` 启动，5 秒未提前退出；仅停止本次 PID |

数据库测试覆盖旧 PostgreSQL 记录兼容、MySQL/MariaDB 配置往返、只读 SQL 防护、真实本地 TCP 握手等待与取消、Widget 默认值/保存/删除凭据。串口测试覆盖参数与编解码、原生库加载及端口枚举、无效端口原生失败时 UI 计时器继续运行、模拟会话收发/关闭、1024×700 高级参数和 HEX 错误、销毁释放。

## 资源与性能边界

- 远程数据库操作使用短生命周期 Isolate；15 秒超时或停止会终止 Isolate/连接。
- 串口原生句柄只存在于工作 Isolate；UI 不执行阻塞读，接收约 100ms 合并一次。
- 串口单次发送最大 1MiB；界面日志最多 2MiB/2000 条，避免长时间调试拖慢窗口。
- 关闭串口先恢复可操作状态，再后台等待句柄释放；工作区销毁同样发出关闭。

## 真实环境边界

- 当前 Windows 机器未枚举到物理 COM 设备，不能把自动化模拟收发写成真实 USB/串口回环通过。
- 当前机器没有 Docker/Podman/MySQL/MariaDB 服务，不能把驱动参数和 TCP 取消测试写成真实数据库成功连接。
- macOS 权限声明已加入 Debug/Release entitlements，但仍需 Apple Silicon/Intel 实机完成构建、USB 串口回环和 Keychain 连接记录验证。

## 发布产物

EXE 文件/产品版本均为 `1.8.0+10`。正式目录为 `release/Vibekits-1.8.0-windows-x64`，ZIP 为 `release/Vibekits-1.8.0-windows-x64.zip`。ZIP 已核对包含 EXE、`libserialport_plus.dll`、7-Zip、OCR 模型和发布说明。

ZIP 与 EXE 的最终校验值写入 `release/SHA256SUMS.txt`，避免发布说明自身进入 ZIP 后产生循环哈希。Git 提交与 `v1.8.0` 标签须同步到 `backup` 和 `cloud` 后才完成本批。
