import 'dart:typed_data';

import 'package:archive/archive.dart';

/// SVG/SVGZ 安全渲染输入（docs/00 §5.4，DOC-204）。
abstract final class SvgSource {
  static const int _maxExpandedBytes = 8 * 1024 * 1024;

  /// 从文件字节得到 SVG 文本；`.svgz` 先受限解压。
  static String decode(Uint8List bytes, {required bool compressed}) {
    final Uint8List raw = compressed ? _gunzip(bytes) : bytes;
    if (raw.length > _maxExpandedBytes) {
      throw const FormatException('SVG 展开后超过大小上限');
    }
    return String.fromCharCodes(raw);
  }

  static Uint8List _gunzip(Uint8List bytes) {
    final Uint8List decompressed = GZipDecoder().decodeBytes(bytes);
    if (decompressed.length > _maxExpandedBytes) {
      throw const FormatException('SVGZ 展开后超过大小上限');
    }
    return decompressed;
  }
}
