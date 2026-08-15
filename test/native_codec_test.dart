import 'dart:io';
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/documents/domain/text_encoding.dart';

void main() {
  test('GB18030 解码 GBK 兼容字节', () {
    if (!Platform.isWindows) return;
    final Uint8List bytes = Uint8List.fromList(gbk.encode('中文'));
    expect(TextCodecs.decode(bytes, DocEncoding.gb18030), '中文');
  });

  test('Big5 解码', () {
    if (!Platform.isWindows) return;
    // Big5 中 = 0xA4 0xA4
    final Uint8List bytes = Uint8List.fromList(<int>[0xA4, 0xA4]);
    expect(TextCodecs.decode(bytes, DocEncoding.big5), '中');
  });
}
