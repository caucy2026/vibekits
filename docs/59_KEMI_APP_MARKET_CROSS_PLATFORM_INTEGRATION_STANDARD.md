# KEMI 应用商城跨平台接入、安装、自更新与发布标准

> 文档状态：强制执行基线
>
> 适用平台：Android、Windows、macOS（Linux/iOS 可按同一模型扩展）
>
> 适用对象：需要接入 KEMI 应用中心、自更新或发布到 KEMI 市场的所有 APP 研发、测试与发布人员
>
> 最后核对：2026-09-04（已对照线上 Windows/macOS 自升级文档，并复核生产接口故障）
> 线上规范优先级：若本文与线上文档冲突，立即停止发布，以线上规范为准更新本文后再继续。

## 1. 目标和完成定义

接入完成不是“页面能显示应用”，也不是“安装包上传成功”。每个平台必须同时完成：

1. 客户端只展示当前操作系统的应用；
2. 用户可以查看详情、下载、校验并启动该平台的安装流程；
3. 本 APP 能用固定包名和当前整数版本码检查自身更新；
4. 下载文件必须通过 HTTPS、平台格式、精确字节数和 SHA-256 校验；
5. 安装包通过平台签名门禁，macOS 还必须完成 Apple 公证和票据装订；
6. 发布端按 `(package_name, os_type)` 更新既有记录，禁止重复创建；
7. 旧版本能发现新版本，当前版本不循环提示；
8. 从公开商城接口重新读取并从 CDN 下载后的结果与本地产物完全一致；
9. 在目标真机完成安装、首次启动、升级和取消路径测试，并保存证据。

官方入口：

- 总文档：<https://kemi.newlinksz.com/kd/docs/>
- AI 发布：<https://kemi.newlinksz.com/kd/docs/ai-publish>
- 安装包上传：<https://kemi.newlinksz.com/kd/docs/app-upload>
- 商城公开 API：<https://kemi.newlinksz.com/kd/docs/store-api>
- 自更新：<https://kemi.newlinksz.com/kd/docs/app-self-update>
- Windows 自更新：<https://kemi.newlinksz.com/kd/docs/app-self-update/windows>
- macOS 自更新：<https://kemi.newlinksz.com/kd/docs/app-self-update/macos>

## 2. 三条链路必须隔离

| 链路 | 使用者 | 鉴权 | 允许行为 |
|---|---|---|---|
| 商城浏览 | 普通客户端 | 公开读取，无发布 token | 分类、搜索、列表、详情、下载安装 |
| 本 APP 自更新 | 普通客户端 | 公开读取，无发布 token | 按包名、平台和版本码检查更新、下载校验、启动安装 |
| 管理员发布 | 受控 CI 或发布工作站 | UserCenter 登录后的短期 Bearer token | 查重、上传、创建/更新商城记录、上下架 |

客户端包内严禁包含管理员账号、密码、Bearer token、上传 token、Apple 私钥或 Windows 签名私钥。普通客户端绝不能调用创建、更新、上下架或上传接口。

## 3. 固定地址和平台标识

```text
UserCenter API: https://kemi.newlinksz.com/usercenter
开发者平台 API: https://kemi.newlinksz.com/kd-api
应用商城 API:   https://kemi.newlinksz.com/kd-api/api/store
```

平台值必须使用小写固定枚举：

| 运行环境 | `os` / `os_type` | 商城可直接安装格式 |
|---|---|---|
| Android | `android` | `.apk` |
| Windows | `windows` | `.exe`、`.msi`、明确标注为 Windows 的 `.zip` |
| macOS | `macos` | `.dmg`、`.pkg`、明确标注为 macOS 的 `.zip` |
| Linux（扩展） | `linux` | `.AppImage`、`.deb`、`.rpm` |
| iOS（扩展） | `ios` | 受签名和分发策略约束的 `.ipa` |

`.zip` 不能由扩展名推断平台，必须以商城记录的 `os_type` 为准。Android 的 `.aab` 是商店分发产物，不得作为客户端直接安装包。

