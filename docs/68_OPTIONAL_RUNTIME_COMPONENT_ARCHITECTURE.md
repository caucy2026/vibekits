# VibeKits 可选运行时组件架构

## 目标

VibeKits 主程序保持可启动、可更新；QEMU 虚拟机和 Mihomo 网络代理按需从 KEMI 商城安装。两个运行时是主程序的功能组件，不是可独立运行的应用。

## 组件身份

组件使用独立的市场记录，但必须声明宿主依赖：

```json
{
  "artifact_type": "component",
  "host_package_name": "com.caucy.vibekits",
  "component_id": "virtual_machine",
  "component_display_name": "虚拟机（QEMU）",
  "os_type": "windows",
  "architecture": "x64",
  "standalone": false
}
```

网络代理组件使用 `component_id: network_proxy`。本轮交付 Windows `x64`。macOS 保留已有内置运行时兼容；独立组件签名、公证与真机验收尚未完成，不在本轮发布范围。

商城描述必须包含：

> VibeKits 功能组件，依赖 VibeKits 主程序，不能单独运行，不创建独立应用入口。

## 安装边界

组件安装器或组件下载器必须先检查主程序包名 `com.caucy.vibekits`：

- 主程序不存在：停止安装，显示“请先安装 VibeKits”，提供主程序商城入口。
- 主程序存在：下载到临时目录，校验 HTTPS、精确字节数、SHA-256、平台签名和组件清单后原子安装。
- 安装失败：删除临时目录，保留上一版组件。
- 组件不得创建开始菜单、桌面、Dock 或启动台入口。

Windows 安装根目录：`%LOCALAPPDATA%\\Vibekits\\components\\<component_id>\\<version>\\`。

macOS 安装根目录：`~/Library/Application Support/Vibekits/components/<component_id>/<version>/`。不得把下载内容写入已签名的 `.app` 包内部，否则会破坏签名和公证。

## 主程序运行时解析

解析顺序固定为：

1. 当前平台用户组件目录中的已验证版本；
2. 旧版本内置运行时目录（升级兼容）；
3. 不存在时返回 `missing`，不能尝试 PATH、系统目录或任意文件扫描。

组件状态至少包括 `missing`、`installing`、`installed`、`outdated`、`invalid`、`failed`。只有 `installed` 且 manifest、签名和架构校验通过时，才允许启动 QEMU 或 Mihomo。

## UI 行为

网络代理和虚拟机页面分别显示组件状态。状态为 `missing` 时显示组件大小和“从应用中心安装”；点击启动按钮也进入同一个安装流程。下载完成后返回原页面并自动重新检查运行时。组件页不显示“打开应用”，只显示“安装”“更新”“卸载组件”。

## 组件之间的关系

QEMU 与 Mihomo 互不依赖，可以分别安装和卸载：

- 仅使用虚拟机时不下载网络代理；
- 仅使用网络代理时不下载 QEMU；
- 主程序、Harness、更新器、市场和基础网络通信始终属于核心包。

## 兼容与发布门禁

每个组件必须有独立版本、架构、精确文件大小、SHA-256、签名证据和宿主依赖字段。组件不能被当作普通 APP 调用自更新或“打开”。发布后必须验证：主程序未安装时被拦截，主程序已安装时可按需安装，安装后运行时可发现，校验失败时不会启动，卸载组件后主程序仍可启动。

## Windows 旧商城协议兼容（2026-09-22）

在线商城文档未声明组件元数据字段，不能依赖服务器保存扩展字段。
客户端按两个精确包名识别组件（不按名称、描述或任意前缀猜测）：

- `com.caucy.vibekits.component.virtual_machine`
- `com.caucy.vibekits.component.network_proxy`

宿主、组件 ID、平台、架构、版本和逐文件 SHA-256 仍必须写入包内
`component-manifest.json`。安装器和 PE 使用与主程序一致的有效发布者签名。
Windows 商城交付已签名 EXE；无宿主时拒绝，组件无独立快捷方式。
激活记录为 `active.json`，上次记录保存在 `active.previous.json`。
默认核心构建不包含 QEMU/Mihomo，旧内置运行时仍可被识别。

最终发布门禁：同一份最终签名 Windows 安装包必须在 4567540178 和
6192992780 完成安装、启动、仿真重连及远程工具调用。代码或单元测试通过
不等于已通过双机验收；结果另记验收报告。

## Android/PAD 扩展需求（2026-09-22）

用户要求 Android 同样使用组件架构，大组件在首次使用时从 KEMI 商城下载。
核心包保留启动、设置、商城、安全校验、权限撤销和被仿真传输；这些能力不能依赖尚未安装的可选组件。
OCR/语音模型、对应推理运行时列为可选组件候选。不能把仅桌面可执行的 QEMU/Mihomo ZIP 直接下发 Android。

Android 原生代码必须由系统安装的同发布者组件 APK 提供，通过受签名权限保护的 Binder 服务调用；不从可写下载目录直接执行 ELF 或加载未经系统验证的代码。模型数据可由组件 APK 提供只读资源。组件无 Launcher 入口，校验宿主包名 com.vibekits.vibekits、平台 android、实际 ABI、宿主协议版本及签名，服务不可用时保留原功能页并提供安装/重试。
使用功能时显示大小、用途和安装按钮；用户确认后从当前平台商城详情取得 HTTPS、精确大小、SHA-256，交给系统安装确认。安装后自动重查服务再继续原操作。取消、断网、低空间、错误包、错误签名不能损坏主程序。不得启动时自动下载，不弹全局更新提示。

验收必须包含空组件启动、首次使用、取消、错误校验、升级回退、卸载后主程序仍可启动，并在 PAD63 真机验证。商城尚无已核实的 Android 组件记录，禁止硬编码虚构下载地址或宣称商城交付完成。

## Android 组件状态（2026-09-22）

此节是待实现需求，不代表已经交付。当前 Android 仍有内置模型，商城组件下载、签名 Binder 服务和首次使用恢复尚未实现。完成拆分并在 PAD63 验证前，不得声称 Android 大组件已改为按需下载。现有 ModelStore 的校验仅可复用，不能作为商城组件端到端验收证据。
