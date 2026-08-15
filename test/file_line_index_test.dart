import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/documents/domain/file_line_index.dart';
import 'package:vibekits/features/documents/domain/text_encoding.dart';

void main() {
  test('流式索引并读行', () async {
    final Directory tmp = Directory.systemTemp.createTempSync('vk_line');
    final File file = File('${tmp.path}/big.log')
      ..writeAsStringSync('line1\nline2\r\nline3');
    try {
      final FileLineIndex index = await FileLineIndex.build(file.path);
      expect(index.lineCount, 3);
      expect(await index.readLine(0, DocEncoding.utf8), 'line1');
      expect(await index.readLine(1, DocEncoding.utf8), 'line2');
      expect(await index.readLine(2, DocEncoding.utf8), 'line3');
    } finally {
      tmp.deleteSync(recursive: true);
    }
  });

  test('文件末尾无换行', () async {
    final Directory tmp = Directory.systemTemp.createTempSync('vk_line2');
    final File file = File('${tmp.path}/a.txt')..writeAsStringSync('x\ny');
    try {
      final FileLineIndex index = await FileLineIndex.build(file.path);
      expect(index.lineCount, 2);
      expect(await index.readLine(1, DocEncoding.utf8), 'y');
    } finally {
      tmp.deleteSync(recursive: true);
    }
  });
}