Flutter 平台映射示例：

```dart
String currentStoreOs() {
  if (Platform.isWindows) return 'windows';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isAndroid) return 'android';
  if (Platform.isLinux) return 'linux';
  if (Platform.isIOS) return 'ios';
  throw UnsupportedError('当前系统尚未接入 KEMI 应用商城');
}
```

## 4. 商城浏览接入

### 4.1 接口

```http
GET https://kemi.newlinksz.com/kd-api/api/store/categories

GET https://kemi.newlinksz.com/kd-api/api/store/apps
    ?category={URL编码后的分类}
    &keyword={URL编码后的关键词}
    &page=1
    &pageSize=30
    &os={android|windows|macos}

GET https://kemi.newlinksz.com/kd-api/api/store/apps/{app_id}?os={os}
```

Windows 和 macOS 请求必须传 `os=windows` 或 `os=macos`。省略 `os` 可能进入 Android 默认分支，属于严重平台串包错误。

### 4.2 响应解析

客户端至少归一化以下字段：

```json
{
  "app_id": 53,
  "app_name": "Vibekits",
  "package_name": "com.caucy.vibekits",
  "os_type": "macos",
  "platforms": ["macos"],
  "version_name": "1.9.0-dev.154",
  "version_code": 2154,
  "category": "开发工具",
  "short_desc": "应用简介",
  "long_desc": "应用详细说明",
  "icon": "https://.../icon.png",
  "screenshots": [],
  "download_url": "https://.../package.zip",
  "apk_sha256": "64位小写十六进制",
  "file_size": "123456",
  "file_size_bytes": 123456,
  "rating": 5,
  "download_count": 0
}
```

兼容原则：

- 未知新增字段忽略，不能因此崩溃；
- 数字字段可兼容 JSON 数字和十进制字符串；
- SHA 可兼容 `apk_sha256` 或新别名 `sha256`，归一化为小写；
- `os_type` 缺失时，只能在 `platforms` 明确包含当前平台时展示；
- `os_type` 与 `platforms` 冲突、两者均缺失或不包含当前平台时，必须排除；
- 只展示服务端已公开且可见的记录，客户端不得自行展示草稿或下架项；
- `status != 200`、`data` 类型错误或关键字段缺失时显示可重试错误，不使用陈旧结果伪装成功。

### 4.3 应用中心界面

应用中心至少包含：当前平台标识、分类、关键词搜索、刷新、加载态、空状态、错误与重试、应用卡片、详情页、版本、大小、评分、下载进度和校验结果。

- Windows 只显示 Windows 应用；macOS 只显示 macOS 应用；Android 只显示 Android 应用。
- 图标失败使用本地占位图，不阻断列表。
- 校验元数据不完整的应用可以查看，但“安装”必须禁用并解释缺少的字段。
- 下载和安装必须由用户明确触发；不得在浏览列表时后台下载大文件。
- 官方插件市场和 KEMI 应用中心是两个独立功能，不能互相替换数据源或入口。
- 应用中心只负责浏览和安装市场内其他应用，不承载“本 APP 检查更新”卡片，也不得显示本 APP 后台更新检查错误。

## 5. 本 APP 自更新

### 5.1 检查接口

```http
GET https://kemi.newlinksz.com/kd-api/api/store/update/check
    ?package_name={稳定包名}
    &version_code={当前整数版本码}
    &os={android|windows|macos}
```

包名在同一产品跨平台时可以相同，但查询必须同时带平台。版本比较只使用严格递增的整数 `version_code`；`version_name` 只用于用户展示。

更新检查必须同时满足 HTTP 与业务信封两层成功：

```text
HTTP status 为 2xx
JSON status == 200
data 是对象
data.has_update 是 boolean
```

HTTP 200 只表示服务器返回了 JSON，不代表更新查询成功。`status != 200` 时不得继续读取
`has_update`，也不得把失败伪装成“当前已是最新版本”。

### 5.2 检查策略

