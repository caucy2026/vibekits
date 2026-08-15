import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/documents/domain/hex_view.dart';

void main() {
  test('formatLine 输出三栏且偏移为 16 位 hex', () {
    final Uint8List bytes = Uint8List.fromList(<int>[
      0x50,
      0x4B,
      0x03,
      0x04,
      0x14,
      0x00,
      0x08,
      0x00,
      0x08,
      0x00,
      0x7A,
      0x53,
      0x2F,
      0x5B,
      0x00,
      0x00,
    ]);
    final String line = HexView.formatLine(offset: 0, bytes: bytes);
    expect(line.startsWith('0000000000000000  '), isTrue);
    expect(line.contains('50 4B 03 04 14 00 08 00'), isTrue);
    expect(line.contains('PK'), isTrue);
  });

  test('不足一行的字节用空格补齐', () {
    final Uint8List bytes = Uint8List.fromList(<int>[0x41]);
    final String line = HexView.formatLine(offset: 0, bytes: bytes);
    expect(line.contains('41'), isTrue);
    expect(line.contains('A'), isTrue);
  });

  test('大小端解释整数', () {
    final ByteData data = ByteData(4)..setUint32(0, 0x12345678, Endian.little);
    expect(
      HexView.interpret(
        data: data,
        start: 0,
        length: 4,
        endian: Endian.little,
        signed: false,
        floating: false,
      ),
      '305419896', // 0x12345678 十进制
    );
    expect(
      HexView.interpret(
        data: data,
        start: 0,
        length: 4,
        endian: Endian.big,
        signed: false,
        floating: false,
      ),
      '2018915346', // 0x78563412 十进制
    );
  });

  test('解释浮点', () {
    final ByteData data = ByteData(4)..setFloat32(0, 1.0, Endian.little);
    final String value = HexView.interpret(
      data: data,
      start: 0,
      length: 4,
      endian: Endian.little,
      signed: false,
      floating: true,
    );
    expect(double.parse(value), 1.0);
  });

  test('Magic Number 识别', () {
    expect(
      detectMagicNumber(Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47])),
      'PNG 图片',
    );
    expect(
      detectMagicNumber(Uint8List.fromList(<int>[0x50, 0x4B, 0x03, 0x04])),
      'ZIP 压缩包',
    );
    expect(
      detectMagicNumber(Uint8List.fromList(<int>[0x4D, 0x5A])),
      'Windows 可执行文件 (PE)',
    );
    expect(detectMagicNumber(Uint8List.fromList(<int>[0x00, 0x01])), isNull);
  });
}
