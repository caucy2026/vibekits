# v1.9.0-dev.87 Android 双屏异显验收

验收日期：2026-08-24  
目标设备：`192.168.3.62:5555`  
结论：通过

## 产物

| 项目 | 结果 |
| --- | --- |
| 版本 | `1.9.0-dev.87` / versionCode `2097` |
| APK | `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` |
| 大小 | 61.2 MB |
| SHA-256 | `E4138243A7495885BA3AD33C2626A3F5EEF173FDF2BE19CAF039BFA7AE42FC4B` |

## 62 真机闭环

| 编号 | 操作 | 实际结果 | 状态 |
| --- | --- | --- | --- |
| HET-01 | 默认双屏启动 | D0 `MainActivity`，D2 `DualScreenCompanionActivity` | 通过 |
| HET-02 | 查看 D0 | 默认显示“智能体（Harness）”，Harness 分段按钮处于选中态 | 通过 |
| HET-03 | 查看 D2 | 默认显示“开发工具 → 资源诊断（CPU/GPU）” | 通过 |
| HET-04 | 等待副屏采样 | 显示本机 Android CPU 18.6%、内存 38.1%、核心数、Load 和可用内存 | 通过 |
| HET-05 | 向下滚动副屏 | 显示 CPU/内存/GPU 图表说明和磁盘图表说明 | 通过 |
| HET-06 | 从 D2 返回 | D0/D2 两个 Activity 同时退出 | 通过 |
| HET-07 | 检查 Logcat | 无 VibeKits FATAL/ANR | 通过 |
| HET-08 | Android 合同测试 | 4/4 通过 | 通过 |

截图证据保存在本机构建目录：

- `build/acceptance/dev87/d0_harness.png`
- `build/acceptance/dev87/d2_resources.png`
- `build/acceptance/dev87/d2_chart_explanation.png`

## 图表说明范围

- 资源诊断：CPU、内存、GPU、磁盘占用比例及读数边界。
- 网络代理：橙色上传、蓝色下载、活动连接数。
- 音频调试：PCM 波形的时间/振幅含义，频谱的频率/能量、谐波与宽带噪声判断提示。

所有说明用于帮助理解，不把单次快照包装成持续性诊断结论。
