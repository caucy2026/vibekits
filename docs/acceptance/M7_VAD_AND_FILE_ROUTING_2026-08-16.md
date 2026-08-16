# M7 VAD、本地模型与全文件路由验收记录

日期：2026-08-16

版本：`1.3.0+4`
平台：Windows x64 / Flutter 3.47.0 / Dart 3.13.0

## 范围

- Markdown 拖入后的默认预览与源码切换。
- 单文件、多文件、未知扩展名、模型文件和系统启动参数的统一路由。
- 文件哈希多文件流式计算工作区。
- sherpa-onnx Windows 运行时、Silero VAD 精选下载清单和真实 WAV 推理。

## 模型供应链

| 模型 | 来源 | 许可证 | 大小 | SHA-256 | 结果 |
|---|---|---|---:|---|---|
| Silero VAD Sherpa 兼容版 | sherpa-onnx 官方 GitHub Release | MIT | 643,854 B | `9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6` | 真实推理通过 |
| Silero VAD v6 | Silero 官方仓库提交 `76e3dc408eb2a5c655c34e230d2d5459b4439daa` | MIT | 2,327,524 B | `1a153a22f4509e292a94e67d6f9b85e8deb25b4988682b7e174c65279d8788e3` | 真实推理通过 |

运行时为 `sherpa_onnx 1.13.5`。精选下载必须由用户点击触发，使用临时文件，完成后核对完整 SHA-256 再进入 `ModelStore.import`；取消、网络错误或哈希不符均不会留下可用模型。

## 真实推理

输入使用 sherpa-onnx 官方 `lei-jun-test.wav`（8,716,818 B），不是合成空数据。两款模型分别在独立 `flutter test` Windows 进程中加载 ONNX Runtime、读取 WAV、分窗推理、刷新并释放 VAD 会话；均发现非空语音片段且片段边界位于音频时长内。

执行命令：

```powershell
flutter test --reporter expanded test\vad_model_smoke_test.dart
flutter test --reporter expanded --dart-define=VAD_MODEL=silero_vad_v6.onnx test\vad_model_smoke_test.dart
```

两次结果均为 `All tests passed!`。

首次运行曾得到 Windows 错误 193。PE 头检查确认 `sherpa-onnx-c-api.dll` 与 `onnxruntime.dll` 均为 AMD64，最终定位为绝对路径加载主 DLL 时其依赖目录未进入 Windows 搜索路径；显式预加载同目录 `onnxruntime.dll` 后通过。此故障已保留为回归路径。

## 自动验收覆盖

- Markdown 默认渲染标题、正文与代码，源码切换可点且窄工具栏无溢出。
- 未知文本与二进制文件分别进入文本/Hex；伪装成 `.txt` 的 ZIP 按文件头进入压缩模块。
- 多文件拖入保留每一项、可切换打开；目录和不存在路径显示明确原因。
- `.onnx` 直接切换本地模型并提交导入；多个系统启动参数逐项路由。
- MD5、SHA-1、SHA-256、SHA-512 对标准 `abc` 文件得到标准摘要；分块进度从 0 到文件总长，预取消不产出摘要。
- 文件哈希 Widget 选择文件后自动计算 SHA-256，不再要求手填路径。

## 整体回归与 Release

- `flutter analyze`：`No issues found`。
- `flutter test --reporter expanded`：169/169 通过；默认测试包含 Sherpa 兼容版 VAD 真推理。
- Silero v6 使用 `--dart-define=VAD_MODEL=silero_vad_v6.onnx` 在独立进程再次通过。
- `flutter build windows --release` 成功；产物同时包含 `onnxruntime.dll` 与 `sherpa-onnx-c-api.dll`，测试模型不随 Release 强制打包。
- Release 同时接收 Markdown 与 YAML 两个启动参数，运行 5 秒保持稳定。
- 当前用户注册表实查通过：任意文件右键“用 Vibekits 自动处理”、`.onnx` 右键“导入到 Vibekits 本地模型”、多选模式 `Player`、`.onnx` 能力映射 `Vibekits.Model`。
- 本次 `vibekits.exe` SHA-256：`ABB55C1AC3D3DADF56306D8A8B612CB99A036380F365C5899D8E347FC57DA04E`。

## 仍未完成

- 本记录验证的是 VAD，不等同于产品矩阵中的 OCR、ASR 或 TTS；三者仍保持未实现状态。
- VAD 推理任务暂不能在单次 native 调用中强制中断，阈值、线程数和显式内存对比尚未开放。
- 模型下载没有断点续传；正式发布前仍需为全部三方运行时生成许可证清单。