- 启动后异步检查，不能阻塞首页和离线使用；
- “关于我们”和“应用中心”均不放置本 APP 的更新卡片或手动检查入口；关于页只展示产品、版本、能力和隐私信息，应用中心只展示当前平台市场目录；
- 只有确认 `has_update=true` 且远端整数版本更高时，才显示独立的全局更新提示，由用户选择稍后或下载并安装；
- 后台检查失败必须静默记录诊断，不得把 `FormatException`、HTTP 响应、数据库字段、URL 或堆栈直接展示给普通用户；
- 网络失败采用有上限的退避，不连续弹窗；
- `has_update=false` 清除旧提示；
- 普通更新允许稍后处理；只有后台明确设置 `force_update` 且产品负责人批准时才阻断关键流程；
- 同一版本用户已忽略后，除非 `force_update` 改变或远端版本再次提升，否则不要重复打扰。

### 5.3 服务端契约故障诊断与 2026-09-04 生产事故

后台更新失败时，客户端先归一化为稳定错误码，再写有界脱敏日志：

| 稳定错误码 | 判定 | 自更新 UI |
|---|---|---|
| `update_http_error` | HTTP 非 2xx | 静默，不创建页面卡片 |
| `update_business_error` | HTTP 成功但 JSON `status != 200` | 静默，不把服务端 `msg` 展示给用户 |
| `update_invalid_envelope` | JSON/`data`/`has_update` 类型错误 | 静默，不伪装无更新 |
| `update_backend_schema_mismatch` | 脱敏诊断确认服务端 SQL/schema 不一致 | 静默并阻断发布闭环 |

2026-09-04 生产接口曾返回：

```json
{
  "status": 400,
  "msg": "Unknown column 'a.names' in 'field list'",
  "data": null
}
```

交叉验证使用了蛇形参数、驼峰参数、`windows`、`macos`、真实包名和不存在包名，结果均在业务筛选
前返回同一错误；同时应用列表与应用详情正常。因此根因不是客户端 `package_name`、
`version_code` 或 `os`，而是服务端 `/api/store/update/check` 路由的 SQL 投影与生产数据库 schema
不一致：查询读取了别名 `a` 上不存在的 `names` 列，或对应 migration 未部署。

服务端修复必须复用正常列表/详情的多语言名称映射，或部署与代码严格匹配的 schema。客户端不得
通过删除 `os`、改参数名、忽略业务状态或硬编码 `has_update=false` 绕过。修复后必须执行第 9.2
节的完整对照探测，才能恢复发布。

### 5.4 下载状态机

```text
idle → checking → available → downloading → verifying → readyToInstall
                  ↘ noUpdate         ↘ failed
                  ↘ cancelled
```

状态必须持久、可恢复且可解释。失败必须保留当前可运行版本；临时文件以 `.part` 写入，验证成功后再原子改名。取消、失败和退出时清理不完整文件。

### 5.5 强制安全校验顺序

1. URL 可解析且 scheme 为 HTTPS；
2. 平台字段与当前系统一致；
3. 扩展名在当前平台白名单；
4. `file_size_bytes` 或可解析的 `file_size` 大于 0；
5. SHA-256 为 64 位小写十六进制；
6. 流式下载，接收字节超过声明大小立即终止；
7. 最终精确字节数完全一致；
8. 流式计算 SHA-256 并完全一致；
9. 执行平台签名/身份校验；
10. 只有全部通过才显示“安装/打开安装包”。

HTTP 重定向的最终 URL 仍必须为 HTTPS。下载进程不要通过拼接 shell 字符串启动安装器，必须使用参数数组，避免路径注入。

## 6. 各平台安装实现

### 6.1 Android

构建与发布门禁：

- 使用正式 release keystore，禁止 debug 签名；
- `applicationId`、`versionCode`、`versionName` 与商城记录一致；
- 使用 `apksigner verify --verbose --print-certs app-release.apk` 验证；
- 记录 APK 精确字节数和 SHA-256；
- 在目标 Android 主版本和 ABI 真机上完成安装、升级、启动和回滚测试。

