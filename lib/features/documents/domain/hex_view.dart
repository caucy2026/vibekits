import 'dart:typed_data';

/// 十六进制视图与字节解释（docs/00 §5.5，DOC-301～DOC-305）。
abstract final class HexView {
  /// 生成一行 Hex/ASCII 文本。
  ///
  /// 返回 `偏移(16位hex)  十六进制字节（分组）  ASCII`。
  static String formatLine({
    required int offset,
    required Uint8List bytes,
    int bytesPerLine = 16,
  }) {
    final StringBuffer hex = StringBuffer();
    final StringBuffer ascii = StringBuffer();
    for (int index = 0; index < bytesPerLine; index++) {
      if (index < bytes.length) {
        final int byte = bytes[index];
        hex.write(byte.toRadixString(16).padLeft(2, '0').toUpperCase());
        ascii.write(
          byte >= 0x20 && byte <= 0x7E ? String.fromCharCode(byte) : '.',
        );
      } else {
        hex.write('  ');
        ascii.write(' ');
      }
      if (index == 7) {
        hex.write(' ');
      }
      if (index != bytesPerLine - 1) {
        hex.write(' ');
      }
    }
    final String offsetText = offset.toRadixString(16).padLeft(16, '0');
    return '$offsetText  $hex  $ascii';
  }

  /// 解释 [data] 中从 [start] 开始 [length] 字节的值。
  static String interpret({
    required ByteData data,
    required int start,
    required int length,
    required Endian endian,
    required bool signed,
    required bool floating,
  }) {
    try {
      if (floating) {
        if (length == 4) {
          return data.getFloat32(start, endian).toString();
        }
        if (length == 8) {
          return data.getFloat64(start, endian).toString();
        }
        return '不支持的长度 $length';
      }
      switch (length) {
        case 1:
          return signed
              ? data.getInt8(start).toString()
              : data.getUint8(start).toString();
        case 2:
          return signed
              ? data.getInt16(start, endian).toString()
              : data.getUint16(start, endian).toString();
        case 4:
          return signed
              ? data.getInt32(start, endian).toString()
              : data.getUint32(start, endian).toString();
        case 8:
          return signed
              ? data.getInt64(start, endian).toString()
              : data.getUint64(start, endian).toString();
        default:
          return '不支持的长度 $length';
      }
    } on RangeError {
      return '超出数据范围';
    }
  }
}

/// 根据文件头识别常见真实类型（DOC-305）。
String? detectMagicNumber(Uint8List bytes) {
  if (bytes.length < 2) {
    return null;
  }
  bool eq(List<int> pattern) {
    if (bytes.length < pattern.length) {
      return false;
    }
    for (int index = 0; index < pattern.length; index++) {
      if (bytes[index] != pattern[index]) {
        return false;
      }
    }
    return true;
  }

  if (eq(const <int>[0x89, 0x50, 0x4E, 0x47])) return 'PNG 图片';
  if (eq(const <int>[0x50, 0x4B, 0x03, 0x04])) return 'ZIP 压缩包';
  if (eq(const <int>[0x7F, 0x45, 0x4C, 0x46])) return 'ELF 可执行文件';
  if (eq(const <int>[0x4D, 0x5A])) return 'Windows 可执行文件 (PE)';
  if (eq(const <int>[0xFF, 0xD8, 0xFF])) return 'JPEG 图片';
  if (eq(const <int>[0x25, 0x50, 0x44, 0x46])) return 'PDF 文档';
  if (eq(const <int>[0x42, 0x4D])) return 'BMP 图片';
  if (eq(const <int>[0x1F, 0x8B])) return 'GZIP 压缩流';
  if (eq(const <int>[0x37, 0x7A, 0xBC, 0xAF])) return '7-Zip 压缩包';
  if (eq(const <int>[0x52, 0x61, 0x72, 0x21])) return 'RAR 压缩包';
  if (eq(const <int>[0x47, 0x49, 0x46, 0x38])) return 'GIF 图片';
  return null;
}
