import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/archive/domain/seven_zip.dart';

void main() {
  test('7z 创建、列表、解压闭环', () async {
    final String? exe = SevenZip.findExecutable();
    if (exe == null) {
      return; // 无 7za 时跳过
    }
    final Directory tmp = Directory.systemTemp.createTempSync('vk_7z');
    File('${tmp.path}/a.txt').writeAsStringSync('hello 7z');
    try {
      final ProcessResult create = await Process.run(exe, <String>[
        'a',
        't.7z',
        'a.txt',
        '-y',
      ], workingDirectory: tmp.path);
      expect(create.exitCode, 0, reason: '${create.stderr}');

      final List<SevenZipEntry> entries = await SevenZip.list(
        '${tmp.path}/t.7z',
      );
      expect(
        entries.any((SevenZipEntry e) => e.name.endsWith('a.txt')),
        isTrue,
      );

      final String out = '${tmp.path}/out';
      await SevenZip.extract('${tmp.path}/t.7z', out);
      expect(File('$out/a.txt').readAsStringSync(), 'hello 7z');
    } finally {
      tmp.deleteSync(recursive: true);
    }
  });
}
