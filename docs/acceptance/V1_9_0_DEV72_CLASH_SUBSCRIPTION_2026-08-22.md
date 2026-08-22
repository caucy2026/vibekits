# v1.9.0-dev.72 Clash 订阅修复验收

## 实机问题

用户确认同一订阅地址在 Clash Verge 可用，但 Vibekits 添加失败。检查 Release 数据目录发现没有生成订阅配置或失败日志，说明失败位于下载/校验/凭据阶段且旧版不可诊断。

## 根因与修复

1. 订阅 URL 被错误限制为 240 字符，Windows 凭据写入又被错误限制为 512 B；现分别调整为 1200 字符和 Windows 支持的 2560 B。
2. Dart 下载默认直连，未使用已经启用的 Windows 系统代理；现在优先走系统代理，失败后回退直连。
3. 请求缺少 Clash 客户端 User-Agent，部分服务会返回不同格式或拒绝；现在使用 Clash Verge 客户端标识。
4. 旧校验要求订阅自带代理端口，但常见 Clash 订阅只返回代理列表；现在接受标准 YAML，并在运行副本补齐本地安全配置。
5. 新增脱敏订阅日志，错误可定位到 download/direct/credential 阶段，禁止写入查询 token。

## 自动验收

- 超过 240 字符的 loopback 订阅下载、更新和删除：PASS。
- 无 `mixed-port` 的代理列表生成可运行配置：PASS。
- 请求携带 Clash Verge User-Agent：PASS。
- 600 字符凭据在 Windows Credential Manager 写入、读取、删除：PASS。
- 日志包含成功/失败阶段且不包含订阅 token：PASS。
- 相关静态分析：0 issue。
- Windows Release 文件/产品版本：`1.9.0-dev.72+82`。
- Release EXE SHA-256：`A2A04A1A0F53A3CA230F87DBF2B2A79A8E7E3346725105D621ACE09185FDEA6A`。
