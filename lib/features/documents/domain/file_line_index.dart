import 'dart:io';
import 'dart:typed_data';

import 'text_encoding.dart';

/// 大文件行索引：按块扫描换行记录偏移，不把文件读入内存（DOC-102/304）。
class FileLineIndex {
  FileLineIndex._(this.path, this.offsets, this.fileSize);

  final String path;
  final List<int> offsets;
  final int fileSize;

  int get lineCount => offsets.length;

  /// 建立索引（流式扫描）。
  static Future<FileLineIndex> build(String path) async {
    final RandomAccessFile raf = File(path).openSync();
    final List<int> offsets = <int>[0];
    final Uint8List buffer = Uint8List(64 * 1024);
    int position = 0;
    try {
      while (true) {
        final int read = raf.readIntoSync(buffer);
        if (read <= 0) break;
        for (int index = 0; index < read; index++) {
          if (buffer[index] == 0x0A) {
            offsets.add(position + index + 1);
          }
        }
        position += read;
      }
    } finally {
      raf.closeSync();
    }
    return FileLineIndex._(path, offsets, File(path).lengthSync());
  }

  /// 读取第 [line] 行并按 [encoding] 解码（去掉尾部换行）。
  Future<String> readLine(int line, DocEncoding encoding) async {
    if (line < 0 || line >= offsets.length) {
      throw RangeError.index(line, offsets, 'line');
    }
    final int start = offsets[line];
    final int end = line + 1 < offsets.length ? offsets[line + 1] : fileSize;
    final int length = end - start;
    final RandomAccessFile raf = File(path).openSync();
    final Uint8List buffer = Uint8List(length);
    try {
      raf.setPositionSync(start);
      raf.readIntoSync(buffer);
    } finally {
      raf.closeSync();
    }
    int usable = length;
    while (usable > 0 &&
        (buffer[usable - 1] == 0x0A || buffer[usable - 1] == 0x0D)) {
      usable--;
    }
    return TextCodecs.decode(
      Uint8List.sublistView(buffer, 0, usable),
      encoding,
    );
  }
}
