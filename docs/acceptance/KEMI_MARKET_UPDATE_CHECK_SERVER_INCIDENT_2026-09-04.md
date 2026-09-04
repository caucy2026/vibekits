# KEMI 应用市场更新检查接口生产故障单

> 日期：2026-09-04  
> 环境：KEMI 生产环境  
> 服务：`https://kemi.newlinksz.com/kd-api`  
> 影响接口：`GET /api/store/update/check`  
> 当前状态：稳定复现，阻断 Windows/macOS 应用自更新与新版本发布闭环

## 1. 故障摘要

KEMI 应用市场的公开更新检查接口能正常建立 HTTPS 连接并返回 HTTP 200，但业务响应为 400，
服务端错误信息为：

```text
Unknown column 'a.names' in 'field list'
```

该错误同时影响 `macos` 和 `windows`。客户端请求已经成功到达服务端，故障发生在服务端执行
更新查询时。当前线上 VibeKits dev.155 无法通过该接口发现已准备好的 dev.156，因此发布流程
不能完成“旧版发现新版”和“当前版不循环更新”两项验收。

## 2. 官方接口合同

依据 KEMI 官方 Windows/macOS 自更新文档，请求格式为：

```http
GET https://kemi.newlinksz.com/kd-api/api/store/update/check
    ?package_name={package_name}
    &version_code={integer_version_code}
    &os={windows|macos}
```

官方文档同时声明兼容：

- `packageName` 替代 `package_name`；
- `versionCode` 替代 `version_code`；
- `os_type` 替代 `os`。

成功响应必须同时满足：HTTP 为 2xx、JSON `status == 200`、`data` 为对象且
`data.has_update` 为 boolean。

## 3. 最小复现

以下请求均为公开只读接口，不需要登录或 Token。

### 3.1 官方蛇形参数

```bash
curl -sS \
  'https://kemi.newlinksz.com/kd-api/api/store/update/check?package_name=com.caucy.vibekits&version_code=2155&os=macos'
```

### 3.2 官方兼容驼峰参数

```bash
curl -sS \
  'https://kemi.newlinksz.com/kd-api/api/store/update/check?packageName=com.caucy.vibekits&versionCode=2155&os=macos'
```

### 3.3 `os_type` 兼容参数

```bash
curl -sS \
  'https://kemi.newlinksz.com/kd-api/api/store/update/check?package_name=com.caucy.vibekits&version_code=2155&os_type=macos'
```

### 3.4 不存在包名对照组

```bash
curl -sS \
  'https://kemi.newlinksz.com/kd-api/api/store/update/check?package_name=com.caucy.vibekits.nonexistent&version_code=1&os=macos'
```

将上述 `os` 改为 `windows` 同样可以复现。

## 4. 实际结果

四组请求以及 Windows/macOS 两个平台均返回 HTTP 200，响应体一致：

```json
{
  "status": 400,
  "msg": "Unknown column 'a.names' in 'field list'",
  "data": null
}
```

## 5. 期望结果

目标应用存在且远端版本更高时：

```json
{
  "status": 200,
  "msg": "success",
  "data": {
    "has_update": true,
    "package_name": "com.caucy.vibekits",
    "os_type": "macos",
    "version_code": 2156
  }
}
```

不存在应用或远端版本不高于客户端版本时：

```json
{
  "status": 200,
  "msg": "success",
  "data": {
    "has_update": false,
    "package_name": "com.caucy.vibekits.nonexistent",
    "os_type": "macos",
    "local_version_code": 1
  }
}
```

实际完整响应还应按官方合同返回 URL、精确大小、SHA-256、版本名称、更新说明和强制更新状态。

## 6. 已排除事项

