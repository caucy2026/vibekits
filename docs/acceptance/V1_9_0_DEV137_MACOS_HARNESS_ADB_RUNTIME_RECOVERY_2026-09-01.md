# VibeKits macOS Harness ADB Runtime 恢复验收报告

日期：2026-09-01  
版本：`v1.9.0-dev.137+2137`  
目标设备：`192.168.3.63:5555`

## 1. 失败原因

Harness 工具记录中的两次红色失败并不是设备拒绝或网络超时。实际返回为：

```text
ProcessException: No such file or directory
Command: .../Vibekits.app/Contents/MacOS/tools/adb/adb -s 192.168.3.63:5555 ...
```

本轮完整重建只打包了 Harness runtime，没有把官方 Android Platform-Tools ADB 放入 App 私有路径。命令在 5–23 ms 内失败，尚未连接设备。

恢复 ADB 后重放原参数又确认第二个问题：Android `getprop` 最多接受属性名和默认值两个参数，原任务一次传入六个属性名，返回 `getprop: Max 2 arguments` / exit 255。

## 2. 修复

1. Release 打包必须包含 `Contents/MacOS/tools/adb/adb`；缺少官方 ADB 时构建失败。
2. ADB 为 Universal x86_64+arm64，并在最终 App 深度签名时一并验签。
3. 能力自检新增 `missingRuntimes`，真实文件缺失时 `ready=false`。
4. `vibekits.adb.shell` 自动识别多个合法 Android property name，逐项执行 `getprop` 并返回结构化映射。

## 3. 验证结果

- ADB/Bridge 定向测试：`38` 通过、`1` 个既有环境测试跳过。
- 静态分析：`No issues found`。
- macOS Release：构建成功，约 613 MB；严格 codesign 验证通过。
- 正式内置 ADB：Platform-Tools 37.0.0、ADB 1.0.41，Universal x86_64+arm64。
- Harness 工具桥真实只读测试：`1/1` 通过。

真实返回：

```text
capabilityReady=true
missingRuntimes=[]
expandedGetprop=true
ro.product.model=huanglong
ro.product.manufacturer=HL2.0
ro.board.platform=huanglong
ro.build.version.release=12
ro.build.version.sdk=31
ro.product.cpu.abi=arm64-v8a
Display Id=0, 1920x1280
Display Id=2, 1920x1280
```

结论：截图中的 ADB runtime 缺包和多属性参数错误均已修复，63 的只读设备/双屏诊断链路恢复。

## 4. 外部模型边界

本报告的真实设备结果由本机 VibeKits Harness 工具桥产生，没有发送到外部模型。让 DeepSeek Harness 自主重新规划整段任务会把局域网地址和诊断结果发送给 DeepSeek API，需要用户对该具体数据传输明确授权。
