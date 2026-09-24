# PAD 编译组件第三方许可

本组件离线携带 OpenJDK 21、Android 构建工具及所需运行库。OpenJDK 的原始 `legal/` 目录保留在 `pad-builder-toolchain-arm64.zip` 中。

| 内容 | 来源与版本 | 随包许可文本 |
| --- | --- | --- |
| aapt 16.0.0.4-2、apksigner 37.0.0、dx 1:1.16-7 | Termux 官方包 | `termux-licenses-Apache-2.0.txt` |
| Android API 35 `android.jar` | Android SDK；再分发条款待核验 | 待补充 |
| libandroid-shmem 0.7 | Termux 官方包 | `libandroid-shmem-copyright` |
| libandroid-spawn 0.3 | Termux 官方包 | `libandroid-spawn-LICENSE` |
| libexpat 2.8.5 | Termux 官方包 | `libexpat-copyright` |
| libpng 1.6.58 | Termux 官方包 | `libpng-copyright` |
| zlib 1.3.1 | Termux 历史镜像包 | `zlib131-LICENSE` |
| libc++ 运行库 | Android NDK / Termux，当前快照的精确包修订待核验 | `termux-licenses-NCSA.txt` |

官方包索引：<https://packages.termux.dev/apt/termux-main/dists/stable/main/binary-aarch64/Packages.gz>。源码配方：<https://github.com/termux/termux-packages>。本文件是许可声明，不代表当前开发快照已通过正式发布验收。
