# v1.9.0-dev.86 Android 双屏退出验收

验收日期：2026-08-24  
目标设备：`192.168.3.62:5555`  
结论：通过

## 环境与产物

| 项目 | 结果 |
| --- | --- |
| 设备状态 | ADB `device` |
| Display 0 | 内置屏，1920×1280 |
| Display 2 | HDMI 外接屏，1920×1280 |
| ABI | ARM64-v8a |
| 版本 | `1.9.0-dev.86` / versionCode `2096` |
| APK | `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` |
| 大小 | 61.2 MB |
| SHA-256 | `955AB66FAF1E6A4E65FC2133BC5F9141C71F34F2F71716DDEAF4F6090BEAFE9F` |

构建命令：

```powershell
D:\tools\flutter\bin\flutter.bat build apk --release --no-pub --target-platform android-arm64 --split-per-abi
```

构建成功，未使用 `--android-skip-build-dependency-validation`。安装使用项目内置 ADB，结果为 `Success`。

## 真机闭环

| 编号 | 操作 | 可观测证据 | 结果 |
| --- | --- | --- | --- |
| A62-01 | 在 D0 启动默认入口 | D0 `MainActivity` task 2011；D2 `DualScreenCompanionActivity` task 2012 | 通过 |
| A62-02 | 对 D0 发送返回键 | 3 秒后 ActivityManager 中两个双屏 Activity 均不存在 | 通过 |
| A62-03 | 重新启动，再对 D2 发送返回键 | 3 秒后 ActivityManager 中两个双屏 Activity 均不存在 | 通过 |
| A62-04 | 检查最近 500 行 Logcat | 无 `FATAL EXCEPTION`、无 `ANR in com.vibekits` | 通过 |
| A62-05 | Android 双屏合同测试 | 2/2 通过 | 通过 |

核心断言不是“窗口不可见”，而是两个 Activity 均已从 ActivityManager 删除，因此不会留下另一屏孤立窗口。实现只关闭配对 UI，不调用 `Process.killProcess()`，避免误杀独立 SSH、传输或智能体后台服务。

## 自动检查

```powershell
D:\tools\flutter\bin\flutter.bat test --no-pub test\android_dual_screen_contract_test.dart
```

覆盖内容：Launcher 路由、长按单屏快捷方式、D0 迁移延时、在线显示器枚举、D0/D2 配对退出以及禁止强杀进程。
