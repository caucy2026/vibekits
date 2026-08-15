import 'dart:convert';
import 'dart:typed_data';

import 'tool_result.dart';

/// 编码转换工具，全部离线可用（docs/06 §6.2、§6.4）。
abstract final class EncodingTools {
  static ToolResult base64Encode(String input) {
    return ToolSuccess(base64.encode(utf8.encode(input)));
  }

  static ToolResult base64Decode(String input) {
    try {
      final Uint8List bytes = base64.decode(base64.normalize(input));
      return ToolSuccess(utf8.decode(bytes));
    } on FormatException catch (e) {
      return ToolFailure('Base64 解码失败：${e.message}');
    }
  }

  static ToolResult urlEncode(String input) {
    return ToolSuccess(Uri.encodeComponent(input));
  }

  static ToolResult urlDecode(String input) {
    try {
      return ToolSuccess(Uri.decodeComponent(input));
    } on ArgumentError {
      return const ToolFailure('URL 解码失败：包含无效的百分号编码');
    }
  }

  static const Map<String, String> _htmlEntities = <String, String>{
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;',
  };

  static ToolResult htmlEncode(String input) {
    final StringBuffer buffer = StringBuffer();
    for (final int codeUnit in input.codeUnits) {
      final String char = String.fromCharCode(codeUnit);
      buffer.write(_htmlEntities[char] ?? char);
    }
    return ToolSuccess(buffer.toString());
  }

  static ToolResult htmlDecode(String input) {
    final StringBuffer buffer = StringBuffer();
    int index = 0;
    while (index < input.length) {
      final int amp = input.indexOf('&', index);
      if (amp < 0) {
        buffer.write(input.substring(index));
        break;
      }
      buffer.write(input.substring(index, amp));
      final int semicolon = input.indexOf(';', amp);
      if (semicolon < 0) {
        buffer.write(input.substring(amp));
        break;
      }
      final String entity = input.substring(amp + 1, semicolon);
      final String? decoded = _decodeEntity(entity);
      if (decoded == null) {
        buffer.write(input.substring(amp, semicolon + 1));
      } else {
        buffer.write(decoded);
      }
      index = semicolon + 1;
    }
    return ToolSuccess(buffer.toString());
  }

  static String? _decodeEntity(String entity) {
    switch (entity) {
      case 'amp':
        return '&';
      case 'lt':
        return '<';
      case 'gt':
        return '>';
      case 'quot':
        return '"';
      case 'apos':
        return "'";
      case 'nbsp':
        return '\u00A0';
    }
    if (entity.startsWith('#')) {
      final String body = entity.substring(1);
      try {
        final int codePoint = body.startsWith('x') || body.startsWith('X')
            ? int.parse(body.substring(1), radix: 16)
            : int.parse(body, radix: 10);
        return String.fromCharCode(codePoint);
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  static ToolResult unicodeEscape(String input) {
    final StringBuffer buffer = StringBuffer();
    for (final int rune in input.runes) {
      if (rune <= 0x7F) {
        buffer.writeCharCode(rune);
      } else if (rune <= 0xFFFF) {
        buffer.write('\\u${rune.toRadixString(16).padLeft(4, '0')}');
      } else {
        buffer.write('\\U${rune.toRadixString(16).padLeft(8, '0')}');
      }
    }
    return ToolSuccess(buffer.toString());
  }

  static ToolResult unicodeUnescape(String input) {
    final StringBuffer buffer = StringBuffer();
    int index = 0;
    while (index < input.length) {
      final int slash = input.indexOf('\\', index);
      if (slash < 0) {
        buffer.write(input.substring(index));
        break;
      }
      buffer.write(input.substring(index, slash));
      if (slash + 1 >= input.length) {
        buffer.write('\\');
        index = slash + 1;
        continue;
      }
      final String marker = input[slash + 1];
      if (marker == 'u' && slash + 6 <= input.length) {
        final String hex = input.substring(slash + 2, slash + 6);
        final int? code = int.tryParse(hex, radix: 16);
        if (code != null) {
          buffer.writeCharCode(code);
          index = slash + 6;
          continue;
        }
      }
      if (marker == 'U' && slash + 10 <= input.length) {
        final String hex = input.substring(slash + 2, slash + 10);
        final int? code = int.tryParse(hex, radix: 16);
        if (code != null) {
          buffer.writeCharCode(code);
          index = slash + 10;
          continue;
        }
      }
      buffer.write('\\$marker');
      index = slash + 2;
    }
    return ToolSuccess(buffer.toString());
  }

  static ToolResult hexEncode(String input) {
    final List<int> bytes = utf8.encode(input);
    final StringBuffer buffer = StringBuffer();
    for (final int byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return ToolSuccess(buffer.toString());
  }

  static ToolResult hexDecode(String input) {
    final String normalized = input.replaceAll(RegExp(r'\s+'), '');
    if (normalized.length.isOdd) {
      return const ToolFailure('Hex 解码失败：十六进制字符数量必须为偶数');
    }
    final List<int> bytes = <int>[];
    for (int index = 0; index < normalized.length; index += 2) {
      final int? byte = int.tryParse(
        normalized.substring(index, index + 2),
        radix: 16,
      );
      if (byte == null) {
        return ToolFailure(
          'Hex 解码失败：第 ${index ~/ 2 + 1} 个字节不是有效的十六进制',
          position: index,
        );
      }
      bytes.add(byte);
    }
    return ToolSuccess(utf8.decode(bytes));
  }

  static ToolResult baseConvert(String input, String fromBase, String toBase) {
    final int? from = int.tryParse(fromBase);
    final int? to = int.tryParse(toBase);
    if (from == null || to == null) {
      return const ToolFailure('进制转换失败：进制必须是 2～36 的整数');
    }
    if (from < 2 || from > 36 || to < 2 || to > 36) {
      return const ToolFailure('进制转换失败：进制必须是 2～36 的整数');
    }
    final int? value = int.tryParse(input.trim(), radix: from);
    if (value == null) {
      return const ToolFailure('进制转换失败：输入不是有效的进制整数');
    }
    return ToolSuccess(value.toRadixString(to));
  }
}
