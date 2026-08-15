import 'dart:convert';

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
}
