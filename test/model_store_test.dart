import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/local_models/domain/model_store.dart';

void main() {
  test('SHA-256 计算', () {
    expect(
      ModelStore.sha256OfBytes('hello'.codeUnits),
      '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
    );
  });

  test('导入与删除模型', () async {
    final Directory dir = Directory.systemTemp.createTempSync('vk_model');
    final Directory src = Directory.systemTemp.createTempSync('vk_model_src');
    final File source = File('${src.path}/model.onnx')
      ..writeAsStringSync('fake-onnx');
    try {
      final ModelInfo info = await ModelStore.import(source.path, dir.path);
      expect(info.fileName, 'model.onnx');
      expect(info.capability, '未知');
      expect(info.sha256.length, 64);

      final List<ModelInfo> installed = ModelStore.list(dir.path);
      expect(installed.length, 1);
      expect(ModelStore.delete('${dir.path}/model.onnx'), isTrue);
      expect(ModelStore.list(dir.path), isEmpty);
    } finally {
      dir.deleteSync(recursive: true);
      src.deleteSync(recursive: true);
    }
  });
}
