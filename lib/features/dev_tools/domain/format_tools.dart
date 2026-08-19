import 'dart:convert';

import 'structured_data_parser.dart';
import 'tool_result.dart';

/// 格式处理工具，全部离线可用。
abstract final class FormatTools {
  /// 格式化 JSON；非法输入返回失败并给出偏移。
  static ToolResult jsonFormat(String input) {
    try {
      final Object? value = jsonDecode(input);
      return ToolSuccess(const JsonEncoder.withIndent('  ').convert(value));
    } on FormatException catch (e) {
      return ToolFailure('JSON 解析失败：${e.message}', position: e.offset);
    }
  }

  /// 校验 JSON，成功时返回顶层类型。
  static ToolResult jsonValidate(String input) {
    try {
      final Object? value = jsonDecode(input);
      final String type = switch (value) {
        null => 'null',
        Map<Object?, Object?>() => '对象 (object)',
        List<Object?>() => '数组 (array)',
        String() => '字符串 (string)',
        int() || double() => '数字 (number)',
        bool() => '布尔 (boolean)',
        _ => '未知类型',
      };
      return ToolSuccess('有效 JSON，顶层类型：$type');
    } on FormatException catch (e) {
      return ToolFailure('JSON 校验失败：${e.message}', position: e.offset);
    }
  }

  /// 安全的 JSON 点路径查询。只读取，不支持表达式执行或写入。
  static ToolResult jsonQuery(String input, String query) {
    return structuredQuery(input, query);
  }

  /// 查询 JSON/YAML/TOML/XML。参数可为 `.path` 或 `format|.path`。
  static ToolResult structuredQuery(String input, String query) {
    try {
      String format = 'auto';
      String path = query.trim();
      final int separator = path.indexOf('|');
      if (separator >= 0) {
        format = path.substring(0, separator).trim();
        path = path.substring(separator + 1).trim();
      }
      final Object? root = StructuredDataParser.parse(input, format);
      final List<Object> tokens = _jsonPathTokens(path);
      List<Object?> values = <Object?>[root];
      for (final Object token in tokens) {
        final List<Object?> next = <Object?>[];
        for (final Object? value in values) {
          if (token == '*') {
            if (value is List) next.addAll(value);
            if (value is Map) next.addAll(value.values);
          } else if (token is int && value is List) {
            if (token < 0 || token >= value.length) {
              return ToolFailure('数组下标越界：$token');
            }
            next.add(value[token]);
          } else if (token is String && value is Map) {
            if (!value.containsKey(token)) return ToolFailure('字段不存在：$token');
            next.add(value[token]);
          } else {
            return ToolFailure('路径与当前 JSON 类型不匹配：$token');
          }
        }
        values = next;
      }
      final Object? result = values.length == 1 ? values.single : values;
      return ToolSuccess(const JsonEncoder.withIndent('  ').convert(result));
    } on FormatException catch (error) {
      return ToolFailure('JSON 查询失败：${error.message}', position: error.offset);
    }
  }

  static List<Object> _jsonPathTokens(String query) {
    String value = query.trim();
    if (value.isEmpty || value == r'$' || value == '.') return const <Object>[];
    if (value.startsWith(r'$')) value = value.substring(1);
    final List<Object> tokens = <Object>[];
    int index = 0;
    while (index < value.length) {
      if (value[index] == '.') {
        index++;
        continue;
      }
      if (value[index] == '[') {
        final int end = value.indexOf(']', index + 1);
        if (end < 0) throw const FormatException('查询路径缺少 ]');
        String token = value.substring(index + 1, end).trim();
        if ((token.startsWith('"') && token.endsWith('"')) ||
            (token.startsWith("'") && token.endsWith("'"))) {
          token = token.substring(1, token.length - 1);
        }
        if (token == '*') {
          tokens.add('*');
        } else {
          final int? number = int.tryParse(token);
          if (number == null) throw FormatException('无效数组下标：$token');
          tokens.add(number);
        }
        index = end + 1;
        continue;
      }
      int end = index;
      while (end < value.length && value[end] != '.' && value[end] != '[') {
        end++;
      }
      final String token = value.substring(index, end).trim();
      if (token.isEmpty) throw const FormatException('查询路径包含空字段');
      tokens.add(token);
      index = end;
    }
    return tokens;
  }
}
