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

/// Highest-accuracy PP-OCRv6 tier. It is intentionally not bundled: the two
/// ONNX files add about 139 MB and must never delay startup or inflate mobile
/// packages. Desktop users can explicitly install the hash-pinned artifacts.
const CuratedModelBundle ppOcrV6MediumBundle = CuratedModelBundle(
  id: 'pp-ocrv6-medium',
  name: 'PP-OCRv6 Medium（桌面高精度）',
  capability: '50 语言高精度图片文字识别',
  version: 'v6 medium ONNX / 34.5M parameters',
  homepage: 'https://huggingface.co/collections/PaddlePaddle/pp-ocrv6',
  license: 'Apache-2.0',
  runtime: 'ONNX Runtime / CPU',
  artifacts: <CuratedModelArtifact>[
    CuratedModelArtifact(
      fileName: 'ppocrv6_medium_det.onnx',
      sourceUrl:
          'https://huggingface.co/PaddlePaddle/PP-OCRv6_medium_det_onnx/'
          'resolve/main/inference.onnx',
      sha256:
          'eb13b44b25bb36f89528b68720af8a61d9cf381176107f465db1757b65d086e1',
      downloadBytes: 62032837,
    ),
    CuratedModelArtifact(
      fileName: 'ppocrv6_medium_rec.onnx',
      sourceUrl:
          'https://huggingface.co/PaddlePaddle/PP-OCRv6_medium_rec_onnx/'
          'resolve/main/inference.onnx',
      sha256:
          '9c09abf0957f7968c7586464b7397b84ad2387a0497a351af40e9acc71b673ba',
      downloadBytes: 76554979,
    ),
    CuratedModelArtifact(
      fileName: 'ppocrv6_medium_rec.yml',
      sourceUrl:
          'https://huggingface.co/PaddlePaddle/PP-OCRv6_medium_rec_onnx/'
          'resolve/main/inference.yml',
      sha256:
          '991b700facf5b50a7de193468207d5f4255b538dde0d312ae3b7c7a9b6873129',
      downloadBytes: 150580,
    ),
  ],
);
