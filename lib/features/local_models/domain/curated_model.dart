class CuratedModel {
  const CuratedModel({
    required this.id,
    required this.name,
    required this.fileName,
    required this.capability,
    required this.version,
    required this.sourceUrl,
    required this.homepage,
    required this.license,
    required this.sha256,
    required this.downloadBytes,
    required this.runtime,
    required this.statusNote,
  });

  final String id;
  final String name;
  final String fileName;
  final String capability;
  final String version;
  final String sourceUrl;
  final String homepage;
  final String license;
  final String sha256;
  final int downloadBytes;
  final String runtime;
  final String statusNote;
}

const List<CuratedModel> curatedModels = <CuratedModel>[
  CuratedModel(
    id: 'silero-vad-sherpa-v4',
    name: 'Silero VAD · Sherpa 兼容版',
    fileName: 'silero_vad.onnx',
    capability: '语音片段检测',
    version: 'v4 export',
    sourceUrl: 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx',
    homepage: 'https://github.com/snakers4/silero-vad',
    license: 'MIT',
    sha256: '9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6',
    downloadBytes: 643854,
    runtime: 'sherpa-onnx 1.13.x / CPU',
    statusNote: '已完成 Windows x64 真实 WAV 推理验证',
  ),
  CuratedModel(
    id: 'silero-vad-v6',
    name: 'Silero VAD · 当前 v6',
    fileName: 'silero_vad_v6.onnx',
    capability: '语音片段检测',
    version: 'v6 · 76e3dc4',
    sourceUrl: 'https://raw.githubusercontent.com/snakers4/silero-vad/76e3dc408eb2a5c655c34e230d2d5459b4439daa/src/silero_vad/data/silero_vad.onnx',
    homepage: 'https://github.com/snakers4/silero-vad',
    license: 'MIT',
    sha256: '1a153a22f4509e292a94e67d6f9b85e8deb25b4988682b7e174c65279d8788e3',
    downloadBytes: 2327524,
    runtime: 'ONNX Runtime / CPU',
    statusNote: '已完成 Windows x64 真实 WAV 推理验证',
  ),
];
