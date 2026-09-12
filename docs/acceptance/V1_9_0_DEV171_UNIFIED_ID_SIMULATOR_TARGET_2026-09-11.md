# VibeKits dev.171 统一 ID 仿真机访问验收记录

日期：2026-09-11
候选版本：`v1.9.0-dev.171+2171`
需求基线：`docs/65_UNIFIED_ID_SIMULATOR_TARGET_REQUIREMENTS.md`

## 1. 本轮实现

- 远程协助 ID 与仿真机 ID 共用同一 RustDesk/HBBS 数字 routing ID。
- 新增独立、默认关闭、可持久化的“允许作为仿真机”授权域。
- 被调试端只监听 `127.0.0.1:32147`，不开放桌面、系统 SSH、任意端口代理或局域网监听。
- 控制端专用隧道区分 `listener_ready` 与 `transport_connected`，未建立真实传输前不得宣称连接成功。
- 原生进程增加易失权限门禁；只有显式授权后，固定仿真机端点才可自动批准。
- UI 只有在原生连接表同时满足已授权、未断开、目标端点为 `127.0.0.1:32147` 时才显示绿色“已连接”和对端 ID。
- PAD 保持只作为控制端；macOS/Windows 共用协议和 Flutter 状态模型。
- 关闭仿真机授权不会误停仍在使用的普通远程协助。

## 2. 已通过门禁

| 门禁 | 结果 | 证据 |
|---|---|---|
| Rust 原生门禁单测 | 通过 | `cargo test --locked --no-default-features --features flutter --lib vibekits_harness_relay::tests`，3/3 |
| Flutter 定向回归 | 通过 | 4 个测试文件，22/22 |
| Flutter 定向静态分析 | 通过 | 8 个源码/测试入口，0 issue |
| macOS Release 构建 | 通过 | `build/macos/Build/Products/Release/Vibekits.app`，822.4 MB |
| 版本一致性 | 通过 | `CFBundleShortVersionString=1.9.0.171`，`CFBundleVersion=2171`，UI=`v1.9.0-dev.171+2171` |
| macOS 主程序架构 | 通过 | `x86_64 arm64` |
| 内置中继架构 | 通过 | `x86_64 arm64` |
| 本地整包签名完整性 | 通过 | 临时 APFS 卷上 ad-hoc 深度签名后 `codesign --verify --deep --strict` 通过 |
| 真实启动/UI 冒烟 | 通过 | 顶部显示同一 ID `1554650784`、仿真机关闭、等待连接；管理面板显示独立仿真机开关且默认关闭 |

定向 Flutter 测试覆盖：默认关闭与独立持久化、同一 ID、固定回环端点、生命周期撤销、普通远程协助隔离、真实连接筛选、PAD 控制端约束、紧凑/双屏布局边界、受管隧道就绪语义与非法目标拒绝。

## 3. 尚未通过、不得冒充完成

以下项目仍需真双机证据，完成前不得称为正式发布：

1. 在当前 Mac 上由用户明确授权临时打开“允许作为仿真机”。
2. 把哈希校验后的最小 RustDesk 源码包发送到已验证 SSH 指纹的 Windows 58，仅在 `D:\KEMI-Test` 新版本目录构建 Windows helper。
3. Windows 58 仅输入 Mac 的 ID，分别完成 LAN/P2P 与强制 HBBR 中继连接。
4. 两条链路均完成 MCP initialize、工具目录、只读查询和一项受控 App 操作。
5. 连接中关闭授权，验证旧连接失效、新调用拒绝、本地 Harness 与普通远程协助不受影响。
6. Windows 主程序 Release、安装、启动、性能和兼容性验收。
7. 正式 macOS Developer ID 签名、公证与 Gatekeeper；本记录中的 ad-hoc 签名只证明本地包完整性，不等同正式认证。

## 4. 环境与可追溯信息

- macOS 通用中继合并前 SHA-256：`4ec1c74feb717ea8e184b4a6b2ffd8b25c46af3b5c38d20493d7e26922db7b8b`
- APFS 候选内签名后中继 SHA-256：`9079322cfe9e1d292a4a20492847fd57cb07d6ca830d597fc392299db373fd66`
- Windows 58 SSH ED25519 指纹：`SHA256:ikZ6NXAH3VFBGooSCeKW0JY9+h0cIcQOzib4fxmvz6M`
- Windows 目标限定：`kemi-test@192.168.3.58`，只写 `D:\KEMI-Test`，禁止写 C 盘和覆盖旧工作区。

## 5. 发布结论

本轮代码、macOS Universal 构建和本机 UI 冒烟已经通过；真双机 P2P/HBBR、Windows Release 与正式 macOS 认证尚未闭环，因此当前结论是“开发候选可进入双机验收”，不是“正式发布完成”。
