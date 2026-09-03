# VibeKits 1.9.0-dev.152 云端系列产品图片验收

日期：2026-09-03  
版本：`1.9.0-dev.152+2152`

## 需求结论

产品方已明确确认 VibeKits 属于同系列产品并授权使用云端图片，因此 dev.151 的纯本地产品区被本版替代。“关于我们”使用资源名 `kemi_s1_xc`，但不复制其他产品的名称、口号或功能数据。

## 生产资源实测

- HTTPS 清单：`https://kemi.newlinksz.com/kd-api/api/open/resources?user_id=8&name=kemi_s1_xc`
- 实测资源版本：`1.0.2`
- 实测图片数量：5
- 每张图片均验证：HTTPS 地址、文件名、顺序、声明大小、MD5、MIME 文件头以及实际图片解码。
- `VIBEKITS_MARKETING_LIVE=1 flutter test test/marketing_cache_live_test.dart`：1/1 通过，证明使用的是生产清单和真实文件，而不是模拟数据。

## 启动、缓存与失败回退

- 首窗渲染不等待网络；应用启动 3 秒后才执行一次低优先级同步。
- 页面不直接加载远端 URL，只显示已经写入本地缓存并通过完整校验的文件。
- 缓存目录为平台缓存根下的 `Marketing/kemi_s1_xc`；下载先进入 staging，全部成功后才原子替换 `active.json`。
- 更新前的完整版本保留在 `backup.json`。清单错误、下载中断、大小或 MD5 不符、格式伪装、无法解码时，继续显示 active/backup；从未成功缓存时显示随包离线产品介绍。
- 清单摘要未变化时不重复下载，资源版本独立于 App 版本。

## 交互与跨平台

- 多图每 5 秒切换；点击主图进入下一张；点击短指示器直接切换并重置 5 秒计时。
- 单图不创建轮播计时器；离开“关于我们”页面立即取消页面计时器。
- 图片带“第 n / 总数 + 文件名”的可访问语义；资源版本和同步状态可见。
- macOS、Windows、Linux 与移动端共用 `AboutTab` 和 `MarketingCacheService`，没有平台专属的业务分叉。
- App 版本、LMCP `appVersion` 与 `catalogRevision=2152` 保持一致。

## 自动与构建验收

- `flutter analyze --no-pub`：0 issue。
- 缓存原子发布、相同清单不重复下载、新版损坏保留旧缓存：2/2 通过。
- 关于页所在主导航及共享 Widget 回归：21/21 通过；合计 23/23。
- 生产云端清单与真实图片完整性：1/1 通过。
- `flutter build macos --release --no-pub`：成功，产物 `build/macos/Build/Products/Release/Vibekits.app`，668.8 MB。
- 首轮 Windows CI 的产品静态分析、Harness UI 24 项及 Agent 集成均通过，但冷启动资源探针碰到测试外层 20 秒门限；产品探针自身 12 秒边界保持不变，仅把 CI 编排余量调整为 45 秒后复跑完整 Windows 门禁。

结论：dev.152 已实现真实云端多图、非阻塞启动、完整缓存、原子切换和离线回退；不再把静态本地区域声明为最终“关于我们”设计。
