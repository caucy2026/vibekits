# v1.9.0-dev.117 网络抓包验收

日期：2026-08-26  
平台：Windows x64  
版本：`1.9.0-dev.117+127`

## 结果

| 验收项 | 结果 | 证据 |
| --- | --- | --- |
| WinDivert 开源源码、许可证和 x64 运行时随包 | 通过 | `native/windivert/`；Release `tools/packet_capture/` |
| 原生 helper 编译与 Release 打包 | 通过 | `vibekits_packet_capture.exe` 30,720 B；`WinDivert64.sys` 94,144 B |
| 不加载驱动的确定性 PCAP 自检 | 通过 | 生成 `self-test.pcap` 72 B，1 个 DNS/UDP 样本 |
| 管理员模式真实网络抓包 | 通过 | Release helper 真抓 5 包，`live-admin-test.pcap` 1,911 B |
| APP 读取、协议/端点解析 | 通过 | DNS 样本识别为 `127.0.0.1:50000 → 8.8.8.8:53` |
| Harness 读取真实抓包文件 | 通过 | `vibekits.capture.read` 返回不少于 5 包和逐包数据 |
| Harness 分析接口 | 通过 | `vibekits.capture.analyze` 返回协议、字节与 Top 端点 |
| UI 导航回归 | 通过 | `dev_tools_widget_test.dart` 11/11 |
| 抓包专项自动测试 | 通过 | `packet_capture_service_test.dart` 3/3 |
| 本次文件静态检查 | 通过 | 6 个改动文件 No issues found |
| Windows Release | 通过 | `build/windows/x64/runner/Release/vibekits.exe` |

## 权限边界

普通 Windows 进程真实调用 `WinDivertOpen` 返回系统错误 5，证明权限检查有效。APP 现在等待原生 started/error 握手，4 秒内失败并给出管理员运行提示，不再出现无限转圈或“已开始”假状态。读取 PCAP 不需要管理员权限。

