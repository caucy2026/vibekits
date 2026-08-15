import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/time_tools.dart';
import 'package:vibekits/features/dev_tools/domain/tool_result.dart';

void main() {
  group('时间戳', () {
    test('秒时间戳 0 转日期', () {
      final String output =
          (TimeTools.timestampToDate('0') as ToolSuccess).output;
      expect(output, contains('本地：1970-01-01'));
      expect(output, contains('UTC：1970-01-01'));
    });

    test('毫秒时间戳转日期', () {
      final String output =
          (TimeTools.timestampToDate('1700000000000') as ToolSuccess).output;
      expect(output, contains('UTC：'));
    });

    test('非法输入失败', () {
      expect(TimeTools.timestampToDate('abc'), isA<ToolFailure>());
    });

    test('日期转时间戳', () {
      final String output = (TimeTools.dateToTimestamp(
        '2026-01-01 00:00:00',
      ) as ToolSuccess).output;
      expect(output, contains('秒：'));
      expect(output, contains('毫秒：'));
    });
  });

  group('正则测试', () {
    test('匹配并给出位置', () {
      final String output =
          (TimeTools.regexTest(r'\d+', 'ab12cd34') as ToolSuccess).output;
      expect(output, contains('共 2 个匹配'));
      expect(output, contains('位置 2～4'));
    });

    test('无匹配', () {
      expect((TimeTools.regexTest(r'z', 'abc') as ToolSuccess).output, '无匹配');
    });

    test('非法模式失败', () {
      expect(TimeTools.regexTest('(', 'abc'), isA<ToolFailure>());
    });

    test('空模式失败', () {
      expect(TimeTools.regexTest('', 'abc'), isA<ToolFailure>());
    });
  });
}