客户端安装：

- 下载只接受 `.apk`；
- 使用 `FileProvider` 的 `content://` URI，不暴露 `file://`；
- 发起系统 `ACTION_VIEW` 或 `ACTION_INSTALL_PACKAGE`，MIME 为 `application/vnd.android.package-archive`；
- Android 8+ 首次需要“允许安装未知应用”时，明确引导到本 APP 的系统授权页；
- 不绕过系统安装确认，不后台授予权限；
- 安装前可读取 APK 包名、版本码和签名证书，与期望值不一致则拒绝。

真机验收：首次安装、旧版覆盖升级、取消、拒绝未知来源权限、空间不足、损坏 APK、错误包名、错误签名和安装后首次启动。

### 6.2 Windows

构建与发布门禁：

- 交付 x64 或明确声明的架构；依赖和运行时必须自包含；
- `.exe`/`.msi` 必须使用组织正式 Authenticode 证书；
- PowerShell 执行 `Get-AuthenticodeSignature`，`Status` 必须为 `Valid`；
- 安装器中的产品名、Publisher、包名和版本与商城记录一致；
- 在干净 Windows 真机验证安装、卸载、升级和重启后启动。

客户端安装：

- `.msi` 使用 `msiexec /i <绝对路径>`；
- `.exe` 直接以参数数组启动；
- `.zip` 只能打开文件位置或进入经过设计的独立更新器，不能由主进程盲目覆盖自身；
- 需要管理员权限时交给系统 UAC，客户端不得伪造或静默绕过；
- 自替换使用独立、签名的 updater：等待主进程退出，备份旧版，替换后健康检查，失败自动回滚。

真机验收：标准用户、管理员用户、UAC 取消、文件占用、杀毒拦截、断网续传、哈希错误、签名错误、旧版到新版和安装失败回滚。

### 6.3 macOS

构建与发布门禁：

- 明确最低系统版本；若要求 Intel 与 Apple Silicon，共同产物必须为 Universal `x86_64 + arm64`；
- 所有嵌套 Mach-O、Framework、helper 和运行时先逐层签名，再签 App 外壳；
- 使用 `Developer ID Application` 和 Hardened Runtime；特殊 JIT/权限 entitlement 必须最小化并逐项审计；
- 公证返回 `Accepted` 后对 `.app` 执行 staple，并重新封装最终 ZIP/DMG；
- 最终交付包再次计算字节数和 SHA-256。

建议门禁命令：

```bash
lipo -archs '/absolute/path/App.app/Contents/MacOS/App'
codesign --verify --deep --strict --verbose=2 '/absolute/path/App.app'
codesign -dvv '/absolute/path/App.app'
ditto -c -k --sequesterRsrc --keepParent \
  '/absolute/path/App.app' '/absolute/path/notary.zip'
xcrun notarytool submit '/absolute/path/notary.zip' \
  --keychain-profile KEMI_NOTARY --wait --timeout 30m
xcrun stapler staple '/absolute/path/App.app'
xcrun stapler validate '/absolute/path/App.app'
spctl -a -vvv -t exec '/absolute/path/App.app'
ditto -c -k --sequesterRsrc --keepParent \
  '/absolute/path/App.app' '/absolute/path/final-notarized.zip'
shasum -a 256 '/absolute/path/final-notarized.zip'
```

客户端安装：

- ZIP/DMG/PKG 校验完成后使用系统 `open` 打开；
- ZIP 默认由用户将已签名 App 拖入 Applications；
- 静默覆盖必须另行设计、签名并审计 privileged helper，不得由普通主进程直接覆盖；
- Gatekeeper 不接受、签名 team/bundle id 不一致或公证票据无效时必须停止。

真机验收：Apple Silicon、Intel（或 Rosetta 不能替代真正 Intel 门禁时使用真机）、最低 macOS 版本、无网络票据验证、升级、用户取消、只读 Applications 和磁盘空间不足。

## 7. 发布到开发者平台

发布是生产写操作，必须获得负责人明确授权，并只在受控 CI/工作站执行。

