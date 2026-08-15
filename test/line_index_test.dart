import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/documents/domain/line_index.dart';

void main() {
  test('按换行建立索引', () {
    final Uint8List bytes = Uint8List.fromList(utf8.encode('a\nbb\nccc'));
    final LineIndex index = LineIndex.fromBytes(bytes);
    expect(index.lineCount, 3);
    expect(index.lineStart(0), 0);
    expect(index.lineStart(1), 2);
    expect(index.lineStart(2), 5);
    expect(index.lineEnd(2), bytes.length);
  });

  test('readLineBytes 去掉换行与回车', () {
    final Uint8List bytes = Uint8List.fromList(utf8.encode('a\r\nb\n'));
    final LineIndex index = LineIndex.fromBytes(bytes);
    expect(utf8.decode(readLineBytes(bytes, index, 0)), 'a');
    expect(utf8.decode(readLineBytes(bytes, index, 1)), 'b');
  });

  test('文件末尾无换行时最后一行完整', () {
    final Uint8List bytes = Uint8List.fromList(utf8.encode('x\ny'));
    final LineIndex index = LineIndex.fromBytes(bytes);
    expect(utf8.decode(readLineBytes(bytes, index, 1)), 'y');
  });

  test('空文件只有一行', () {
    final Uint8List bytes = Uint8List.fromList(const <int>[]);
    final LineIndex index = LineIndex.fromBytes(bytes);
    expect(index.lineCount, 1);
    expect(readLineBytes(bytes, index, 0).isEmpty, isTrue);
  });
}
