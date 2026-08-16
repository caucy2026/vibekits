# 第三方组件、模型与供应链记录

更新日期：2026-08-16

适用版本：`1.4.0+5`

## 发布时直接使用的关键组件

| 组件 | 固定版本 | 用途 | 许可证 | 来源与完整性 |
|---|---|---|---|---|
| 7-Zip Windows x64 | 26.02 | RAR/7z/ZIP/ISO/ZSTD/CAB/WIM/DMG 等列表与解压 | LGPL-2.1-or-later；RAR 解码另受 unRAR 限制 | 官方安装器；安装器 SHA-256 `6745fa76...2ef0`；`native/7zip` 保留原始许可证、历史和二进制哈希 |
| ONNX Runtime C API | 随 sherpa-onnx Windows 运行时 | PP-OCRv6 tiny CPU 推理 | MIT | 官方头文件；Release 运行库由已锁定依赖提供，Vibekits 桥接只调用公开 C API |
| `sherpa_onnx` | 1.13.5 | Silero VAD 与 Windows ONNX Runtime 分发 | Apache-2.0 | pub.dev 锁文件 SHA-256 `94f9fc85...d31b` |
| `sqlite3` | 3.5.1 | SQLite 只读数据库管理和 Windows/macOS 原生资产 | MIT | pub.dev 锁文件 SHA-256 `64b2c63c...478a`；使用 Dart native-asset hooks |
| `image` | 4.9.1 | 图片格式探测、首帧解码、方向固化和 PNG 预览 | MIT | pub.dev 锁文件 SHA-256 `6300175e...c52` |

完整 Dart/Flutter 直接与传递依赖版本、来源和包哈希以 `pubspec.lock` 为准；发布前不得绕过锁文件临时升级。

## PP-OCRv6 tiny 官方模型包

上游：PaddlePaddle/PaddleOCR；许可证：Apache-2.0；模型由用户主动安装，不随应用静默下载。

| 资产 | 字节 | SHA-256 |
|---|---:|---|
| `ppocrv6_tiny_det.onnx` | 1,780,590 | `193bab7a04fca699a6c82e6abb5b81bdb28177f0abd4062552b04908dafb19f8` |
| `ppocrv6_tiny_rec.onnx` | 4,462,639 | `9ef676d6ed3c88256a2d92c640c44f25b0c40947e111b14b8be8f594091563e6` |
| `ppocrv6_tiny_rec.yml` | 55,571 | `66170210bad538e83fff3c4a3867e547d6bf20b50d64b20347c4b913f3034ea1` |

下载写入临时文件；三项全部满足大小和 SHA-256 后才事务安装，任一失败不替换现有可用包。

## 开源借鉴边界

- Zed、Geany、OpenSSH、Git 和 GitHub 文档只用于工作流与操作习惯研究，没有复制 GPL 项目代码。
- SSH/SFTP、Git 使用用户系统安装的官方命令；参数以列表传递，`runInShell=false`。
- GitHub 网络诊断只读取 DNS/TLS/HTTPS/代理/hosts/SSH 状态，不移植 FastGithub 的 hosts、代理、证书或系统修改逻辑。
- 不直接嵌入 GPL/AGPL 工具源码；新增组件必须先记录版本、许可证、上游、产物方式和哈希。

## 当前供应链缺口

- macOS ONNX Runtime arm64/x64 原生库和桥接尚未固定版本与哈希，因此 macOS OCR 不得标记完成。
- 正式安装器还需汇总完整 NOTICE/SBOM，并在安装目录提供所有必须随附的许可证文本。
- HEIF/AVIF/JXL/RAW 解码器尚未选型；许可证和二进制供应链评审前不得只注册扩展名假装支持。
