# VibeKits 1.9.0-dev.156 自更新入口纠正与发布验收

## 1. 纠正目标

- “关于我们”只展示产品、版本、版权和品牌内容，不承载检查更新。
- “应用中心”只浏览、下载和安装当前平台的其他应用，不承载 VibeKits 自更新。
- Windows 与 macOS 共用后台更新状态机。只有服务端严格确认存在更高版本时，才显示独立的全局更新提示；当前版本、无更新、网络失败和服务端失败均不占用产品页面。
- 失败信息只进入脱敏诊断日志，不向用户暴露 `FormatException`、SQL、表名、字段名或响应正文。

## 2. 根因与服务端边界

2026-09-04 真实请求：

`GET /kd-api/api/store/update/check?package_name=com.caucy.vibekits&version_code=2155&os=windows`

服务端返回 HTTP 200，但 JSON 业务状态为 400，消息是 `Unknown column 'a.names' in 'field list'`。该问题属于 KEMI 市场服务端数据库/查询契约故障。旧客户端把非成功业务状态转成 `FormatException` 并直接显示在“关于我们”，因此 macOS 与 Windows 同时出现“更新服务响应格式不兼容”。

2026-09-04 再次按线上文档交叉验证：蛇形参数、驼峰参数、`windows`、`macos` 以及不存在的探测包名，全部在进入包名/版本判断前返回同一个 `a.names` 错误；与此同时 `/api/store/apps` 与 `/api/store/apps/{app_id}` 正常返回，其中 `names` 可由正常应用查询结构生成。由此可以排除 VibeKits 包名、版本号和 `os` 参数错误，并把故障收敛到服务端 `store/update/check` 路由的 SQL 投影：代码读取了生产 `apps` 别名 `a` 上不存在的 `names` 列，或者对应数据库 migration 未部署。服务端应复用正常详情/列表的名称映射，或部署与代码匹配的 schema；客户端不得通过改参数或忽略业务状态绕过。

dev.156 已修正客户端故障隔离和展示边界，但不能伪造生产更新成功；服务端恢复前，真实生产正向升级仍须标记为外部阻塞。

## 3. 实现结果

- 删除“关于我们”的更新卡片、检查按钮和错误文字。
- “应用中心”没有 VibeKits 自更新卡片或检查入口。
- 后台失败仅记录诊断；面向用户的兜底文本不包含底层异常。
- 发现更高版本时，在应用根级显示一次全局更新对话框，支持“稍后”和“下载并安装”；强制更新仍由根级阻断层处理。
- 版本统一为 `1.9.0-dev.156+2156`，LMCP `appVersion` 与 `catalogRevision=2156` 同步。

## 4. 自动化验证

- 定向更新/About/应用中心回归：28/28 通过。
- 完整 Flutter 测试：668 通过，16 项按环境门禁跳过，0 失败。
- `flutter analyze --no-pub`：0 issue。
- 官方 Harness Koffi 版本与 Universal 原生模块精确对齐；修复后 Harness Agent 集成测试通过。
- macOS Release 兼容门禁通过：Universal `arm64+x86_64`、macOS 12+、Harness、ADB、7-Zip、Git 均在 App 内验证。

## 5. macOS 候选证据

- App：`build/macos/Build/Products/Release/Vibekits.app`
- ZIP：`build/macos/Build/Products/Release/Vibekits-1.9.0-dev.156+2156-macos-universal-notarized-v2.zip`
- ZIP 大小：263,110,746 bytes
- ZIP SHA-256：`3fe972feefc54db0b100cd46727e3c2a25b3614fc085a5a27cbcc0709a33ef3b`
- Developer ID：`Developer ID Application: zhen ji (26T5WV4GLP)`
- Apple 公证：Accepted，Submission ID `2804bc87-485e-468a-a1b0-c45de0b149b8`
- staple/validate：通过
- Gatekeeper：`accepted`，`source=Notarized Developer ID`
- 主程序架构：`x86_64 arm64`；`LSMinimumSystemVersion=12.0`
- 最终 ZIP 解压后的 App 再次通过 `codesign --verify --deep --strict`、staple validate 与 Gatekeeper；首次并行调用代码签名服务曾瞬时返回 internal error，串行重试后所有校验通过，不能把该瞬时结果误判为包损坏。
- 真实 About 页面检查：版本显示 dev.156，页面中不存在检查更新卡片。

该文件仍是发布候选，Windows 门禁完成前不得复制到 `bin`、不得更新市场。

## 6. Windows 门禁状态

- GitHub Windows Release run `33853280232` 全绿，产物版本为 `1.9.0-dev.156+2156`。
- CI 外层产物：`Vibekits-1.9.0-dev.156+2156-windows-x64-ci.zip`，275,041,480 bytes，SHA-256 `ae712d09ad065fc590ea3808e6c782df0e88499c4bcae6c51436cf265641cd47`。
- 真机 `192.168.3.58` 已在 `D:\KEMI-Test` 下载并核对外层产物；解出的正式内层 ZIP 为 283,270,754 bytes，SHA-256 `6aef285928d4d2dbb3029afec20260257334dbc03bec50b85136f4f7d31875ca`，与包内摘要一致。
- 隔离目录三次启动均在 5 秒检查点保持运行，工作集约 93–95 MB；Harness、ADB、Git、7-Zip、Mihomo、QEMU 运行时均随包存在，不依赖开发工具链。
- 真机 `Get-AuthenticodeSignature` 结果仍为 `NotSigned`。这不影响已完成的“能运行”验证，但不满足第 59 号规范的 Windows 正式发布签名门禁，因此不能把该包标为已完成正式发布。

## 7. 发布判定

当前判定：**macOS 正式包通过；Windows 可运行但未签名；双平台市场记录仍保持 dev.155，正式发布暂缓**。

2026-09-04 发布前再次请求生产接口，macOS 与 Windows 均仍返回业务状态 400 和同一 `a.names` SQL/schema 错误。依照第 59 号规范，即使包上传成功也不能完成旧版正向发现与当前版反向无更新验证，因此本次没有执行上传或覆盖线上记录。

正式发布必须同时满足：

1. 最新 macOS 与 Windows GitHub Release 工作流完成且全绿；
2. Windows 真机 D 盘增量 Release、安装、About/应用中心 UI、冷暖启动性能通过；
3. 服务端更新接口恢复后，完成旧版本到 dev.156 的正向升级和当前版本无更新反向验证；
4. 最终 Windows 与 macOS 包校验后，按 manifest-last 顺序更新 KEMI 市场。
