# Vibekits 1.9.0-dev.239 macOS KEMI 商场发布验收

- 日期：2026-09-24；目标：KEMI 商场既有 macOS 应用 `53`，`com.caucy.vibekits`。
- 源码修复提交：`1d0a2aa`（远端 Harness 发送和历史）、`f4e7093`（完成状态和等待回执）。候选从 dev236 的隔离源码构建，只叠加这些修复；未把同时进行的其他主线改动并入此包。
- 版本：`1.9.0-dev.239`，VersionCode/构建号 `2239`，通用架构 `x86_64 arm64`。
- 最终 post-staple ZIP：`/Volumes/ORICO/kemi-build-cache/app-release-gate/vibekits/macos/harness-dispatch-20260924/candidate-239/Vibekits-1.9.0-dev.239+2239-macos-universal-notarized-clean.zip`。
- 精确大小：`421091118` 字节；SHA-256：`ef892c6b05e9ff057c4c1ea23935e7cd2c439a288c089bd0484dc21197f10acd`。
- 签名：Developer ID Application: zhen ji (`26T5WV4GLP`)；251 个 Mach-O 已验证。Apple 公证 `1ed9aa66-ad4b-4f8f-a9b8-ad55edd059f3`：Accepted。最终 ZIP 经发布技能 `verify_macos_release.sh` 解压验证，staple、Gatekeeper、双架构均 PASS。
- 既有线上版本为 dev236/2236；仅更新 app 53，保留分类“工作”、商城展示及非强制更新。开发者控制台返回“已直接更新线上版本（免审）”。
- CDN：`https://cdn.newlink-sz.com/kemiAppStore/macpkg/2026/09/1790250083149_fc0b31e9_Vibekits-1_9_0-dev_239_2239-macos-univer.zip`。HEAD 为 HTTP 200、Content-Length `421091118`。完整下载后的字节数与 SHA-256 和本地最终包完全一致；下载包再次通过发布脚本验证。
- 公开详情、无分类参数的 macOS“全部”列表均显示 app 53、dev239/2239、精确十进制大小和 SHA-256。`version_code=2236&os=macos` 返回 `has_update=true`、目标 2239；`version_code=2239&os=macos` 返回 `has_update=false`。
- 测试机 `4456560334` 从 CDN 直接下载同一 ZIP，核对大小与 SHA-256 后解压并安装。当前 `/Users/mac/tools/Vibekits.app` 为 2239，PID 7784；严格签名验证通过，Gatekeeper 为 `Notarized Developer ID`。dev238 回滚包仍在 `/Users/mac/tools/Vibekits-2238-rollback-20260924.app`。
- 从商城包安装后，远端 Harness `session_prompt` 接受只读请求 `harness-market-239-4456560334-01`；官方历史 seq 684 为对应 `user/message`，seq 697 为 `turn/end completed`；`session_wait` 返回 `changed=true, state=completed`。安装前版本的状态、历史、超时回执也已实测通过。
- 限制：`AppUpdateService` 在当前产品源码中按既有产品策略保持空实现，应用不会自行弹出自更新。应用中心源码有下载与安装入口，但此次远端辅助功能控件检查不稳定，未实测应用内按钮点击；已验证商场公开接口、CDN 实际下载和目标 Mac 安装启动。目标 Mac 未安装 Xcode 命令行工具，远端无法运行 `stapler validate`；本地对相同哈希的 CDN 包已通过该检查，远端 Gatekeeper 已放行。