### 7.1 发布清单

| 字段 | 要求 |
|---|---|
| `package_name` | 稳定且不可随版本变化 |
| `os_type` | 与安装包平台严格一致 |
| `app_name` | 用户可见正式名称 |
| `version_name` | 用户可读版本 |
| `version_code` | 同平台严格递增整数 |
| `category` | 来自后台分类 API |
| `download_url` | 上传完成接口返回的 HTTPS URL |
| `apk_sha256` | 最终交付包 64 位小写 SHA-256 |
| `file_size` | 精确字节数的十进制字符串 |
| `file_size_bytes` | 相同精确字节数的整数 |
| `icon` / `screenshots` | 正式 HTTPS 素材 |
| `short_desc` / `long_desc` | 只描述已完成并验收的能力 |
| `release_notes` | 当前版本真实变化 |
| `list_in_store` | 上架为 1 |
| `force_update` | 默认 0，非经批准不得开启 |

`file_size` 和 `file_size_bytes` 必须同时填写且数值一致，否则兼容客户端可能无法安装。

### 7.2 查重和更新规则

管理员接口先查询：

```http
GET https://kemi.newlinksz.com/kd-api/api/apps/list
    ?os_type={os}
    &keyword={package_name}
    &page=1
    &pageSize=20
Authorization: Bearer {短期TOKEN}
```

唯一键为 `(package_name, os_type)`：

- 0 条：允许创建；
- 1 条：记录 `app_id` 并更新；
- 多条：停止发布并先处理重复数据；
- 不允许通过改包名规避重复；
- Windows 与 macOS 可以共用包名，但必须分别有各自平台记录。

### 7.3 上传事务

桌面端标准流程：

1. `POST /api/upload/package-token`，提交分类、文件名和精确大小；
2. 使用返回的一次性上传地址和 token 直传 CDN；
3. `POST /api/upload/package-complete`；
4. 校验服务端返回 URL 为 HTTPS，大小和 SHA 与本地完全一致；
5. 已有记录调用 `POST /api/apps/update`，否则调用 `POST /api/apps/create`；
6. 重新读取管理员列表、公开详情和公开更新接口；
7. 从 CDN 完整下载并复算 SHA，目标真机安装。

Android 按线上文档使用 APK 专用上传凭证。接口字段可能演进，发布脚本应以线上文档为准，不能将一次性 token 或密码硬编码。

### 7.4 失败与回滚

- 上传失败：不得创建/更新商城记录；
- 元数据更新失败：保留旧线上版本，清理未引用上传对象由后台策略处理；
- 已上线版本异常：将记录回退到上一份仍可验证的签名产物，或按后台能力下架；
- 禁止覆盖 CDN 上的同名旧文件来“原地修复”；每个 `version_code` 对应不可变产物；
- 回滚后再次执行公开详情、更新正反向和真机安装验收。

## 8. 标准错误码和用户提示

| 错误码 | 含义 | UI 行为 |
|---|---|---|
| `unsupported_platform` | 当前系统未接入 | 禁用入口并说明支持范围 |
| `network_timeout` | 请求或下载超时 | 保留页面，允许重试 |
| `invalid_envelope` | API 响应结构错误 | 不展示陈旧成功状态 |
| `platform_mismatch` | 应用不属于当前平台 | 排除条目并记录脱敏日志 |
| `unsafe_url` | 非 HTTPS 或非法 URL | 禁止下载 |
| `unsupported_package` | 扩展名不在白名单 | 禁止安装 |
| `missing_size` | 没有有效精确大小 | 允许查看，禁止安装 |
| `invalid_sha256` | SHA 格式错误或缺失 | 允许查看，禁止安装 |
| `size_mismatch` | 下载字节数不一致 | 删除临时文件 |
| `sha256_mismatch` | 摘要不一致 | 删除临时文件并高亮风险 |
| `signature_invalid` | 平台签名/身份无效 | 禁止安装并建议重新下载 |
| `user_cancelled` | 用户取消下载、UAC 或安装 | 安静返回可重试状态 |
| `install_launch_failed` | 系统安装程序未启动 | 保留已验证文件并给出位置 |
| `update_business_error` | 更新接口业务状态失败 | 本 APP 自更新静默；只写有界脱敏诊断 |
| `update_backend_schema_mismatch` | 更新路由与数据库 schema 不一致 | 阻断发布；不得提示“已是最新版” |

