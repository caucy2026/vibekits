# v1.9.0-dev.73 Clash 标准 Profile 启动验收

## 真实故障证据

- 订阅下载：成功，31,057 字节。
- Profile 结构：32 个 `proxies` 列表项，使用行内 YAML 映射。
- dev.72 显示：0 节点，属于解析错误。
- 内置 Mihomo 首次校验：因缺少 GeoData 尝试在线下载，DNS 失败。
- 补齐 GeoData 后对同一 Profile 校验：38 ms，`test is successful`。

## 标准链路

1. 订阅作为 Profile 保存，不把 UI 状态当作运行成功。
2. 生成独立运行副本并补齐本地端口、回环控制器等 App 层配置。
3. 从 Release 私有运行包准备 `Country.mmdb`、`geoip.dat`、`geosite.dat`。
4. 使用同一个内置 Mihomo 执行 `-t` 预校验。
5. 预校验成功后才启动进程、连接 REST 控制器并切换系统代理。
6. 任何阶段失败都保留脱敏日志并恢复原网络。

## 失败判定

- 节点数量与 Profile 列表项不符；
- 运行时还需要联网下载 GeoData；
- 未预校验就修改系统代理；
- 预校验进程超时后不能退出；
- 错误日志泄露订阅 URL 或节点凭据。

## 最终 Release 结果

- 使用用户刚添加的同一份真实 Profile 启动 Release 内置 Mihomo：PASS。
- Profile 节点：32；REST 代理组非空且可见节点不少于 32：PASS。
- GeoData 随 Release 发布并复制到独立运行目录：PASS。
- 自包含资产校验：28 项 PASS。
- 静态分析：0 issue。
- 文件/产品版本：`1.9.0-dev.73+83`。
- EXE SHA-256：`9B36D078D0EEFB7CF12F1ECFC324B15B0FF7BB0852AB1584105B7BB60064A796`。
