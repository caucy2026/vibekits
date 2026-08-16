class CuratedModelArtifact {
  const CuratedModelArtifact({
    required this.fileName,
    required this.sourceUrl,
    required this.sha256,
    required this.downloadBytes,
    this.bundleAssetPath,
  });

  final String fileName;
  final String sourceUrl;
  final String sha256;
  final int downloadBytes;
  final String? bundleAssetPath;
}

class CuratedModelBundle {
  const CuratedModelBundle({
    required this.id,
    required this.name,
    required this.capability,
    required this.version,
    required this.homepage,
    required this.license,
    required this.runtime,
    required this.artifacts,
  });

  final String id;
  final String name;
  final String capability;
  final String version;
  final String homepage;
  final String license;
  final String runtime;
  final List<CuratedModelArtifact> artifacts;

  int get downloadBytes => artifacts.fold<int>(
    0,
    (int total, CuratedModelArtifact artifact) =>
        total + artifact.downloadBytes,
  );
}

const CuratedModelBundle ppOcrV6TinyBundle = CuratedModelBundle(
  id: 'pp-ocrv6-tiny',
  name: 'PP-OCRv6 tiny',
  capability: '多语言图片文字识别',
  version: 'v6 tiny ONNX',
  homepage: 'https://github.com/PaddlePaddle/PaddleOCR',
  license: 'Apache-2.0',
  runtime: 'ONNX Runtime / CPU',
  artifacts: <CuratedModelArtifact>[
    CuratedModelArtifact(
      fileName: 'ppocrv6_tiny_det.onnx',
      sourceUrl:
          'https://huggingface.co/PaddlePaddle/PP-OCRv6_tiny_det_onnx/'
          'resolve/main/inference.onnx',
      sha256:
          '193bab7a04fca699a6c82e6abb5b81bdb28177f0abd4062552b04908dafb19f8',
      downloadBytes: 1780590,
      bundleAssetPath: 'test_data/models/ppocrv6_tiny/det.onnx',
    ),
    CuratedModelArtifact(
      fileName: 'ppocrv6_tiny_rec.onnx',
      sourceUrl:
          'https://huggingface.co/PaddlePaddle/PP-OCRv6_tiny_rec_onnx/'
          'resolve/main/inference.onnx',
      sha256:
          '9ef676d6ed3c88256a2d92c640c44f25b0c40947e111b14b8be8f594091563e6',
      downloadBytes: 4462639,
      bundleAssetPath: 'test_data/models/ppocrv6_tiny/rec.onnx',
    ),
    CuratedModelArtifact(
      fileName: 'ppocrv6_tiny_rec.yml',
      sourceUrl:
          'https://huggingface.co/PaddlePaddle/PP-OCRv6_tiny_rec_onnx/'
          'resolve/main/inference.yml',
      sha256:
          '66170210bad538e83fff3c4a3867e547d6bf20b50d64b20347c4b913f3034ea1',
      downloadBytes: 55571,
      bundleAssetPath: 'test_data/models/ppocrv6_tiny/rec.yml',
    ),
  ],
);
