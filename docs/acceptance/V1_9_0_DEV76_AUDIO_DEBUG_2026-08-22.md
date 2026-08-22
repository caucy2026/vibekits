# v1.9.0-dev.76 音频调试验收

## 用户闭环

1. 在开发工具选择“音频调试”，或直接拖入 `.pcm/.raw/.wav/.wave`。
2. WAV 自动读取格式；RAW PCM 选择采样率、声道、位深、有符号状态和端序。
3. 后台分析后显示文件参数、多声道波形、频谱快照、峰值、RMS、削波、静音和直流偏置。
4. 点击播放直接听声音；RAW PCM 自动生成临时 WAV，APP 退出时释放播放器并清理预览文件。
5. Harness 调用 `vibekits.audio_analyzer`，`input` 为本地路径；RAW 参数通过 `params` JSON 传入。

## Harness 示例

```json
{
  "input": "D:\\audio\\capture.pcm",
  "params": "{\"sampleRate\":48000,\"channels\":2,\"bitsPerSample\":16,\"signed\":true,\"littleEndian\":true}"
}
```

## 已验证

- 自动测试生成 1 秒、16 kHz、16-bit、440 Hz PCM。
- RAW PCM 识别为 1 秒，峰值约 0.5、RMS 约 0.3535 且无削波。
- RAW 封装为 WAV 后再次识别，采样率、声道和时长一致。
- 目标文件静态分析无问题。
- Windows Release 构建通过。

## 来源边界

- 播放采用 MIT `audioplayers 6.8.1`。
- 波形、频谱与诊断算法由 Vibekits 独立实现；Spek 等 GPL 项目只用于工作流研究，没有复制源码。
