# PAD 编译组件第三方许可

本组件离线携带 Termux `openjdk-21` 与 `openjdk-21-x` 21.0.12、Android 构建工具及所需运行库。OpenJDK 的原始 `legal/` 目录保留在 `pad-builder-toolchain-arm64.zip` 中。

| 内容 | 来源与版本 | 随包许可文本 |
| --- | --- | --- |
| aapt 16.0.0.4-2、apksigner 37.0.0、dx 1:1.16-7 | Termux 官方包 | `termux-licenses-Apache-2.0.txt` |
| 设备自带 Android 框架 | 在 PAD 上按需读取 `/system/framework/framework.jar` 与 `framework-res.apk`；不随组件分发 | 依设备系统许可 |
| dex2jar v2.4 及依赖 | 官方 GitHub 发布包；只用于从本机框架 DEX 生成编译桩 | 工具链内 `dex2jar/LICENSE.txt`、`NOTICE.txt`、`lib/open-source-license.txt` |
| libandroid-shmem 0.7 | Termux 官方包 | `libandroid-shmem-copyright` |
| libandroid-spawn 0.3 | Termux 官方包 | `libandroid-spawn-LICENSE` |
| libexpat 2.8.5 | Termux 官方包 | `libexpat-copyright` |
| libpng 1.6.58 | Termux 官方包 | `libpng-copyright` |
| zlib 1.3.2 | Termux `zlib_1.3.2_aarch64.deb`，包哈希与固定索引一致 | `zlib132-copyright`（直接取自该包的 `share/doc/zlib/copyright`） |
| libc++ 运行库 30 | Termux `libc++_30_aarch64.deb`，包哈希与固定索引一致 | `termux-licenses-NCSA.txt` |

官方包索引：<https://packages.termux.dev/apt/termux-main/dists/stable/main/binary-aarch64/Packages.gz>。源码配方：<https://github.com/termux/termux-packages>。本文件是许可声明，不代表当前开发快照已通过正式发布验收。
