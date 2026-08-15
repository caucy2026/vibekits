import 'dart:convert';
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';

import 'native_codec.dart';

/// 文档支持的字符编码（docs/00 §5.3，DOC-101）。
enum DocEncoding {
  utf8('UTF-8'),
  utf16le('UTF-16 LE'),
  utf16be('UTF-16 BE'),
  gbk('GBK'),
  gb18030('GB18030'),
  big5('Big5');

  const DocEncoding(this.label);

  final String label;
}

/// 编码探测与解码（BOM → 严格 UTF-8 → GBK 兜底）。
abstract final class TextCodecs {
  /// 探测编码：优先 BOM，其次严格 UTF-8，否则按常见中文文本回退 GBK。
  static DocEncoding detect(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return DocEncoding.utf8;
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return DocEncoding.utf16le;
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return DocEncoding.utf16be;
    }
    if (isValidUtf8(bytes)) {
      return DocEncoding.utf8;
    }
    return DocEncoding.gbk;
  }

  static bool isValidUtf8(Uint8List bytes) {
    try {
      utf8.decode(bytes);
      return true;
    } on FormatException {
      return false;
    }
  }

  /// 去除与 [encoding] 对应的 BOM 字节。
  static Uint8List stripBom(Uint8List bytes, DocEncoding encoding) {
    switch (encoding) {
      case DocEncoding.utf8:
        if (bytes.length >= 3 &&
            bytes[0] == 0xEF &&
            bytes[1] == 0xBB &&
            bytes[2] == 0xBF) {
          return bytes.sublist(3);
        }
        return bytes;
      case DocEncoding.utf16le:
        if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
          return bytes.sublist(2);
        }
        return bytes;
      case DocEncoding.utf16be:
        if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
          return bytes.sublist(2);
        }
        return bytes;
      case DocEncoding.gbk:
      case DocEncoding.gb18030:
      case DocEncoding.big5:
        return bytes;
    }
  }

  static String decode(Uint8List bytes, DocEncoding encoding) {
    switch (encoding) {
      case DocEncoding.utf8:
        return utf8.decode(stripBom(bytes, DocEncoding.utf8));
      case DocEncoding.utf16le:
        return _decodeUtf16(stripBom(bytes, DocEncoding.utf16le), true);
      case DocEncoding.utf16be:
        return _decodeUtf16(stripBom(bytes, DocEncoding.utf16be), false);
      case DocEncoding.gbk:
        return gbk.decode(bytes);
      case DocEncoding.gb18030:
        return NativeCodec.decodeGb18030(bytes);
      case DocEncoding.big5:
        return NativeCodec.decodeBig5(bytes);
    }
  }

  static String _decodeUtf16(Uint8List bytes, bool littleEndian) {
    if (bytes.length.isOdd) {
      throw const FormatException('UTF-16 字节长度必须为偶数');
    }
    final ByteData data = ByteData.sublistView(bytes);
    final StringBuffer buffer = StringBuffer();
    for (int index = 0; index < bytes.length; index += 2) {
      final int unit = data.getUint16(
        index,
        littleEndian ? Endian.little : Endian.big,
      );
      buffer.writeCharCode(unit);
    }
    return buffer.toString();
  }
}
