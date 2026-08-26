# Android 单屏与连续跨屏规范

更新日期：2026-08-24  
实现版本：`1.9.0-dev.93+103`

> 本文从 dev.93 起取代 dev.86～dev.88 的“双 Activity 异显”实现。目标不是两个独立页面，而是一个 Flutter 状态树运行在一张纵向 `1920×2560` 逻辑画布上，由两块 `1920×1280` 物理屏连续显示。

## 产品行为

| 用户动作 | 模式 | 行为 |
| --- | --- | --- |
| 普通点击图标 | 连续跨屏（默认） | 一个 `MainActivity`、一个 Flutter Engine、一个状态树；D2 显示画布 `Y=0..1279`，D0 显示 `Y=1280..2559` |
| 点击 D2 内容 | 同一交互树 | 触摸坐标转发给 D0 上的源 FlutterView，同一状态同时反映到上下屏 |
| 长按图标 → 单屏模式 | 单屏 | 只启动当前物理屏上的普通 Flutter 页面，不创建 Presentation |
| 点击跨屏退出 | 原子退出 | 关闭 `MainActivity` 与 D2 `Presentation`，不留下第二个 Activity |
| HOME | 后台 | UI 进入后台；独立后台服务继续遵循各自生命周期 |

默认页面仍为 Harness。跨屏时界面按一张连续长画布布局，上屏不是“副工具页”，下屏也不是第二份应用；滚动、选择、OCR Tab 和工具状态属于同一棵 Widget/RenderObject 树。

## 实现架构

- `MainActivity` 是跨屏模式中唯一 Activity，并持有唯一 Flutter Engine/View。
- Flutter 根视图固定为逻辑 `1920×2560`；D0 窗口显示其下半段，源视图使用 `translationY=-1280`。
- D2 使用 Android `Presentation`，其 Surface 在每帧调用源 FlutterView 的 `draw(Canvas)`，显示同一画布上半段。
- D2 触摸事件经 `dispatchTouchEvent` 转发给同一个源 FlutterView，因此 Tab、按钮和滚动共享状态，不复制业务逻辑。
- Flutter Android 渲染模式为 `RenderMode.texture`，使源 View 可以稳定绘制到 D2 Presentation。
- D0/D2 都隐藏系统栏，物理可视区域严格为 `1920×1280`，避免状态栏或导航栏造成中缝和偏移。
- 设备枚举使用 `DisplayManager` 和真实物理模式，不假定 Display ID 连续；目标设备优先选择在线的 `1920×1280` 外接屏。
- 外接屏未就绪时采用 250 ms 有界重试，最多 12 次；单屏设备自然降级，不阻塞其他功能。

实现遵循 KEMI `unique` 目录的“一个状态树 + 多 Surface/View + 统一输入路由”路径：[跨显示器连续办公设计](https://github.com/caucy2026/kemi-rd/blob/main/unique/DUAL_DISPLAY_CONTINUOUS_OFFICE_DESIGN.md)、[双屏合成与联动交互](https://github.com/caucy2026/kemi-rd/blob/main/unique/DUAL_DISPLAY_COMPOSITION_AND_LINKED_INTERACTION.md)。

## 安全与生命周期边界

1. 不再创建 `DualScreenCompanionActivity`，Manifest 与合同测试都禁止该 Activity 回归。
2. 跨屏退出只结束 UI Activity/Presentation，不使用 `Process.killProcess()`，避免误杀独立后台 SSH、传输或智能体服务。
3. `onDestroy`、显示器移除或模式切换都会注销 DisplayListener、移除绘制监听并释放 Presentation。
4. D2 绘制采用合帧与递归保护，避免源 View 重绘形成死循环。
5. 屏幕尺寸不匹配时不强行裁切；记录诊断日志并安全降级为单屏。

## 验收矩阵

1. D0 与 D2 均为 `1920×1280` 时，普通启动后只有一个 `MainActivity`，D2 存在一个 Presentation 窗口。
2. D2 显示逻辑画布上半段，D0 显示下半段，边界连续且无系统栏空隙。
3. 在 D2 点击 OCR Tab 后，D2 切换到 OCR 上半区，D0 同时显示同一 OCR 页下半区。
4. D2 点击退出后，`MainActivity` 与 Presentation 均从窗口/Activity 记录中消失。
5. 单屏快捷入口只创建一个窗口，不等待外接屏。
6. Logcat 不出现 AndroidRuntime、Flutter fatal、重复 Presentation 或递归绘制错误。

## 192.168.3.62 真机结论

2026-08-24 在目标设备完成 ARM64 Release 闭环：

- 显示拓扑：D0 与 D2 均为 `1920×1280`。
- 安装版本：`1.9.0-dev.93+103`。
- 日志明确报告：`continuous canvas active: D2=0..1279 D0=1280..2559`。
- ActivityManager 仅有一个 `com.vibekits.vibekits.MainActivity`；D2 为同 Activity 的 Presentation 窗口。
- 通过 `adb shell input -d 2 tap ...` 在 D2 点击 OCR，D0/D2 同步进入同一 OCR 状态，通过。
- 在 D2 点击退出后，Activity 与 Presentation 同时消失；重新启动后双屏恢复，通过。
- 合同测试 5/5、`flutter analyze --no-pub` 0 问题、ARM64 Release 构建通过。

完整证据见 [dev.93 Android 连续跨屏画布验收](acceptance/V1_9_0_DEV93_ANDROID_CONTINUOUS_CANVAS_2026-08-24.md)。