1. **不是参数命名错误**：蛇形、驼峰和 `os_type` 三种官方形式结果一致。
2. **不是 VibeKits 包名错误**：不存在包名在进入包名筛选前也返回同一 SQL 错误。
3. **不是平台参数错误**：`windows` 与 `macos` 均稳定复现。
4. **不是网络或 TLS 错误**：服务器正常返回 HTTP 200 和结构化 JSON。
5. **不是整个商城数据库不可用**：以下公开详情接口仍能正常返回线上 dev.155：
   - macOS：`GET /api/store/apps/53?os=macos`
   - Windows：`GET /api/store/apps/54?os=windows`
6. **不是客户端 JSON 解析错误**：服务端业务状态明确为 400，且 `data` 为 `null`。

## 7. 服务端根因判断

错误文本表明更新检查路由生成的 SQL 在查询别名 `a` 时读取了不存在的 `names` 列。高概率原因：

1. `/api/store/update/check` 的 SQL/ORM projection 已升级，但生产数据库 migration 未部署；或
2. `names` 实际来自翻译表、JSON 聚合或应用详情 DTO，却被错误写成 `a.names`；或
3. 列已更名/拆表，但更新检查路由仍使用旧 schema。

由于应用列表和详情接口能正常返回 `names` 对象，建议更新检查路由复用列表/详情当前有效的
多语言名称映射，而不是直接假设 `apps a` 存在 `names` 列。

## 8. 建议修复步骤

1. 检查生产数据库 `apps` 表实际字段和已执行 migration 版本。
2. 定位 `/api/store/update/check` 对应 SQL、ORM select 或 DTO projection 中的 `a.names`。
3. 与 `/api/store/apps/{app_id}` 当前正常使用的名称查询实现对照。
4. 若 schema 设计确实要求 `names` 列，补部署缺失 migration，并验证已有数据回填。
5. 若 `names` 来自关联表或聚合字段，修正查询并保留缺少翻译时回退到 `app_name` 的行为。
6. 服务端异常响应不得向普通客户端暴露 SQL、表名或列名；记录内部 trace ID，对外返回稳定错误码。
7. 在预发布环境完成下述矩阵后再部署生产。

## 9. 修复验收矩阵

| 用例 | 请求条件 | 必须结果 |
|---|---|---|
| macOS 正向更新 | 线上 2156，本地 2155，`os=macos` | `status=200`、`has_update=true`、版本/URL/大小/SHA 正确 |
| macOS 反向检查 | 线上 2156，本地 2156，`os=macos` | `status=200`、`has_update=false` |
| Windows 正向更新 | 线上 2156，本地 2155，`os=windows` | `status=200`、`has_update=true`，且不返回 macOS 包 |
| Windows 反向检查 | 线上 2156，本地 2156，`os=windows` | `status=200`、`has_update=false` |
| 不存在包名 | 不存在的 package name | `status=200`、`has_update=false` |
| 驼峰兼容 | `packageName/versionCode` | 与蛇形参数语义一致 |
| `os_type` 兼容 | 使用 `os_type` | 与 `os` 语义一致 |
| 跨平台隔离 | 同包名分别查询 Windows/macOS | app_id、URL、大小和 SHA 不串平台 |
| 缺少平台 | 非 Android 桌面请求缺少 `os` | 按官方合同返回明确参数错误，不泄露 SQL |
| 数据异常 | 缺少翻译记录 | 回退名称或稳定业务错误，不出现数据库字段信息 |

## 10. 发布恢复条件

服务端修复后，发布方还必须完成：

1. 更新 KEMI 商场中既有 macOS app_id `53` 和 Windows app_id `54`，不得创建重复记录；
2. 上传完成返回的 URL、字节数和 SHA-256 与本地包完全一致；
3. 公开详情返回版本 2156、HTTPS URL、精确大小和正确 SHA-256；
4. 从 CDN 完整下载并复算 SHA-256；
5. 旧版 2155 返回 `has_update=true`；
6. 当前版 2156 返回 `has_update=false`；
7. 客户端真实完成检查、下载、校验和安装/打开流程。

在上述项目全部通过之前，不应将“文件已上传”描述为“正式发布完成”。
