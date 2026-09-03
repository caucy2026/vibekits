# VibeKits dev.153 KEMI 市场与自升级验收

版本：`1.9.0-dev.153+2153`

## 发布合同

- 逻辑包名固定为 `com.caucy.vibekits`。
- 更新检查使用 `https://kemi.newlinksz.com/kd-api/api/store/update/check`。
- Windows 请求必须带 `os=windows`，macOS 请求必须带 `os=macos`；版本只比较整数 `version_code=2153`。
- 只有 `status=200`、`has_update=true` 且远端整数版本更高时才显示更新。
- 下载地址必须是 HTTPS；Windows 只接受 `.exe/.msi/.zip`，macOS 只接受 `.dmg/.pkg/.zip`。
- 下载后必须同时核对服务端声明的精确字节数与 64 位 SHA-256；任一缺失或不一致即删除临时文件，禁止安装。
- macOS 由系统打开已校验的安装包；Windows 的 MSI 交给 `msiexec`、EXE 直接启动、ZIP 交给资源管理器。客户端不使用商城 DeepLink。
- 应用启动后后台检查一次，“关于我们”保留状态、发布说明、手动检查及“下载并安装”入口。

## 已执行自动门禁

- `flutter analyze --no-pub`：0 问题。
- `flutter test --no-pub test/app_update_service_test.dart test/widget_test.dart`：23/23。
- 协议测试确认 `package_name/version_code/os` 完整并拒绝 HTTP 安装包。
- macOS Release 构建：通过，App 669.9 MB。
- `verify_macos_release_compat.sh`：App、Harness、ADB、7-Zip、Git 均满足 Universal 与 macOS 12+ 门禁。

## 上架前剩余硬门禁

1. 当前源码提交可追溯，Windows Actions Release 构建及产物下载成功。
2. macOS Developer ID、Hardened Runtime、时间戳、Apple 公证 Accepted、staple、Gatekeeper 全部通过。
3. 登录 KEMI 开发者后台，读取管理员发布规范，核对或创建 macOS/Windows 两条同包名、不同 `os_type` 的应用记录。
4. 上传最终产物后记录市场返回的下载 URL、字节数和 SHA-256，并从公开更新接口以旧版本号真实查询两平台。
5. 最终发布/覆盖线上记录属于外部状态修改，执行前展示精确版本、文件和 SHA-256 并取得确认。
