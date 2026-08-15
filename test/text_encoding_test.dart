import 'dart:convert';
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/documents/domain/text_encoding.dart';

void main() {
  group('编码探测', () {
    test('UTF-8 BOM', () {
      final Uint8List bytes = Uint8List.fromList(<int>[
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('abc'),
      ]);
      expect(TextCodecs.detect(bytes), DocEncoding.utf8);
    });

    test('UTF-16 LE BOM', () {
      final Uint8List bytes = Uint8List.fromList(<int>[0xFF, 0xFE, 0x61, 0x00]);
      expect(TextCodecs.detect(bytes), DocEncoding.utf16le);
    });

    test('UTF-16 BE BOM', () {
      final Uint8List bytes = Uint8List.fromList(<int>[0xFE, 0xFF, 0x00, 0x61]);
      expect(TextCodecs.detect(bytes), DocEncoding.utf16be);
    });

    test('无 BOM 的合法 UTF-8', () {
      expect(
        TextCodecs.detect(Uint8List.fromList(utf8.encode('你好'))),
        DocEncoding.utf8,
      );
    });

    test('GBK 字节回退为 GBK', () {
      final Uint8List bytes = Uint8List.fromList(gbk.encode('中文'));
      expect(TextCodecs.detect(bytes), DocEncoding.gbk);
    });
  });

  group('解码', () {
    test('UTF-8 去 BOM', () {
      final Uint8List bytes = Uint8List.fromList(<int>[
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('abc'),
      ]);
      expect(TextCodecs.decode(bytes, DocEncoding.utf8), 'abc');
    });

    test('UTF-16 LE 去 BOM', () {
      final Uint8List bytes = Uint8List.fromList(<int>[0xFF, 0xFE, 0x61, 0x00]);
      expect(TextCodecs.decode(bytes, DocEncoding.utf16le), 'a');
    });

    test('GBK 往返', () {
      final Uint8List bytes = Uint8List.fromList(gbk.encode('中文测试'));
      expect(TextCodecs.decode(bytes, DocEncoding.gbk), '中文测试');
    });

    test('GBK 解码 UTF-8 中文为乱码时由探测兜底', () {
      // 探测会自动选 GBK，解码应得到原文。
      final Uint8List bytes = Uint8List.fromList(gbk.encode('中文'));
      final DocEncoding encoding = TextCodecs.detect(bytes);
      expect(TextCodecs.decode(bytes, encoding), '中文');
    });
  });
}
