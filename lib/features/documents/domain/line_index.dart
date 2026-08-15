import 'dart:typed_data';

/// 大文本行索引（docs/00 §5.3，DOC-102）。
///
/// 只记录每行起始字节偏移，不保存行内容；按需读取指定行，
/// 因此内存占用与文件大小无关。
class LineIndex {
  LineIndex._(this.offsets, this.totalBytes);

  /// 每行起始字节偏移（第一行固定为 0）。
  final List<int> offsets;

  /// 文件总字节数。
  final int totalBytes;

  int get lineCount => offsets.length;

  /// 从内存字节建立索引（用于测试与小文件）。
  factory LineIndex.fromBytes(List<int> bytes) {
    final List<int> offsets = <int>[0];
    for (int index = 0; index < bytes.length; index++) {
      if (bytes[index] == 0x0A) {
        offsets.add(index + 1);
      }
    }
    return LineIndex._(offsets, bytes.length);
  }

  /// 第 [line] 行起始字节偏移。
  int lineStart(int line) {
    if (line < 0 || line >= offsets.length) {
      throw RangeError.index(line, offsets, 'line');
    }
    return offsets[line];
  }

  /// 第 [line] 行的结束偏移（即下一行起点或文件末尾，含换行符）。
  int lineEnd(int line) {
    if (line < 0 || line >= offsets.length) {
      throw RangeError.index(line, offsets, 'line');
    }
    return line + 1 < offsets.length ? offsets[line + 1] : totalBytes;
  }
}

/// 读取第 [line] 行的原始字节，并去掉结尾的 `\n`/`\r`。
Uint8List readLineBytes(Uint8List source, LineIndex index, int line) {
  final int start = index.lineStart(line);
  int end = index.lineEnd(line);
  while (end > start && (source[end - 1] == 0x0A || source[end - 1] == 0x0D)) {
    end--;
  }
  return Uint8List.sublistView(source, start, end);
}
