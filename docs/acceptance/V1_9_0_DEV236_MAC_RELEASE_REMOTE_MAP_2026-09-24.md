# Mac dev.236 发布与 4456560334 远程仿真改动记录

日期：2026-09-24。范围：VibeKits Mac 发布、目标 `4456560334` 的版本替换、远端目录映射及相关验证。

## 版本与发布

- 源码修复提交：`b0fe31e47e80206c17190c3e9f11f4e5506462f7`，持久化 Harness 派生会话标题并清理删除后的残留缓存。定向 Flutter 回归 26 项通过，相关 Dart 静态检查无问题。
- Mac 版本：`1.9.0-dev.236+2236`。完成 Developer ID 签名、Apple 公证 `Accepted`（提交 `ded4a1db-b005-4ae5-9709-507872bb4ba8`）和本机签名/Gatekeeper 验证。最终 ZIP 为 `420542050` 字节，SHA-256 `ed6f30b0266cd2b2c913d78414450e6681660340e31251336aca8ea7e42063bf`。
- KEMI 商城更新现有 Mac 条目 `53`，详情：<https://kemi.newlinksz.com/kd-api/api/store/apps/53?os=macos>；包：<https://cdn.newlink-sz.com/kemiAppStore/macpkg/2026/09/1790212988040_652bc263_Vibekits-1_9_0-dev_236_2236-macos-univer.zip>。本机 `/Applications/Vibekits.app` 已安装运行。
- 远端原 `/Users/mac/Applications/Vibekits.app` dev.2217 已移至 `/Users/mac/tools/Vibekits-2217-rollback.app`；远端当前运行 `/Users/mac/tools/Vibekits.app` dev.2236，签名与 Gatekeeper 已验证。保留回退包。

## 远程仿真与目录映射

- 设备 ID `4456560334`，身份 `macdeMac-mini.local`，仿真连接返回 `connected=true`、`transport=p2p_or_relay`；SSH 主机指纹 `SHA256:SYx46z2xZOPrBIPfKyJAGX0XenbuKFvqZpVpVezETVs`。
- 远端目录 `/Users/mac/kemi/vibekits` 映射为本机 Finder 目录 `/Users/newlink/VibeKits-4456560334`，经仿真 SSH 隧道、rclone SFTP 与本机 WebDAV 挂载。两侧创建目录均已互相看见。远端新建目录最初因 rclone 默认约 5 分钟的目录缓存，重新进入 Finder 后仍不可见；以 `--dir-cache-time 2s --poll-interval 0` 重启映射后，约 4 秒内可见。测试目录已清理，用户已有 `111`、`222` 保留。
- 此映射当前依赖仍在运行的仿真连接及本机挂载服务；不是开机自动挂载，也不保证断线后自动恢复。映射为 `noexec/nosuid`，适合浏览和编辑，不能当作本地可执行构建盘。
- 用户明确只要求测试远端编译能力，不要求迁移源码。已停止误启动的克隆，仅移除本轮生成的不完整 `.git`，没有保留源码副本或删除用户文件。远端未发现 Flutter、Cargo 和可用的 Xcode，因此本轮未在该机编译。

## 缓存清理状态

- 已向远端 Harness 提交限定为闲置可再生缓存的清理指令，请求 `cleanup-4456560334-20260924-01`，会话 `session-d17a543b-8e04-4287-90e2-32b829c0615f`；最后一次查询仍是 `queued`，不能认定清理已执行。指令要求保留源码、Git、当前应用、工作目录、回退包、签名资料、会话和活跃构建。
- 另已独立移除本轮产生且无人占用的远端重复下载 ZIP（约 401 MB）；正式商城 CDN 包仍保留。此操作不代表 Harness 排队任务完成。

## 当前边界

仿真连接和挂载仍保持运行，以便继续验收。本文记录已经核实的发布和测试结果；远端编译、挂载重启持久化与 Harness 清理完成均尚未验收。
