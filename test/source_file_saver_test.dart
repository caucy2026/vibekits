import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/documents/domain/source_file_saver.dart';

void main() {
  test('真实文件在身份复核后原子替换且不残留临时文件', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_source_save_',
    );
    final File source = File('${sandbox.path}${Platform.pathSeparator}main.txt')
      ..writeAsStringSync('before');
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final DateTime modified = source.lastModifiedSync();

    final SourceSaveResult result = await SourceFileSaver.save(
      source.path,
      Uint8List.fromList('after'.codeUnits),
      expectedSize: 6,
      expectedModified: modified,
    );

    expect(source.readAsStringSync(), 'after');
    expect(result.size, 5);
    expect(
      sandbox.listSync().where(
        (FileSystemEntity item) => item.path.contains('.vibekits-'),
      ),
      isEmpty,
    );
  });

  test('外部修改后拒绝覆盖并保留外部版本', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_source_race_',
    );
    final File source = File('${sandbox.path}${Platform.pathSeparator}main.txt')
      ..writeAsStringSync('original');
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final DateTime originalModified = source.lastModifiedSync();
    source.writeAsStringSync('external change', flush: true);

    await expectLater(
      SourceFileSaver.save(
        source.path,
        Uint8List.fromList('editor change'.codeUnits),
        expectedSize: 8,
        expectedModified: originalModified,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(source.readAsStringSync(), 'external change');
  });
}
