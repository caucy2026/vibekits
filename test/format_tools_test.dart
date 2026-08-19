import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/format_tools.dart';
import 'package:vibekits/features/dev_tools/domain/tool_result.dart';

void main() {
  group('JSON 格式化', () {
    test('对象格式化含缩进', () {
      final String output =
          (FormatTools.jsonFormat('{"a":1}') as ToolSuccess).output;
      expect(output, contains('\n'));
      expect(output, contains('  "a": 1'));
    });

    test('数组格式化', () {
      final String output =
          (FormatTools.jsonFormat('[1,2]') as ToolSuccess).output;
      expect(output, contains('1'));
    });

    test('非法 JSON 返回位置', () {
      final ToolResult result = FormatTools.jsonFormat('{"a":');
      expect(result, isA<ToolFailure>());
      final ToolFailure failure = result as ToolFailure;
      expect(failure.position, isNotNull);
    });
  });

  group('JSON 校验', () {
    test('有效对象', () {
      expect(
        (FormatTools.jsonValidate('{"a":1}') as ToolSuccess).output,
        contains('对象'),
      );
    });

    test('有效数组', () {
      expect(
        (FormatTools.jsonValidate('[1,2]') as ToolSuccess).output,
        contains('数组'),
      );
    });

    test('无效返回失败', () {
      expect(FormatTools.jsonValidate('{'), isA<ToolFailure>());
    });
  });

  group('JSON 路径查询', () {
    test('提取嵌套数组字段', () {
      final ToolResult result = FormatTools.jsonQuery(
        '{"users":[{"name":"Ada"},{"name":"Linus"}]}',
        '.users[1].name',
      );
      expect((result as ToolSuccess).output, '"Linus"');
    });

    test('通配数组输出有界 JSON 列表', () {
      final ToolResult result = FormatTools.jsonQuery(
        '{"items":[{"id":1},{"id":2}]}',
        '.items[*].id',
      );
      expect((result as ToolSuccess).output, contains('1'));
      expect(result.output, contains('2'));
    });

    test('不存在字段明确失败', () {
      expect(FormatTools.jsonQuery('{"a":1}', '.b'), isA<ToolFailure>());
    });

    test('自动查询 YAML 嵌套列表', () {
      final ToolResult result = FormatTools.structuredQuery(
        'server:\n  ports:\n    - 8080\n    - 8443\n',
        'yaml|.server.ports[1]',
      );
      expect((result as ToolSuccess).output, '8443');
    });

    test('自动查询 TOML section', () {
      final ToolResult result = FormatTools.structuredQuery(
        '[database]\nhost = "localhost"\nport = 5432\n',
        'toml|.database.port',
      );
      expect((result as ToolSuccess).output, '5432');
    });

    test('自动查询 XML 重复节点和属性', () {
      final ToolResult result = FormatTools.structuredQuery(
        '<root><item id="a">one</item><item id="b">two</item></root>',
        'xml|.item[1].@id',
      );
      expect((result as ToolSuccess).output, '"b"');
    });
  });
}