日志不得包含密码、Bearer token、上传 token、Cookie、私钥或完整用户目录；URL 查询中若含临时签名也必须脱敏。

## 9. 测试矩阵

### 9.1 自动测试

每个客户端必须覆盖：

- 平台到 `os` 映射；
- 非 Android 请求始终带正确 `os`；
- 分类、关键词和分页正确 URL 编码；
- `os_type`、`platforms` 和冲突字段过滤；
- 字符串/数字形式大小兼容；
- 未知字段前向兼容；
- HTTPS、扩展名、大小、SHA 正反例；
- 下载超量立即停止、少量失败、哈希失败和临时文件清理；
- 旧版返回更新、当前版无更新、另一平台同包名不串包；
- 取消和重试；
- 安装进程使用参数数组而不是 shell 拼接。

### 9.2 生产只读联调

发布前后均执行：

1. 分类接口返回正常；
2. 当前平台列表只含当前平台；
3. 详情的版本、URL、两个大小字段和 SHA 完整；
4. 旧版本码检查得到 `has_update=true`；
5. 当前版本码检查得到 `has_update=false`；
6. CDN HEAD/完整下载成功，字节数和 SHA 一致。

更新接口异常时必须追加三路对照，不得反复修改客户端碰运气：

1. 用当前真实包名调用更新检查；
2. 用明确不存在的探测包名调用同一接口；
3. 读取同平台应用列表与目标 `app_id` 详情；
4. 若真实包名和不存在包名在业务筛选前返回相同 SQL/schema 错误，而列表/详情正常，则判定为
   更新路由服务端故障；保存 HTTP 状态、业务状态和脱敏错误类别，禁止保存 Token 或完整临时 URL；
5. 服务端修复后重新执行旧版本 `has_update=true`、当前版本 `has_update=false`、不存在包名
   `has_update=false` 以及另一平台不串包四项验证。

生产只读联调不得使用发布 token，也不得改变线上数据。

### 9.3 真机矩阵

| 场景 | Android | Windows | macOS |
|---|---:|---:|---:|
| 当前平台列表与搜索 | 必须 | 必须 | 必须 |
| 首次安装和启动 | 必须 | 必须 | 必须 |
| 旧版升级新版 | 必须 | 必须 | 必须 |
| 用户取消 | 必须 | 必须 | 必须 |
| 错误大小/SHA 拒绝 | 必须 | 必须 | 必须 |
| 平台签名验证 | APK signer | Authenticode | Developer ID + notarization |
| 权限拒绝 | 未知来源 | UAC | Applications/系统策略 |
| 架构门禁 | 支持 ABI | 声明架构 | arm64/x86_64 + 最低系统 |
| 失败保留旧版 | 必须 | 必须 | 必须 |

## 10. 发布后闭环验收

下列任一项失败，都不得宣称“已发布”或“可自动更新”：

1. 管理员列表中同 `(package_name, os_type)` 只有一条；
2. `status=1` 且 `list_in_store=1`；
3. 管理员记录、公开详情和更新接口的版本、URL、大小、SHA 完全一致；
4. CDN 完整下载后的字节数和 SHA 与本地最终包一致；
5. 旧版返回更新，当前版返回无更新；
6. 应用中心详情页安装按钮可用且不混入其他平台；
7. 真机安装、启动、升级、取消和失败回滚通过；
8. macOS 最终包是 staple 后重新封装的包，Gatekeeper 为 `Notarized Developer ID`；
9. Windows 签名有效且运行时自包含；
10. Android 包名、版本码和签名证书一致；
11. 发布临时目录、登录响应和短期 token 已清理；
12. 形成不含秘密的验收报告并关联 Git 提交和构建任务。

