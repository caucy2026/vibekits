import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/local_models/domain/bundled_model_installer.dart';
import 'package:vibekits/features/local_models/domain/model_store.dart';

void main() {
  test('PP-OCRv6 tiny 无网络也能从应用内置资源安装', () async {
    final Directory models = await Directory.systemTemp.createTemp(
      'vibekits_bundled_models_',
    );
    addTearDown(() => models.delete(recursive: true));
    double progress = 0;

    final List<ModelInfo> installed =
        await BundledModelInstaller.installPpOcrV6Tiny(
          models.path,
          (String path) => File(path).readAsBytes(),
          (double value) => progress = value,
        );

    expect(installed, hasLength(3));
    expect(progress, 1);
    for (final String name in <String>[
      'ppocrv6_tiny_det.onnx',
      'ppocrv6_tiny_rec.onnx',
      'ppocrv6_tiny_rec.yml',
    ]) {
      expect(
        File('${models.path}${Platform.pathSeparator}$name').existsSync(),
        isTrue,
      );
    }
    expect(
      (await ModelStore.list(
        models.path,
      )).every((ModelInfo model) => model.integrity == ModelIntegrity.verified),
      isTrue,
    );
  });
}
