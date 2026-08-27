# Harness 功能模块与工具接口目录

> 本文由 `tool/export_harness_capability_catalog.dart` 从实际 `ToolSpec` 与 `VibekitsHarnessToolBridge` 生成。带 `*` 的参数为必填；运行时以 MCP `inputSchema` 为最终准则。

## 数量口径

- 产品一级页面：5（智能体、解压缩、系统清理、文档阅读、开发工具）。
- 开发工具业务能力条目：79。
- 开发工具独立工作区入口：19。
- Harness 定义接口：161。
- Harness 当前可执行接口：139。
- 当前不可公开接口：22。

不要把以上数字相加称为“总功能数”：页面、业务条目和机器接口是三种不同层级。Harness 回答时先调用 `vibekits.system.capability_check` 获取本次运行的动态数字。

## 统一调用协议

1. 通过 MCP 工具目录发现 `vibekits.*`。
2. 读取目标工具的 `description`、风险级别和 `inputSchema`。
3. 使用符合 Schema 的 JSON 对象调用；没有参数的工具传 `{}`。
4. 只读工具直接执行；写数据、控制设备或破坏性操作按当前权限模式审批。
5. 读取结构化结果，并在对应模块 Harness 记录中核对真实日志。

外部 MCP 客户端采用标准 `tools/call`，`name` 为下表工具 ID，`arguments` 为 JSON 参数。VibeKits 内置 Harness 会自动完成这层协议。

## 模块汇总

| 模块 | 可执行接口数 |
| --- | ---: |
| 文件工具 | 7 |
| 系统诊断 | 7 |
| 格式处理 | 10 |
| 加密生成 | 9 |
| 计算调试 | 9 |
| 编码转换 | 13 |
| 网络开发 | 25 |
| 时间文本 | 10 |
| 智能开发 | 1 |
| 音频调试 | 6 |
| 远程连接 | 27 |
| 数据库 | 5 |
| 版本控制 | 7 |
| 虚拟化 | 3 |

## 文件工具（7）

| 工具 ID | 名称 | 风险 | 参数 |
| --- | --- | --- | --- |
| `vibekits.batch_rename` | 批量重命名（Rename） | `writesData` | `input`*, `params` |
| `vibekits.code_statistics` | 代码统计（LOC） | `readOnly` | `input`*, `params` |
| `vibekits.code_structure_search` | 代码结构搜索（Structure） | `readOnly` | `input`*, `params` |
| `vibekits.file_diff` | 比较两个文件 | `readOnly` | `leftPath`*, `rightPath`*, `ignoreWhitespace`, `ignoreCase` |
| `vibekits.file_hash` | 文件哈希（Hash） | `readOnly` | `input`*, `params` |
| `vibekits.files.duplicate_scan` | 扫描重复文件 | `readOnly` | `root`*, `recursive`, `minimumSize` |
| `vibekits.files.search` | 搜索文件 | `readOnly` | `root`*, `query`*, `mode`, `maxResults` |

## 系统诊断（7）

| 工具 ID | 名称 | 风险 | 参数 |
| --- | --- | --- | --- |
| `vibekits.audio_analyzer` | 音频调试（PCM/WAV） | `readOnly` | `input`*, `params` |
| `vibekits.cleaner.analyze_drive` | 分析磁盘占用 | `readOnly` | `root`* |
| `vibekits.project.build` | 验证并编译 Vibekits APP | `writesData` | `workspace`*, `target`*, `flutterExecutable`, `runTests` |
| `vibekits.project.iteration_inspect` | 检查 APP 自迭代工作区 | `readOnly` | `workspace`* |
| `vibekits.system.capability_check` | 检查智能体工具链 | `readOnly` | `{}` |
| `vibekits.system.resources` | 检查系统资源 | `readOnly` | `adbSerial`, `samples`, `intervalMs` |
| `vibekits.windows_node.helper_status` | 检查 Windows 节点 Helper | `readOnly` | `{}` |

## 格式处理（10）

