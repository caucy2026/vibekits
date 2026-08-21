import 'dart:convert';

import 'package:xml/xml.dart';

import 'tool_result.dart';

/// Thirty small, deterministic developer operations inspired by the task
/// coverage of DevToys, CyberChef and Hexkit. All operations are local and
/// bounded so the UI and Harness share the exact same implementation.
abstract final class UtilityPlusTools {
  static const int _maxInput = 1024 * 1024;

  static ToolResult jsonMinify(String input) => _guard(input, () {
    return jsonEncode(jsonDecode(input));
  });

  static ToolResult jsonEscape(String input) =>
      _guard(input, () => jsonEncode(input));

  static ToolResult jsonUnescape(String input) => _guard(input, () {
    final Object? value = jsonDecode(input);
    if (value is! String) throw const FormatException('输入必须是 JSON 字符串');
    return value;
  });

  static ToolResult xmlFormat(String input) => _guard(input, () {
    return XmlDocument.parse(input).toXmlString(pretty: true, indent: '  ');
  });

  static ToolResult xmlMinify(String input) => _guard(input, () {
    return XmlDocument.parse(input).toXmlString(pretty: false);
  });

  static ToolResult csvToJson(String input) => _guard(input, () {
    final List<List<String>> rows = _parseCsv(input);
    if (rows.isEmpty) return '[]';
    final List<String> headers = rows.first;
    if (headers.isEmpty ||
        headers.any((String value) => value.trim().isEmpty)) {
      throw const FormatException('CSV 表头不能为空');
    }
    final List<Map<String, String>> result = <Map<String, String>>[];
    for (final List<String> row in rows.skip(1)) {
      result.add(<String, String>{
        for (int index = 0; index < headers.length; index++)
          headers[index]: index < row.length ? row[index] : '',
      });
    }
    return const JsonEncoder.withIndent('  ').convert(result);
  });

  static ToolResult jsonToCsv(String input) => _guard(input, () {
    final Object? decoded = jsonDecode(input);
    if (decoded is! List || decoded.any((Object? item) => item is! Map)) {
      throw const FormatException('输入必须是 JSON 对象数组');
    }
    final List<String> headers = <String>[];
    for (final Object? item in decoded) {
      for (final Object? key in (item! as Map).keys) {
        final String text = '$key';
        if (!headers.contains(text)) headers.add(text);
      }
    }
    final List<String> lines = <String>[_csvRow(headers)];
    for (final Object? item in decoded) {
      final Map<Object?, Object?> row = item! as Map<Object?, Object?>;
      lines.add(
        _csvRow(headers.map((String key) => '${row[key] ?? ''}').toList()),
      );
    }
    return lines.join('\n');
  });

