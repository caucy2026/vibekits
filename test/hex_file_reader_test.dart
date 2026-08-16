import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/documents/domain/hex_file_reader.dart';

void main() {
  test('2GB 以上文件按 64 位偏移读取固定窗口', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_large_hex',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final File file = File('${sandbox.path}${Platform.pathSeparator}large.bin');
    final RandomAccessFile writer = file.openSync(mode: FileMode.write);
    const int markerOffset = 2 * 1024 * 1024 * 1024 + 123;
    writer
      ..setPositionSync(markerOffset)
      ..writeFromSync(<int>[0xDE, 0xAD, 0xBE, 0xEF])
      ..closeSync();

    final HexFileWindow window = await HexFileReader.readWindow(
      file.path,
      offset: markerOffset - 2,
      length: 8,
    );

    expect(window.fileSize, markerOffset + 4);
    expect(window.offset, markerOffset - 2);
    expect(
      window.bytes.skip(2).take(4),
      orderedEquals(<int>[0xDE, 0xAD, 0xBE, 0xEF]),
    );
  });

  test('搜索不会漏掉跨读取块的字节序列', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_hex_search',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final File file = File('${sandbox.path}${Platform.pathSeparator}cross.bin')
      ..writeAsBytesSync(<int>[
        ...List<int>.filled(14, 0),
        0x56,
        0x49,
        0x42,
        0x45,
        0x4b,
        0x49,
        0x54,
        0x53,
      ]);

    final int? offset = await HexFileReader.findFirst(
      file.path,
      Uint8List.fromList('VIBEKITS'.codeUnits),
      chunkBytes: 16,
    );

    expect(offset, 14);
  });
}
