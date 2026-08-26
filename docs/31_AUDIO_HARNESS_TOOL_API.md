# 音频 Harness 工具接口

`vibekits.audio.inspect` 除整段质量指标外，还返回 `timelineSummary`：

- `harmonicHotspots`：按 THD 排序的最多五个时间段；
- `noiseHotspots`：按估算 SNR 从低到高排列的最多五个时间段；
- 每段包含开始/结束时间、峰值、RMS、削波比例、基频、THD、SNR、噪声底和单音可信度；
- `includeVisualData=true` 时返回完整有界 `timeline`，用于界面定位和点击试听。

这些指标对稳态单音最可靠。语音和音乐必须结合频谱、波形和上下文，不得把估算结果描述成实验室仪器结论。

音频工具与 APP 的“开发工具 → 音频调试”共用 `AudioAnalysisService`，Harness 调用会进入统一工具日志。RAW PCM 未携带格式头，必须在调用时给出真实格式；WAV 会自动读取格式头。

## 通用 RAW PCM 参数

| 参数 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `sampleRate` | integer | 48000 | 采样率 |
| `channels` | integer | 2 | 1～8 声道 |
| `bitsPerSample` | integer | 16 | 8/16/24/32 bit |
| `signed` | boolean | true | 是否有符号 |
| `littleEndian` | boolean | true | 是否小端 |

## 工具

### `vibekits.audio.inspect`

只读。输入 `path` 和可选 RAW 参数，返回格式、时长、峰值/RMS、直流偏置、削波率、静音率，以及：

- `quality.dominantFrequencyHz`：主频；
- `quality.harmonicsDbRelativeToFundamental`：2～5 次谐波 dBc；
- `quality.thdPercent`、`quality.thdnPercent`；
- `quality.estimatedSnrDb`、`quality.noiseFloorDbfs`；
- `quality.crestFactorDb`、`quality.channelCorrelation`；
- `quality.estimatedEffectiveBits`、`quality.qualityScore`。

```json
{"path":"D:\\audio\\capture.pcm","sampleRate":48000,"channels":2,"bitsPerSample":16,"signed":true,"littleEndian":true}
```

THD、THD+N、SNR 是稳态单音窗口估算。复杂音乐、语音、扫频应结合波形、频谱及 `tonalConfidence` 判断，不能把估算值冒充实验室仪器结果。

### `vibekits.audio.pcm_to_wav`

写文件。输入 `inputPath`、`outputPath` 和 RAW 参数，仅封装 WAV，不重采样、不修改样本。

### `vibekits.audio.play` / `pause` / `stop`

设备控制。`play` 输入 `path`；RAW PCM 还需格式参数。`pause`、`stop` 无参数，控制 Harness 启动的播放器。

### `vibekits.audio.generate_tone`

写文件。生成 16-bit 正弦 WAV 并立即返回同一分析服务的质量结果，用于自动闭环。

```json
{
  "outputPath":"D:\\audio\\self_test.wav",
  "frequencyHz":1000,
  "durationSeconds":1,
  "amplitude":0.5,
  "sampleRate":48000,
  "channels":2,
  "bitsPerSample":16
}
```

## 推荐智能体流程

1. 用户提供文件时先调用 `vibekits.audio.inspect`，不要先播放未知高幅度信号。
2. RAW 参数不明确时询问或从上下文取得，禁止猜测后给出确定结论。
3. 需要试听时调用 `play`，用户要求暂停/停止时调用对应接口。
4. 验证音频链路时调用 `generate_tone`，再用 `inspect` 核对主频、THD 和削波。
5. 需要交付通用文件时调用 `pcm_to_wav`，不得覆盖原 PCM。

所有接口由 Harness 通用调用层记录工具 ID、目标、耗时、成功/失败和返回摘要；用户可在当前工具的 Harness 记录中查看或删除日志，也可在设置中关闭日志。