| 工具 ID | 名称 | 风险 | 参数 |
| --- | --- | --- | --- |
| `vibekits.csv_to_json` | CSV 转 JSON | `readOnly` | `input`*, `params` |
| `vibekits.json_escape` | JSON 字符串转义 | `readOnly` | `input`*, `params` |
| `vibekits.json_format` | JSON 格式化 | `readOnly` | `input`*, `params` |
| `vibekits.json_minify` | JSON 压缩 | `readOnly` | `input`*, `params` |
| `vibekits.json_query` | 结构化数据查询 | `readOnly` | `input`*, `params` |
| `vibekits.json_to_csv` | JSON 转 CSV | `readOnly` | `input`*, `params` |
| `vibekits.json_unescape` | JSON 字符串反转义 | `readOnly` | `input`*, `params` |
| `vibekits.json_validate` | JSON 校验 | `readOnly` | `input`*, `params` |
| `vibekits.xml_format` | XML 格式化 | `readOnly` | `input`*, `params` |
| `vibekits.xml_minify` | XML 压缩 | `readOnly` | `input`*, `params` |

## 加密生成（9）

| 工具 ID | 名称 | 风险 | 参数 |
| --- | --- | --- | --- |
| `vibekits.hmac_sha256` | HMAC-SHA256 | `readOnly` | `input`*, `params` |
| `vibekits.jwt_decode` | JWT 解码 | `readOnly` | `input`*, `params` |
| `vibekits.jwt_expiry` | JWT 过期检查 | `readOnly` | `input`*, `params` |
| `vibekits.md5` | MD5 | `readOnly` | `input`*, `params` |
| `vibekits.random_password` | 随机密码 | `readOnly` | `input`*, `params` |
| `vibekits.sha1` | SHA-1 | `readOnly` | `input`*, `params` |
| `vibekits.sha256` | SHA-256 | `readOnly` | `input`*, `params` |
| `vibekits.sha512` | SHA-512 | `readOnly` | `input`*, `params` |
| `vibekits.uuid_v4` | UUID v4 | `readOnly` | `input`*, `params` |

## 计算调试（9）

| 工具 ID | 名称 | 风险 | 参数 |
| --- | --- | --- | --- |
| `vibekits.bytes_convert` | 存储单位转换 | `readOnly` | `input`*, `params` |
| `vibekits.calculator.programmer` | 程序员计算器 | `readOnly` | `expression`*, `width`, `inputRadix` |
| `vibekits.chmod_decode` | chmod 权限解码 | `readOnly` | `input`*, `params` |
| `vibekits.chmod_encode` | chmod 权限编码 | `readOnly` | `input`*, `params` |
| `vibekits.duration_convert` | 时间单位转换 | `readOnly` | `input`*, `params` |
| `vibekits.endian_swap` | 字节序反转 | `readOnly` | `input`*, `params` |
| `vibekits.number_base_convert` | 2～36 进制转换 | `readOnly` | `input`*, `params` |
| `vibekits.safe_benchmark` | 安全性能基准（Benchmark） | `readOnly` | `input`*, `params` |
| `vibekits.semver_compare` | 语义版本比较 | `readOnly` | `input`*, `params` |

## 编码转换（13）

| 工具 ID | 名称 | 风险 | 参数 |
| --- | --- | --- | --- |
| `vibekits.ascii_inspect` | 字符码检查 | `readOnly` | `input`*, `params` |
| `vibekits.base64_decode` | Base64 解码 | `readOnly` | `input`*, `params` |
| `vibekits.base64_encode` | Base64 编码 | `readOnly` | `input`*, `params` |
| `vibekits.hex_decode` | Hex 解码 | `readOnly` | `input`*, `params` |
| `vibekits.hex_encode` | Hex 编码 | `readOnly` | `input`*, `params` |
| `vibekits.hex_to_rgb` | HEX 转 RGB | `readOnly` | `input`*, `params` |
| `vibekits.html_decode` | HTML 实体解码 | `readOnly` | `input`*, `params` |
| `vibekits.html_encode` | HTML 实体编码 | `readOnly` | `input`*, `params` |
| `vibekits.rgb_to_hex` | RGB 转 HEX | `readOnly` | `input`*, `params` |
| `vibekits.unicode_escape` | Unicode 转义 | `readOnly` | `input`*, `params` |
| `vibekits.unicode_unescape` | Unicode 反转义 | `readOnly` | `input`*, `params` |
| `vibekits.url_decode` | URL 解码 | `readOnly` | `input`*, `params` |
| `vibekits.url_encode` | URL 编码 | `readOnly` | `input`*, `params` |

