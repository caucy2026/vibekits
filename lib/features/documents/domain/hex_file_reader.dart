import 'dart:io';
import 'dart:typed_data';

class HexFileWindow {
  const HexFileWindow({
    required this.offset,
    required this.fileSize,
    required this.bytes,
  });

  final int offset;
  final int fileSize;
  final Uint8List bytes;
}

/// Bounded random-access reader used by the large binary viewer.
abstract final class HexFileReader {
  static const int defaultWindowBytes = 1024 * 1024;
  static const int maxWindowBytes = 8 * 1024 * 1024;

  static Future<HexFileWindow> readWindow(
    String path, {
    required int offset,
    int length = defaultWindowBytes,
  }) async {
    if (offset < 0) throw const FormatException('偏移不能小于 0');
    if (length < 1 || length > maxWindowBytes) {
      throw const FormatException('读取窗口必须在 1 字节到 8 MiB 之间');
    }
    final File file = File(path);
    final int fileSize = await file.length();
    final int safeOffset = offset.clamp(0, fileSize);
    final RandomAccessFile reader = await file.open();
    try {
      await reader.setPosition(safeOffset);
      return HexFileWindow(
        offset: safeOffset,
        fileSize: fileSize,
        bytes: await reader.read(length.clamp(0, fileSize - safeOffset)),
      );
    } finally {
      await reader.close();
    }
  }

  /// Returns the first byte offset of [pattern], retaining overlap between
  /// bounded reads so a match spanning two chunks is not missed.
  static Future<int?> findFirst(
    String path,
    Uint8List pattern, {
    int start = 0,
    int chunkBytes = defaultWindowBytes,
  }) async {
    if (pattern.isEmpty) throw const FormatException('搜索内容不能为空');
    if (pattern.length > maxWindowBytes) {
      throw const FormatException('搜索内容不能超过 8 MiB');
    }
    if (start < 0) throw const FormatException('起始偏移不能小于 0');
    final int safeChunk = chunkBytes.clamp(pattern.length, maxWindowBytes);
    final File file = File(path);
    final int fileSize = await file.length();
    if (start >= fileSize) return null;
    final RandomAccessFile reader = await file.open();
    Uint8List carry = Uint8List(0);
    int position = start;
    try {
      await reader.setPosition(start);
      while (position < fileSize) {
        final Uint8List next = await reader.read(
          safeChunk.clamp(0, fileSize - position),
        );
        if (next.isEmpty) return null;
        final Uint8List searchable = Uint8List(carry.length + next.length)
          ..setRange(0, carry.length, carry)
          ..setRange(carry.length, carry.length + next.length, next);
        final int index = _indexOf(searchable, pattern);
        if (index >= 0) return position - carry.length + index;
        final int keep = (pattern.length - 1).clamp(0, searchable.length);
        carry = Uint8List.sublistView(searchable, searchable.length - keep);
        position += next.length;
        await Future<void>.delayed(Duration.zero);
      }
      return null;
    } finally {
      await reader.close();
    }
  }

  static int _indexOf(Uint8List source, Uint8List pattern) {
    final int last = source.length - pattern.length;
    for (int start = 0; start <= last; start++) {
      int index = 0;
      while (index < pattern.length &&
          source[start + index] == pattern[index]) {
        index++;
      }
      if (index == pattern.length) return start;
    }
    return -1;
  }
}
