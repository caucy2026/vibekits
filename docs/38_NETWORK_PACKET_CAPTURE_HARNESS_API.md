# 网络抓包（PCAP）与 Harness 接口

## 目标

VibeKits 在“开发工具 → 网络开发 → 网络抓包（PCAP）”提供完整闭环：实时抓包、过滤、停止、标准 PCAP 保存、已有 PCAP 读取、协议/端点统计和 Harness 调用记录。UI 与智能体共享同一个后台抓包任务，不维护两套状态。

## 开源内核与分层

- Windows 实时抓包内核：WinDivert 2.2.2，LGPL；发行运行时、许可证和对应完整源码均保存在 `native/windivert/`。
- VibeKits 原生适配器：`windows/runner/packet_capture_helper.cpp`。仅以嗅探/只读方式打开网络层，实时输出摘要，同时写标准 PCAP `LINKTYPE_RAW (101)`。
- PCAP 读取与分析：`packet_capture_service.dart`，由 VibeKits 自己解析 IPv4/IPv6、TCP、UDP、ICMP，并标注 DNS、HTTP、TLS、QUIC。
- 运行时文件全部安装到 `tools/packet_capture/`，不依赖 Npcap、WinPcap、Wireshark 或系统 PATH。

Windows 的通用网络抓包驱动需要管理员权限。普通权限启动时 APP 必须在 4 秒内明确返回“以管理员身份运行”，不得无限加载或假装已抓包。

## UI 操作

1. 输入过滤器或点“全部/TCP/UDP/DNS/HTTPS”预设。
2. 点“开始抓包”，列表实时显示协议、源、目标、方向、接口编号和长度。
3. 点“停止并保存”，PCAP 会刷新并显示协议统计。
4. “读取 PCAP”可打开既有 `.pcap/.cap`；“另存为”复制当前结果。
5. 默认目录：`<APP>/tmp/network-capture/`。

## Harness 接口

| 接口 | 风险 | 参数 | 结果 |
| --- | --- | --- | --- |
| `vibekits.capture.status` | 只读 | 无 | 内核、任务、包数、路径、最近错误 |
| `vibekits.capture.start` | 控制设备 | `outputPath?`, `filter?`, `maxPackets?` | 实际输出路径和过滤器 |
| `vibekits.capture.stop` | 控制设备 | 无 | 停止状态、包数、协议和端点统计 |
| `vibekits.capture.read` | 只读 | `path`, `maxPackets?` | 逐包详情与汇总 |
| `vibekits.capture.analyze` | 只读 | `path` | 协议、字节数、Top 端点，不返回大包列表 |

每次调用由通用 Harness 活动存储记录；记录可在该工具右上角“Harness 记录”查看和删除。抓包内容可能包含隐私，智能体不得抓取未获授权的第三方设备流量。