## 网络开发（25）

| 工具 ID | 名称 | 风险 | 参数 |
| --- | --- | --- | --- |
| `vibekits.capture.analyze` | 分析 PCAP 流量 | `readOnly` | `path`* |
| `vibekits.capture.read` | 读取 PCAP 数据包 | `readOnly` | `path`*, `maxPackets` |
| `vibekits.capture.start` | 开始网络抓包 | `controlsDevice` | `outputPath`, `filter`, `maxPackets` |
| `vibekits.capture.status` | 检查网络抓包状态 | `readOnly` | `{}` |
| `vibekits.capture.stop` | 停止并保存网络抓包 | `controlsDevice` | `{}` |
| `vibekits.cidr_calc` | IP/CIDR 计算 | `readOnly` | `input`*, `params` |
| `vibekits.dns_lookup` | DNS 查询 | `readOnly` | `input`*, `params` |
| `vibekits.github.diagnose` | GitHub 网络诊断 | `readOnly` | `{}` |
| `vibekits.github.proxy_apply` | 应用 GitHub 专用代理 | `writesData` | `planId`*, `digest`* |
| `vibekits.github.proxy_candidates` | 发现 GitHub 代理候选 | `readOnly` | `{}` |
| `vibekits.github.proxy_plan` | 预览 GitHub 专用代理 | `readOnly` | `candidateId`* |
| `vibekits.github.proxy_rollback` | 恢复 GitHub 代理旧值 | `writesData` | `planId`*, `digest`* |
| `vibekits.http.request` | 发送 HTTP 请求 | `controlsDevice` | `method`*, `url`*, `headers`, `body` |
| `vibekits.http_status_lookup` | HTTP 状态码查询 | `readOnly` | `input`*, `params` |
| `vibekits.mime_lookup` | MIME 类型查询 | `readOnly` | `input`*, `params` |
| `vibekits.proxy.start` | 启动 Clash Verge 内核 | `controlsDevice` | `configPath`*, `dataDirectory`*, `systemProxyPort` |
| `vibekits.proxy.stop` | 停止 Clash Verge 内核 | `controlsDevice` | `dataDirectory` |
| `vibekits.proxy.system_apply` | 启用 Windows 系统代理 | `controlsDevice` | `port`*, `dataDirectory`* |
| `vibekits.proxy.system_restore` | 恢复 Windows 原系统代理 | `controlsDevice` | `dataDirectory`* |
| `vibekits.query_build` | 查询参数生成 | `readOnly` | `input`*, `params` |
| `vibekits.query_parse` | 查询参数解析 | `readOnly` | `input`*, `params` |
| `vibekits.runtime.inspect` | 检查代理与虚拟机运行时 | `readOnly` | `{}` |
| `vibekits.runtime.status` | 读取代理与虚拟机状态 | `readOnly` | `{}` |
| `vibekits.tcp_port` | TCP 端口测试 | `readOnly` | `input`*, `params` |
| `vibekits.url_parse` | URL 分解 | `readOnly` | `input`*, `params` |

## 时间文本（10）

| 工具 ID | 名称 | 风险 | 参数 |
| --- | --- | --- | --- |
| `vibekits.case_convert` | 命名风格转换 | `readOnly` | `input`*, `params` |
| `vibekits.date_to_timestamp` | 日期转时间戳 | `readOnly` | `input`*, `params` |
| `vibekits.glob_test` | Glob 匹配测试 | `readOnly` | `input`*, `params` |
| `vibekits.line_ending_normalize` | 换行符规范化 | `readOnly` | `input`*, `params` |
| `vibekits.line_sort` | 文本行排序 | `readOnly` | `input`*, `params` |
| `vibekits.line_unique` | 文本行去重 | `readOnly` | `input`*, `params` |
| `vibekits.regex_escape` | 正则字面量转义 | `readOnly` | `input`*, `params` |
| `vibekits.regex_test` | 正则测试 | `readOnly` | `input`*, `params` |
| `vibekits.text_statistics` | 文本统计 | `readOnly` | `input`*, `params` |
| `vibekits.timestamp_to_date` | 时间戳转日期 | `readOnly` | `input`*, `params` |

