import 'tool_result.dart';

/// 时间与文本工具，全部离线可用。
abstract final class TimeTools {
  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _formatDateTime(DateTime dateTime, {required bool utc}) {
    final DateTime value = utc ? dateTime.toUtc() : dateTime;
    final String zone = utc ? 'UTC' : '本地';
    return '${value.year}-${_two(value.month)}-${_two(value.day)} '
        '${_two(value.hour)}:${_two(value.minute)}:${_two(value.second)} '
        '($zone)';
  }

  /// 将 Unix 秒或毫秒时间戳转换为本地时间和 UTC 时间。
  static ToolResult timestampToDate(String input) {
    final String text = input.trim();
    final int? raw = int.tryParse(text);
    if (raw == null || raw < 0) {
      return const ToolFailure('时间戳转换失败：输入必须是数字');
    }
    final DateTime dateTime = text.length <= 10
        ? DateTime.fromMillisecondsSinceEpoch(raw * 1000)
        : DateTime.fromMillisecondsSinceEpoch(raw);
    return ToolSuccess(
      '本地：${_formatDateTime(dateTime, utc: false)}\n'
      'UTC：${_formatDateTime(dateTime, utc: true)}',
    );
  }

  /// 将本地时间字符串转换为 Unix 秒时间戳。
  static ToolResult dateToTimestamp(String input) {
    final DateTime? parsed = DateTime.tryParse(input.trim());
    if (parsed == null) {
      return const ToolFailure(
        '日期转时间戳失败：无法解析日期，请使用 yyyy-MM-dd HH:mm:ss 或 ISO 格式',
      );
    }
    final int seconds = parsed.millisecondsSinceEpoch ~/ 1000;
    return ToolSuccess('秒：$seconds\n毫秒：${parsed.millisecondsSinceEpoch}');
  }

  /// 正则测试：params 为模式，input 为待匹配文本。
  static ToolResult regexTest(String pattern, String text) {
    if (pattern.trim().isEmpty) {
      return const ToolFailure('正则测试失败：模式不能为空');
    }
    final RegExp regexp;
    try {
      regexp = RegExp(pattern);
    } on FormatException catch (e) {
      return ToolFailure('正则表达式无效：${e.message}');
    }

    final Iterable<RegExpMatch> matches = regexp.allMatches(text);
    final List<RegExpMatch> list = matches.toList();
    if (list.isEmpty) {
      return const ToolSuccess('无匹配');
    }
    final StringBuffer buffer = StringBuffer();
    buffer.write('共 ${list.length} 个匹配：\n');
    for (int index = 0; index < list.length; index++) {
      final RegExpMatch match = list[index];
      final String groupText = match.groupCount == 0
          ? ''
          : ' 组：${match.groups(List<int>.generate(match.groupCount, (int i) => i + 1)).join(', ')}';
      buffer.write(
        '${index + 1}. 位置 ${match.start}～${match.end}：'
        '${match.group(0)}$groupText\n',
      );
    }
    return ToolSuccess(buffer.toString().trimRight());
  }
}
