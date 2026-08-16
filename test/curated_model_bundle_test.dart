import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/local_models/domain/curated_model_bundle.dart';
import 'package:vibekits/features/local_models/domain/model_store.dart';

void main() {
  test('PP-OCRv6 tiny 精选包与官方测试资产哈希一致', () async {
    final String separator = Platform.pathSeparator;
    final String directory = <String>[
      Directory.current.path,
      'test_data',
      'models',
      'ppocrv6_tiny',
    ].join(separator);
    final Map<String, String> localFiles = <String, String>{
      'ppocrv6_tiny_det.onnx': '$directory${separator}det.onnx',
      'ppocrv6_tiny_rec.onnx': '$directory${separator}rec.onnx',
      'ppocrv6_tiny_rec.yml': '$directory${separator}rec.yml',
    };

    expect(ppOcrV6TinyBundle.artifacts, hasLength(3));
    for (final CuratedModelArtifact artifact in ppOcrV6TinyBundle.artifacts) {
      final String path = localFiles[artifact.fileName]!;
      expect(await File(path).length(), artifact.downloadBytes);
      expect(await ModelStore.sha256OfFile(path), artifact.sha256);
      expect(
        artifact.bundleAssetPath,
        startsWith('test_data/models/ppocrv6_tiny/'),
      );
    }
  });
}