## 11. 交付给其他 APP 团队的最小资料包

每个接入团队必须提供：

```yaml
product:
  appName: "正式名称"
  packageName: "稳定包名"
  category: "后台合法分类"
platforms:
  - osType: windows
    versionName: "1.0.0"
    versionCode: 10000
    architecture: "x64"
    packageFormat: ".exe"
  - osType: macos
    versionName: "1.0.0"
    versionCode: 10000
    architecture: "universal-x86_64-arm64"
    minimumOs: "12.0"
    packageFormat: ".zip"
  - osType: android
    versionName: "1.0.0"
    versionCode: 10000
    architecture: "arm64-v8a"
    packageFormat: ".apk"
update:
  checkOnStartup: true
  manualCheckEntry: null
  presentation: "global-prompt-only-when-update-available"
  backgroundFailure: "silent"
  forceUpdate: false
security:
  requireHttps: true
  requireExactSize: true
  requireSha256: true
  requirePlatformSignature: true
```

同时提交每个平台的最终包绝对路径或 CI artifact、精确字节数、SHA-256、签名输出、真机截图、旧版升级结果和回滚结果。不能只交一张“上传成功”截图。

## 12. 发布报告模板

```markdown
# <产品> <版本> KEMI 市场发布报告

- 时间 / 发布人：
- Git commit / CI run：
- package_name / os_type / app_id：
- 新建或更新：
- version_name / version_code：
- 正式包和架构：
- 精确字节数：
- SHA-256：
- 平台签名：PASS/FAIL（附摘要）
- macOS 公证 ID / Accepted / staple / Gatekeeper：
- 上传完成返回的 URL、大小、SHA 一致：PASS/FAIL
- 管理员记录唯一且可见：PASS/FAIL
- 公开详情：PASS/FAIL
- CDN 完整下载复核：PASS/FAIL
- 旧版 has_update=true：PASS/FAIL
- 当前版 has_update=false：PASS/FAIL
- 当前平台应用中心展示且无串包：PASS/FAIL
- 真机首次安装 / 启动 / 升级 / 取消 / 回滚：PASS/FAIL
- 临时凭据已清理：PASS/FAIL
- 已知限制：
```

## 13. 禁止事项

- 禁止把管理员账号、密码或 token 编译进 APP；
- 禁止未签名、未公证、调试包或测试包上架；
- 禁止省略桌面端 `os`；
- 禁止仅凭扩展名判断 ZIP 平台；
- 禁止只校验 HTTP 200 就启动安装；
- 禁止把 HTTP 200 内的业务 `status != 200` 当作无更新或成功；
- 禁止在关于页、应用中心或全局弹窗展示服务端 SQL、字段名、响应正文与 `FormatException`；
- 禁止缺少大小或 SHA 时继续安装；
- 禁止使用 shell 字符串拼接用户可控路径；
- 禁止同一 `(package_name, os_type)` 创建重复记录；
- 禁止覆盖旧 CDN 文件或复用旧 `version_code` 发布不同二进制；
- 禁止以 CI 编译成功替代目标真机安装；
- 禁止以后台记录正确替代公开 API、CDN 和客户端闭环；
- 禁止声称支持尚未真机验收的平台、架构或最低系统版本。

## 14. VibeKits 可参考实现

其他 Flutter APP 可参考但不可直接复制产品身份：

- 商城模型、平台过滤、安全下载和安装入口：`lib/features/app_center/domain/app_center_service.dart`
- 应用中心页面：`lib/features/app_center/presentation/app_center_tab.dart`
- 自更新检查、下载与校验：`lib/app/app_update_service.dart`
- 商城合同测试：`test/app_center_test.dart`
- 自更新合同测试：`test/app_update_service_test.dart`

复制实现后必须替换包名、版本读取、产品文案和平台安装策略，并重新执行本文全部门禁。VibeKits 的包名、版本或商城 `app_id` 不能成为其他产品的默认值。
