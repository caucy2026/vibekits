# 系统资源诊断与 Harness 接口

## 目标

当用户说“电脑/手机卡顿、发热、快死机、编译很慢”时，Harness 不靠猜测，先调用 Vibekits 的只读资源探针取得 CPU、内存、GPU、磁盘和 Top 进程证据，再给出解释和下一步动作。

## 界面入口

`开发工具 → 系统诊断 → 资源诊断`

- 打开后立即显示界面，资源读取在后台进行。
- Windows/macOS 显示本机快照；Windows 还可输入 ADB 序列号诊断 Android 真机。
- GPU 计数器因硬件、驱动或系统权限不可用时显示“未取得”，不得填充模拟值。
- 单次正常不代表间歇卡顿已排除。

## Harness 工具

工具 ID：`vibekits.system.resources`

输入：

```json
{
  "adbSerial": "192.168.3.63:5555",
  "samples": 5,
  "intervalMs": 700
}
```

- `adbSerial` 可省略，省略时诊断当前运行 Vibekits 的系统。
- `samples` 为 1～10，默认 3。
- `intervalMs` 为 250～5000，默认 700。

输出包含最新完整快照、连续采样 `series` 和汇总 `summary`。汇总提供 CPU/内存平均值与峰值，以及多次进入 Top 5 的进程。调用是只读操作并进入当前工具的 Harness 日志。

## 平台证据

| 平台 | CPU | 内存 | GPU | 存储/进程 |
|---|---|---|---|---|
| Windows | `Get-Process` 双采样 | `.NET ComputerInfo` | GPU Engine 性能计数器与显卡注册表；系统不支持时留空 | `.NET DriveInfo` / `Get-Process` |
| Android | `/proc/stat` 双采样 | `/proc/meminfo` | Qualcomm KGSL（设备支持时） | `df /data` / `top` |
| macOS | load/核心数近似 | `vm_stat` | 当前留空 | `df` / `ps` |

## 智能体诊断顺序

1. 默认连续采样 3 次；间歇问题采样 5～10 次。
2. 先判断 CPU、内存、GPU、磁盘哪个资源持续逼近阈值。
3. 用重复出现的 Top 进程建立关联，但不能仅凭一次相关性自动结束进程。
4. Android 问题继续调用 ADB Logcat、截图或文件工具；磁盘不足继续调用系统盘分析；源码回归继续调用 Git/Diff。
5. 任何关闭进程、卸载或删除动作都必须进入对应工具的风险授权流程。

## 边界

- 本工具不杀进程、不卸载、不清理文件。
- macOS CPU 当前是负载近似，不宣称为精确瞬时忙碌率。
- Android GPU 计数器不是跨厂商标准；缺失就是未知。
- 诊断结论必须携带证据来源、采样次数和时间，避免把旧快照当作当前状态。
