# v1.9.0-dev.68 代理与轻量虚拟机闭环验收

日期：2026-08-22

## 用户可见流程

- 开发工具左侧第二项固定显示“Clash Verge / 虚拟机”，不再需要向下翻找。
- Clash Verge：选择 YAML，核对 `mixed-port`，一次点击并确认后启动内置 Mihomo、保存旧代理并启用 Windows 系统代理；停止按钮恢复原网络。
- 轻量虚拟机：可创建 qcow2 稀疏磁盘，或选择已有 qcow2/vhd/vhdx/vmdk/img/raw 和 ISO，设置内存与 CPU 后启动。
- 支持来宾范围：Windows 7～11、x86_64 Linux、BSD 和其他 PC x86/x64 系统；不声明 macOS 来宾或 ARM 支持。

## Harness 接口

- `vibekits.runtime.inspect` / `runtime.status`
- `vibekits.proxy.start` / `proxy.stop`
- `vibekits.proxy.system_apply` / `proxy.system_restore`
- `vibekits.vm.create_disk` / `vm.start` / `vm.stop`

所有改变网络、写磁盘和控制进程的调用都进入统一审批与可删除活动日志。`proxy.start` 接受可选 `systemProxyPort`，可原子完成启动和系统代理切换；任一步失败都会停止新进程或恢复旧值。

## 真实验收

命令使用 `VIBEKITS_LIVE_RELEASE` 指向 Windows Release，并通过真正的 `VibekitsHarnessToolBridge` 调用：

1. 启动 Release 内置 Mihomo 1.19.29，确认 `127.0.0.1:17890` 可连接。
2. 保存真实 WinINet 用户代理，切换到本地端口并读取注册表确认。
3. 使用 Release 内置 qemu-img 11.1.0 创建 1 GiB qcow2 稀疏盘。
4. 以 256 MiB、1 CPU、headless 模式启动 Release 内置 QEMU 11.1.0。
5. `runtime.status` 同时返回 Mihomo/QEMU 正在运行及 PID。
6. Harness 停止 QEMU，停止 Mihomo并恢复测试前 ProxyEnable、ProxyServer、ProxyOverride。

最终 dev.68 Release 结果：`00:04 +1: All tests passed!`

发布门禁：Windows Release 构建成功；版本 `1.9.0-dev.68+78`；Mihomo、QEMU、qemu-img 等 25 项必需运行时校验通过；`flutter analyze --no-pub` 为 0 issue。

## 仍不冒充完成的范围

- TUN/管理员驱动安装未实现，不静默提权。
- 快照、克隆、模板镜像下载和完整来宾安装矩阵仍待后续。
- macOS 的代理服务选择、QEMU 双架构签名与实机证据仍待目标机器。