  static ToolResult jwtDecode(String input) => _guard(input, () {
    final List<String> parts = input.trim().split('.');
    if (parts.length != 3) throw const FormatException('JWT 必须包含三段');
    final Object? header = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))),
    );
    final Object? payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'header': header,
      'payload': payload,
      'signatureVerified': false,
      'warning': '仅解码，未验证签名',
    });
  });

  static ToolResult jwtExpiry(String input) => _guard(input, () {
    final List<String> parts = input.trim().split('.');
    if (parts.length != 3) throw const FormatException('JWT 必须包含三段');
    final Object? payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (payload is! Map || payload['exp'] is! num) {
      throw const FormatException('JWT payload 不包含数字 exp');
    }
    final int exp = (payload['exp'] as num).toInt();
    final int now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    return jsonEncode(<String, Object?>{
      'expiresAtUtc': DateTime.fromMillisecondsSinceEpoch(
        exp * 1000,
        isUtc: true,
      ).toIso8601String(),
      'expired': exp <= now,
      'remainingSeconds': exp - now,
      'signatureVerified': false,
    });
  });

  static ToolResult numberBaseConvert(String input, String params) => _guard(
    input,
    () {
      final List<String> options = params.split('|');
      final int from = int.tryParse(options.isNotEmpty ? options[0] : '') ?? 10;
      final int to = int.tryParse(options.length > 1 ? options[1] : '') ?? 16;
      if (from < 2 || from > 36 || to < 2 || to > 36) {
        throw const FormatException('进制范围必须为 2～36');
      }
      return BigInt.parse(
        input.trim(),
        radix: from,
      ).toRadixString(to).toUpperCase();
    },
  );

  static ToolResult endianSwap(String input) => _guard(input, () {
    final String hex = input.replaceAll(
      RegExp(r'\s+|0x', caseSensitive: false),
      '',
    );
    if (hex.isEmpty ||
        hex.length.isOdd ||
        !RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) {
      throw const FormatException('请输入偶数位十六进制字节');
    }
    final List<String> bytes = <String>[
      for (int i = 0; i < hex.length; i += 2) hex.substring(i, i + 2),
    ];
    return bytes.reversed.join(' ').toUpperCase();
  });

  static ToolResult asciiInspect(String input) => _guard(input, () {
    final List<String> rows = <String>[];
    for (final int rune in input.runes.take(256)) {
      rows.add(
        'U+${rune.toRadixString(16).padLeft(4, '0').toUpperCase()}\t$rune\t${String.fromCharCode(rune)}',
      );
    }
    return 'Unicode\tDecimal\tCharacter\n${rows.join('\n')}';
  });

  static ToolResult chmodDecode(String input) => _guard(input, () {
    String value = input.trim();
    if (value.length == 4) value = value.substring(1);
    if (!RegExp(r'^[0-7]{3}$').hasMatch(value)) {
      throw const FormatException('请输入三位或四位八进制权限');
    }
    const List<String> triplets = <String>[
      '---',
      '--x',
      '-w-',
      '-wx',
      'r--',
      'r-x',
      'rw-',
      'rwx',
    ];
    return value
        .split('')
        .map((String digit) => triplets[int.parse(digit)])
        .join();
  });

  static ToolResult chmodEncode(String input) => _guard(input, () {
    final String value = input.trim();
    if (!RegExp(r'^[r-][w-][x-][r-][w-][x-][r-][w-][x-]$').hasMatch(value)) {
      throw const FormatException('请输入九位符号权限，例如 rwxr-xr--');
    }
    int digit(String part) =>
        (part[0] == 'r' ? 4 : 0) +
        (part[1] == 'w' ? 2 : 0) +
        (part[2] == 'x' ? 1 : 0);
    return '${digit(value.substring(0, 3))}${digit(value.substring(3, 6))}${digit(value.substring(6, 9))}';
  });

  static ToolResult semverCompare(String input, String params) =>
      _guard(input, () {
        final String right = params.trim();
        if (right.isEmpty) throw const FormatException('参数请输入另一个版本号');
        final int comparison = _compareSemver(input.trim(), right);
        return comparison == 0
            ? 'equal'
            : comparison < 0
            ? 'less'
            : 'greater';
      });

  static ToolResult bytesConvert(String input, String params) =>
      _unitConvert(input, params, const <String, double>{
        'b': 1,
        'kb': 1000,
        'mb': 1000000,
        'gb': 1000000000,
        'kib': 1024,
        'mib': 1048576,
        'gib': 1073741824,
      });

  static ToolResult durationConvert(String input, String params) =>
      _unitConvert(input, params, const <String, double>{
        'ms': 0.001,
        's': 1,
        'm': 60,
        'h': 3600,
        'd': 86400,
      });

  static ToolResult hexToRgb(String input) => _guard(input, () {
    String value = input.trim().replaceFirst('#', '');
    if (value.length == 3) {
      value = value.split('').map((String c) => '$c$c').join();
    }
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(value)) {
      throw const FormatException('请输入 #RGB 或 #RRGGBB');
    }
    return jsonEncode(<String, int>{
      'r': int.parse(value.substring(0, 2), radix: 16),
      'g': int.parse(value.substring(2, 4), radix: 16),
      'b': int.parse(value.substring(4, 6), radix: 16),
    });
  });

  static ToolResult rgbToHex(String input) => _guard(input, () {
    final List<int> values = input
        .split(RegExp(r'[,\s]+'))
        .where((String v) => v.isNotEmpty)
        .map(int.parse)
        .toList();
    if (values.length != 3 ||
        values.any((int value) => value < 0 || value > 255)) {
      throw const FormatException('请输入 0～255 的 R,G,B');
    }
    return '#${values.map((int value) => value.toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';
  });

  static ToolResult queryParse(String input) => _guard(input, () {
    String value = input.trim();
    if (value.startsWith('?')) value = value.substring(1);
    final Map<String, List<String>> result = <String, List<String>>{};
    for (final String pair
        in value.split('&').where((String item) => item.isNotEmpty)) {
      final int separator = pair.indexOf('=');
      final String key = Uri.decodeQueryComponent(
        separator < 0 ? pair : pair.substring(0, separator),
      );
      final String item = Uri.decodeQueryComponent(
        separator < 0 ? '' : pair.substring(separator + 1),
      );
      result.putIfAbsent(key, () => <String>[]).add(item);
    }
    return const JsonEncoder.withIndent('  ').convert(result);
  });

  static ToolResult queryBuild(String input) => _guard(input, () {
    final Object? value = jsonDecode(input);
    if (value is! Map) throw const FormatException('请输入 JSON 对象');
    final List<String> pairs = <String>[];
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      final Iterable<Object?> values = entry.value is List
          ? entry.value as List
          : <Object?>[entry.value];
      for (final Object? item in values) {
        pairs.add(
          '${Uri.encodeQueryComponent('${entry.key}')}=${Uri.encodeQueryComponent('${item ?? ''}')}',
        );
      }
    }
    return pairs.join('&');
  });

  static ToolResult regexEscape(String input) =>
      _guard(input, () => RegExp.escape(input));

  static ToolResult globTest(String input, String params) => _guard(input, () {
    if (params.trim().isEmpty) throw const FormatException('参数请输入 glob');
    final StringBuffer regex = StringBuffer('^');
    for (int index = 0; index < params.length; index++) {
      final String c = params[index];
      if (c == '*') {
        final bool double =
            index + 1 < params.length && params[index + 1] == '*';
        regex.write(double ? '.*' : r'[^/\\]*');
        if (double) index++;
      } else if (c == '?') {
        regex.write(r'[^/\\]');
      } else {
        regex.write(RegExp.escape(c));
      }
    }
    regex.write(r'$');
    return RegExp(regex.toString()).hasMatch(input.trim())
        ? 'match'
        : 'no match';
  });

  static ToolResult lineSort(String input, String params) => _guard(input, () {
    final List<String> lines = const LineSplitter().convert(input)..sort();
    if (params.trim().toLowerCase() == 'desc') return lines.reversed.join('\n');
    return lines.join('\n');
  });

  static ToolResult lineUnique(String input) => _guard(input, () {
    final Set<String> seen = <String>{};
    return const LineSplitter().convert(input).where(seen.add).join('\n');
  });

  static ToolResult textStatistics(String input) => _guard(input, () {
    final int words = RegExp(r'\S+').allMatches(input).length;
    final int lines = input.isEmpty
        ? 0
        : const LineSplitter().convert(input).length;
    return jsonEncode(<String, int>{
      'characters': input.runes.length,
      'utf8Bytes': utf8.encode(input).length,
      'words': words,
      'lines': lines,
    });
  });

  static ToolResult caseConvert(String input, String params) => _guard(
    input,
    () {
      final List<String> words = input
          .trim()
          .split(RegExp(r'[^A-Za-z0-9]+|(?<=[a-z0-9])(?=[A-Z])'))
          .where((String word) => word.isNotEmpty)
          .map((String word) => word.toLowerCase())
          .toList();
      String cap(String word) =>
          word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}';
      return switch (params.trim().toLowerCase()) {
        'upper' => input.toUpperCase(),
        'lower' => input.toLowerCase(),
        'snake' => words.join('_'),
        'kebab' => words.join('-'),
        'camel' =>
          words.isEmpty ? '' : '${words.first}${words.skip(1).map(cap).join()}',
        'pascal' => words.map(cap).join(),
        'title' => words.map(cap).join(' '),
        _ => throw const FormatException(
          '参数应为 upper/lower/snake/kebab/camel/pascal/title',
        ),
      };
    },
  );

  static ToolResult normalizeLineEndings(String input, String params) =>
      _guard(input, () {
        final String normalized = input
            .replaceAll('\r\n', '\n')
            .replaceAll('\r', '\n');
        return params.trim().toLowerCase() == 'crlf'
            ? normalized.replaceAll('\n', '\r\n')
            : normalized;
      });

  static ToolResult httpStatusLookup(String input) => _guard(input, () {
    final int? status = int.tryParse(input.trim());
    const Map<int, String> names = <int, String>{
      200: 'OK',
      201: 'Created',
      204: 'No Content',
      301: 'Moved Permanently',
      302: 'Found',
      304: 'Not Modified',
      400: 'Bad Request',
      401: 'Unauthorized',
      403: 'Forbidden',
      404: 'Not Found',
      409: 'Conflict',
      418: "I'm a teapot",
      422: 'Unprocessable Content',
      429: 'Too Many Requests',
      500: 'Internal Server Error',
      502: 'Bad Gateway',
      503: 'Service Unavailable',
      504: 'Gateway Timeout',
    };
    if (status == null || status < 100 || status > 599) {
      throw const FormatException('请输入 100～599 的 HTTP 状态码');
    }
    return '${names[status] ?? 'Unknown'} (${status ~/ 100}xx)';
  });

  static ToolResult mimeLookup(String input) => _guard(input, () {
    final String value = input.trim().toLowerCase();
    final String extension = value.contains('.')
        ? value.substring(value.lastIndexOf('.'))
        : value.startsWith('.')
        ? value
        : '.$value';
    const Map<String, String> types = <String, String>{
      '.json': 'application/json',
      '.xml': 'application/xml',
      '.yaml': 'application/yaml',
      '.yml': 'application/yaml',
      '.html': 'text/html',
      '.css': 'text/css',
      '.js': 'text/javascript',
      '.mjs': 'text/javascript',
      '.ts': 'text/typescript',
      '.txt': 'text/plain',
      '.md': 'text/markdown',
      '.csv': 'text/csv',
      '.pdf': 'application/pdf',
      '.zip': 'application/zip',
      '.7z': 'application/x-7z-compressed',
      '.gz': 'application/gzip',
      '.png': 'image/png',
      '.jpg': 'image/jpeg',
      '.jpeg': 'image/jpeg',
      '.webp': 'image/webp',
      '.svg': 'image/svg+xml',
      '.wasm': 'application/wasm',
      '.bin': 'application/octet-stream',
    };
    return types[extension] ?? 'application/octet-stream';
  });

  static ToolResult _unitConvert(
    String input,
    String params,
    Map<String, double> units,
  ) {
    return _guard(input, () {
      final List<String> options = params.toLowerCase().split('|');
      if (options.length != 2 ||
          !units.containsKey(options[0]) ||
          !units.containsKey(options[1])) {
        throw FormatException('参数应为 from|to，可用：${units.keys.join(', ')}');
      }
      final double? value = double.tryParse(input.trim());
      if (value == null || !value.isFinite) {
        throw const FormatException('请输入有限数字');
      }
      final double output = value * units[options[0]]! / units[options[1]]!;
      return output.toStringAsPrecision(12).replaceFirst(RegExp(r'\.?0+$'), '');
    });
  }

  static ToolResult _guard(String input, String Function() operation) {
    if (input.length > _maxInput) return const ToolFailure('输入超过 1 MiB 上限');
    try {
      return ToolSuccess(operation());
    } on FormatException catch (error) {
      return ToolFailure(error.message, position: error.offset);
    } on Object catch (error) {
      return ToolFailure('处理失败：$error');
    }
  }

  static List<List<String>> _parseCsv(String input) {
    final List<List<String>> rows = <List<String>>[];
    List<String> row = <String>[];
    final StringBuffer field = StringBuffer();
    bool quoted = false;
    for (int index = 0; index < input.length; index++) {
      final String c = input[index];
      if (c == '"') {
        if (quoted && index + 1 < input.length && input[index + 1] == '"') {
          field.write('"');
          index++;
        } else {
          quoted = !quoted;
        }
      } else if (c == ',' && !quoted) {
        row.add(field.toString());
        field.clear();
      } else if ((c == '\n' || c == '\r') && !quoted) {
        if (c == '\r' && index + 1 < input.length && input[index + 1] == '\n') {
          index++;
        }
        row.add(field.toString());
        field.clear();
        rows.add(row);
        row = <String>[];
      } else {
        field.write(c);
      }
    }
    if (quoted) throw const FormatException('CSV 引号未闭合');
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }
    return rows;
  }

  static String _csvRow(List<String> values) => values
      .map((String value) {
        if (value.contains(',') ||
            value.contains('"') ||
            value.contains('\n')) {
          return '"${value.replaceAll('"', '""')}"';
        }
        return value;
      })
      .join(',');

  static int _compareSemver(String left, String right) {
    List<Object> parse(String value) {
      final Match? match = RegExp(
        r'^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
      ).firstMatch(value);
      if (match == null) throw FormatException('无效语义版本：$value');
      return <Object>[
        int.parse(match[1]!),
        int.parse(match[2]!),
        int.parse(match[3]!),
        match[4] ?? '',
      ];
    }

    final List<Object> a = parse(left);
    final List<Object> b = parse(right);
    for (int index = 0; index < 3; index++) {
      final int compared = (a[index] as int).compareTo(b[index] as int);
      if (compared != 0) return compared;
    }
    final String ap = a[3] as String;
    final String bp = b[3] as String;
    if (ap.isEmpty || bp.isEmpty) {
      return ap.isEmpty == bp.isEmpty
          ? 0
          : ap.isEmpty
          ? 1
          : -1;
    }
    final List<String> ai = ap.split('.');
    final List<String> bi = bp.split('.');
    for (int index = 0; index < ai.length || index < bi.length; index++) {
      if (index >= ai.length) return -1;
      if (index >= bi.length) return 1;
      final int? an = int.tryParse(ai[index]);
      final int? bn = int.tryParse(bi[index]);
      final int compared = an != null && bn != null
          ? an.compareTo(bn)
          : an != null
          ? -1
          : bn != null
          ? 1
          : ai[index].compareTo(bi[index]);
      if (compared != 0) return compared;
    }
    return 0;
  }
}
