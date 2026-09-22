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

网络代理组件使用 `component_id: network_proxy`。macOS 分别发布 `x64` 和 `arm64`；Windows 当前发布 `x64`。

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
