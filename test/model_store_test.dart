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

      final List<ModelInfo> installed = await ModelStore.list(dir.path);
      expect(installed.length, 1);
      expect(installed.single.integrity, ModelIntegrity.verified);
      source.writeAsStringSync('changed');
      File('${dir.path}/model.onnx').writeAsStringSync('changed');
      final List<ModelInfo> changed = await ModelStore.list(dir.path);
      expect(changed.single.integrity, ModelIntegrity.modified);
      expect(ModelStore.delete('${dir.path}/model.onnx'), isTrue);
      expect(await ModelStore.list(dir.path), isEmpty);
    } finally {
      dir.deleteSync(recursive: true);
      src.deleteSync(recursive: true);
    }
  });

  test('导入拒绝超过大小上限且不留下半成品', () async {
    final Directory dir = Directory.systemTemp.createTempSync('vk_model_limit');
    final File source = File('${dir.path}/large.onnx')
      ..writeAsBytesSync(<int>[1, 2, 3, 4]);
    final Directory models = Directory('${dir.path}/models');
    try {
      expect(
        () => ModelStore.import(source.path, models.path, maxBytes: 3),
        throwsFormatException,
      );
      expect(models.existsSync(), isFalse);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('模型清单损坏时安全降级为未登记', () async {
    final Directory dir = Directory.systemTemp.createTempSync(
      'vk_model_manifest_bad',
    );
    try {
      File('${dir.path}/ocr.onnx').writeAsStringSync('model');
      File('${dir.path}/.vibekits-models.json').writeAsStringSync('{bad');

      final List<ModelInfo> models = await ModelStore.list(dir.path);

      expect(models.single.fileName, 'ocr.onnx');
      expect(models.single.integrity, ModelIntegrity.untracked);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