## 智能开发（1）

| 工具 ID | 名称 | 风险 | 参数 |
| --- | --- | --- | --- |
| `vibekits.next_action_recommendation` | 下一步建议 | `readOnly` | `input`*, `params` |

## 音频调试（6）

| 工具 ID | 名称 | 风险 | 参数 |
| --- | --- | --- | --- |
| `vibekits.audio.generate_tone` | 生成音频测试音 | `writesData` | `outputPath`*, `frequencyHz`, `durationSeconds`, `amplitude`, `sampleRate`, `channels`, `bitsPerSample`, `signed`, `littleEndian` |
| `vibekits.audio.inspect` | 分析 PCM / WAV 质量 | `readOnly` | `path`*, `sampleRate`, `channels`, `bitsPerSample`, `signed`, `littleEndian` |
| `vibekits.audio.pause` | 暂停音频 | `controlsDevice` | `{}` |
| `vibekits.audio.pcm_to_wav` | PCM 转 WAV | `writesData` | `inputPath`*, `outputPath`*, `sampleRate`, `channels`, `bitsPerSample`, `signed`, `littleEndian` |
| `vibekits.audio.play` | 播放 PCM / WAV | `controlsDevice` | `path`*, `sampleRate`, `channels`, `bitsPerSample`, `signed`, `littleEndian` |
| `vibekits.audio.stop` | 停止音频 | `controlsDevice` | `{}` |

## 远程连接（27）

| 工具 ID | 名称 | 风险 | 参数 |
| --- | --- | --- | --- |
| `vibekits.adb.command` | 执行 ADB 命令 | `controlsDevice` | `serial`*, `arguments`* |
| `vibekits.adb.connect` | 连接 ADB 设备 | `controlsDevice` | `address`* |
| `vibekits.adb.install_apk` | 安装 APK | `controlsDevice` | `serial`*, `apkPath`*, `replace` |
| `vibekits.adb.list_devices` | 列出 ADB 设备 | `readOnly` | `{}` |
| `vibekits.adb.logcat` | 读取 Android Logcat | `controlsDevice` | `serial`*, `lines`, `tag` |
| `vibekits.adb.pull_file` | 从 Android 拉取文件 | `controlsDevice` | `serial`*, `remotePath`*, `localPath`*, `overwrite` |
| `vibekits.adb.push_file` | 推送文件到 Android | `controlsDevice` | `serial`*, `localPath`*, `remotePath`* |
| `vibekits.adb.screenshot` | 保存 Android 截图 | `controlsDevice` | `serial`*, `localPath`*, `overwrite` |
| `vibekits.adb.session_close` | 关闭 ADB 长连接 | `controlsDevice` | `sessionId`* |
| `vibekits.adb.session_open` | 保持 ADB 长连接 | `controlsDevice` | `serial`*, `heartbeatSeconds` |
| `vibekits.adb.session_status` | 读取 ADB 长连接状态 | `readOnly` | `sessionId`* |
| `vibekits.adb.shell` | 执行 Android Shell | `controlsDevice` | `serial`*, `arguments`* |
| `vibekits.remote.list_profiles` | 列出远程会话 | `readOnly` | `{}` |
| `vibekits.remote.sftp_download` | SFTP 下载文件 | `writesData` | `profileId`*, `remotePath`*, `localPath`*, `overwrite` |
| `vibekits.remote.sftp_list` | 列出 SFTP 目录 | `readOnly` | `profileId`*, `remotePath` |
| `vibekits.remote.sftp_upload` | SFTP 上传文件 | `writesData` | `profileId`*, `localPath`*, `remotePath`*, `overwrite` |
| `vibekits.remote.ssh_exec` | 执行 SSH 命令 | `controlsDevice` | `profileId`*, `command`* |
| `vibekits.serial.list_ports` | 列出串口 | `readOnly` | `{}` |
| `vibekits.serial.session_close` | 关闭串口长连接 | `controlsDevice` | `sessionId`* |
| `vibekits.serial.session_open` | 打开串口长连接 | `controlsDevice` | `port`*, `baudRate`, `dataBits`, `stopBits`, `parity`, `flowControl` |
| `vibekits.serial.session_read` | 读取串口长连接 | `readOnly` | `sessionId`*, `mode`, `clear` |
| `vibekits.serial.session_write` | 写入串口长连接 | `controlsDevice` | `sessionId`*, `data`*, `mode`, `lineEnding` |
| `vibekits.serial.transact` | 串口收发与监听 | `controlsDevice` | `port`*, `baudRate`, `data`, `mode`, `waitMs` |
| `vibekits.windows_node.export_onboarding` | 导出节点 onboarding | `readOnly` | `host`*, `port`, `hostKeyFingerprint`*, `allowedCidr`* |
| `vibekits.windows_node.inspect` | 体检 Windows 测试节点 | `readOnly` | `rootPath` |
| `vibekits.windows_node.list_devices` | 列出节点设备 | `readOnly` | `{}` |
| `vibekits.windows_node.plan` | 生成 Windows 节点变更计划 | `readOnly` | `inspectionId`* |

