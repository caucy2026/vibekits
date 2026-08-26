# v1.9.0-dev.93 Android 连续跨屏画布验收

日期：2026-08-24  
版本：`1.9.0-dev.93+103`  
设备：`192.168.3.62:5555`  
目标：一张 `1920×2560` Flutter 逻辑画布连续显示在 D2（上）与 D0（下），而非两个 Activity 或两个独立页面。

## 实现结论

- 唯一 `MainActivity`、唯一 Flutter Engine/View、唯一 Widget 状态树。
- D2 `Presentation` 绘制源 FlutterView 的 `Y=0..1279`。
- D0 源窗口显示同一 View 的 `Y=1280..2559`。
- D2 触摸转发到源 View；状态、滚动和工具操作不复制。
- 两屏均使用沉浸式 `1920×1280` 可视区域。
- 双屏退出关闭 Activity 与 Presentation；单屏快捷模式继续保留。

## 真机闭环

| 编号 | 动作 | 唯一预期 | 结果 |
| --- | --- | --- | --- |
| AC-01 | 安装 ARM64 Release 并普通启动 | D0/D2 同时出现连续画布 | 通过 |
| AC-02 | 检查 Activity/Window | 仅一个 MainActivity；D2 为 Presentation | 通过 |
| AC-03 | D2 点击 OCR Tab | D2 与 D0 显示同一 OCR 页的上下区段 | 通过 |
| AC-04 | D2 点击退出 | Activity 与 D2 Presentation 同时消失 | 通过 |
| AC-05 | 再次启动 | 连续画布重新建立，无残留窗口 | 通过 |
| AC-06 | 检查 Logcat | 无 AndroidRuntime/Flutter fatal | 通过 |

关键设备日志：

```text
VibekitsContinuous: attach displays=[id=0,state=2,mode=1920x1280, id=2,state=2,mode=1920x1280]
VibekitsContinuous: continuous canvas active: D2=0..1279 D0=1280..2559
```

退出检查：

```text
EXIT_PASS: MainActivity and D2 Presentation closed
```

## 自动门禁与构建

- `flutter test --no-pub test/android_dual_screen_contract_test.dart`：5/5 通过。
- `flutter analyze --no-pub`：No issues found。
- `flutter build apk --release --target-platform android-arm64`：通过。
- APK：`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
- 大小：64,207,214 bytes。
- SHA-256：`8C9BD70E045D8AB32B33158BC264E95F7CCDFDBCE3EE1191D60A5E35E59E3CFB`

## 图像证据

- D2 连续画布上半区：`build/acceptance/dev93/d2-upper.png`
- D0 连续画布下半区：`build/acceptance/dev93/d0-lower.png`
- D2 点击 OCR 后：`build/acceptance/dev93/d2-ocr-touch.png`
- 同时刻 D0 OCR 下半区：`build/acceptance/dev93/d0-ocr-state.png`

## 历史实现纠正

dev.86～dev.88 的“双 Activity 异显”只能共享存储，不能满足一张连续画布和同一交互树，因此已被 dev.93 完整替代。合同测试明确禁止 `DualScreenCompanionActivity` 回归。