## 数据库（5）

| 工具 ID | 名称 | 风险 | 参数 |
| --- | --- | --- | --- |
| `vibekits.database.remote_inspect` | 检查远程数据库 | `controlsDevice` | `profileId`* |
| `vibekits.database.remote_list_profiles` | 列出远程数据库会话 | `readOnly` | `{}` |
| `vibekits.database.remote_query` | 查询远程数据库 | `controlsDevice` | `profileId`*, `sql`* |
| `vibekits.sqlite.inspect` | 检查 SQLite 数据库 | `readOnly` | `path`* |
| `vibekits.sqlite.query` | 查询 SQLite 数据库 | `readOnly` | `path`*, `sql`*, `maxRows` |

## 版本控制（7）

| 工具 ID | 名称 | 风险 | 参数 |
| --- | --- | --- | --- |
| `vibekits.git.backup_commit` | 提交 Git 备份 | `writesData` | `previewId`*, `includedPaths`*, `message`* |
| `vibekits.git.backup_preview` | 预览 GitHub 备份 | `readOnly` | `path`*, `remoteId`*, `deviceLabel` |
| `vibekits.git.backup_push` | 推送 Git 备份 | `controlsDevice` | `previewId`*, `commitSha`* |
| `vibekits.git.compare_refs` | 对比 Git 两个版本 | `readOnly` | `path`*, `baseRef`*, `targetRef`* |
| `vibekits.git.create_local_branch` | 创建 Git 本地安全分支 | `writesData` | `path`*, `name`*, `startPoint` |
| `vibekits.git.inspect` | 检查 Git 工作区 | `readOnly` | `path`* |
| `vibekits.git.verify_remote_ref` | 核验远端备份 SHA | `readOnly` | `path`*, `remoteId`*, `targetBranch`* |

## 虚拟化（3）

| 工具 ID | 名称 | 风险 | 参数 |
| --- | --- | --- | --- |
| `vibekits.vm.create_disk` | 创建 QEMU 虚拟磁盘 | `writesData` | `path`*, `sizeGiB`* |
| `vibekits.vm.start` | 启动轻量虚拟机 | `controlsDevice` | `diskPath`, `isoPath`, `memoryMiB`, `cpuCount`, `headless` |
| `vibekits.vm.stop` | 停止轻量虚拟机 | `controlsDevice` | `{}` |

## 典型闭环

- 串口：一次交互用 `serial.list_ports → serial.transact`；持续调试用 `serial.session_open → session_read/session_write → session_close`。
- ADB：`adb.list_devices/connect → shell/logcat/screenshot/push/pull/install_apk`；持续任务用 `adb.session_open → session_status → session_close` 保持并核验连接。
- SSH/SFTP：`remote.list_profiles/open_interactive → ssh_exec/sftp_*`。
- Git 备份：`git.inspect → backup_preview → backup_commit → backup_push → verify_remote_ref`。
- 代理：`runtime.inspect → proxy.start → runtime.status → proxy.system_apply`；退出前恢复系统代理。
- 虚拟机：`runtime.inspect → vm.create_disk → vm.start → runtime.status → vm.stop`。
- APP 自迭代：`project.iteration_inspect → Harness 工作区写入 → project.build`；只生成 Release 产物，安装和发布仍需用户验收。
- 能力自检：`system.capability_check`；它只证明注册与处理器接线，不替代真机/网络/凭据门禁。
