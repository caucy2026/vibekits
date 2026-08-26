import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_bridge.dart';
import 'package:vibekits/features/dev_tools/domain/harness_tool_activity_store.dart';
import 'package:vibekits/features/dev_tools/domain/tool_registry.dart';
import 'package:vibekits/features/dev_tools/domain/tool_result.dart';

void main() {
  const Set<String> ids = <String>{
    'json_minify',
    'json_escape',
    'json_unescape',
    'xml_format',
    'xml_minify',
    'csv_to_json',
    'json_to_csv',
    'jwt_decode',
    'jwt_expiry',
    'number_base_convert',
    'endian_swap',
    'ascii_inspect',
    'chmod_decode',
    'chmod_encode',
    'semver_compare',
    'bytes_convert',
    'duration_convert',
    'hex_to_rgb',
    'rgb_to_hex',
    'query_parse',
    'query_build',
    'regex_escape',
    'glob_test',
    'line_sort',
    'line_unique',
    'text_statistics',
    'case_convert',
    'line_ending_normalize',
    'http_status_lookup',
    'mime_lookup',
  };

  test('exactly thirty utility-plus tools are registered with AI guidance', () {
    final List<ToolSpec> specs = allDevToolRegistry
        .where((ToolSpec tool) => ids.contains(tool.id))
        .toList(growable: false);
    expect(specs, hasLength(30));
    expect(specs.every((ToolSpec tool) => tool.run != null), isTrue);
    expect(
      specs.every((ToolSpec tool) => tool.aiUseWhen?.isNotEmpty ?? false),
      isTrue,
    );
    expect(
      specs.every((ToolSpec tool) => tool.aiAvoidWhen?.isNotEmpty ?? false),
      isTrue,
    );
  });

  test('all thirty operations close their representative local workflow', () {
    final Map<String, (String, String, String)> cases = _cases();

    expect(cases.keys.toSet(), ids);
    for (final MapEntry<String, (String, String, String)> entry
        in cases.entries) {
      final ToolSpec spec = allDevToolRegistry.singleWhere(
        (ToolSpec tool) => tool.id == entry.key,
      );
      final ToolResult result = spec.run!(entry.value.$1, entry.value.$2);
      expect(result, isA<ToolSuccess>(), reason: entry.key);
      expect(
        (result as ToolSuccess).output,
        contains(entry.value.$3),
        reason: entry.key,
      );
    }
  });

  test(
    'all thirty execute through Harness and write auditable evidence',
    () async {
      final List<String> audited = <String>[];
      final VibekitsHarnessToolBridge bridge = VibekitsHarnessToolBridge(
        activityRecorder:
            ({
              required String toolId,
              required String toolName,
              required String target,
              required Map<String, Object?> arguments,
              required Object? result,
              required HarnessToolActivityStatus status,
              required DateTime startedAt,
            }) async {
              expect(status, HarnessToolActivityStatus.succeeded);
              audited.add(toolId);
            },
      );
      final Set<String> executable = bridge.executableCatalog
          .map((HarnessToolDefinition tool) => tool.id)
          .toSet();
      expect(
        ids.every((String id) => executable.contains('vibekits.$id')),
        isTrue,
      );

      int approvals = 0;
      for (final MapEntry<String, (String, String, String)> entry
          in _cases().entries) {
        final HarnessToolCallResult result = await bridge.invoke(
          toolId: 'vibekits.${entry.key}',
          arguments: <String, Object?>{
            'input': entry.value.$1,
            'params': entry.value.$2,
          },
          approve: (_) async {
            approvals++;
            return true;
          },
        );
        expect(result.ok, isTrue, reason: entry.key);
        expect(
          result.data?['output'],
          contains(entry.value.$3),
          reason: entry.key,
        );
      }
      expect(approvals, 0);
      expect(audited.toSet(), <String>{
        for (final String id in ids) 'vibekits.$id',
      });
    },
  );
}

Map<String, (String, String, String)> _cases() {
  final String jwt =
      '${_part(<String, Object?>{'alg': 'none'})}.'
      '${_part(<String, Object?>{'sub': '7', 'exp': 4102444800})}.x';
  return <String, (String, String, String)>{
    'json_minify': ('{ "a": 1 }', '', '{"a":1}'),
    'json_escape': ('a\nb', '', r'"a\nb"'),
    'json_unescape': (r'"a\nb"', '', 'a\nb'),
    'xml_format': ('<a><b>1</b></a>', '', '<b>1</b>'),
    'xml_minify': ('<a><b>1</b></a>', '', '<a><b>1</b></a>'),
    'csv_to_json': ('name,age\nAda,37', '', '"name": "Ada"'),
    'json_to_csv': ('[{"name":"Ada","age":37}]', '', 'name,age\nAda,37'),
    'jwt_decode': (jwt, '', '"signatureVerified": false'),
    'jwt_expiry': (jwt, '', '"expired":false'),
    'number_base_convert': ('255', '10|16', 'FF'),
    'endian_swap': ('0x1234ABCD', '', 'CD AB 34 12'),
    'ascii_inspect': ('A', '', 'U+0041\t65\tA'),
    'chmod_decode': ('754', '', 'rwxr-xr--'),
    'chmod_encode': ('rwxr-xr--', '', '754'),
    'semver_compare': ('1.2.3-alpha', '1.2.3', 'less'),
    'bytes_convert': ('1024', 'b|kib', '1'),
    'duration_convert': ('120', 's|m', '2'),
    'hex_to_rgb': ('#0A64FF', '', '"r":10'),
    'rgb_to_hex': ('10, 100, 255', '', '#0A64FF'),
    'query_parse': ('a=1&a=2', '', '"a": ['),
    'query_build': ('{"q":"a b"}', '', 'q=a+b'),
    'regex_escape': ('a+b', '', r'a\+b'),
    'glob_test': ('lib/a/test.dart', 'lib/**/test.dart', 'match'),
    'line_sort': ('b\na', '', 'a\nb'),
    'line_unique': ('a\nb\na', '', 'a\nb'),
    'text_statistics': ('hello 世界', '', '"words":2'),
    'case_convert': ('hello world', 'camel', 'helloWorld'),
    'line_ending_normalize': ('a\r\nb\r', 'lf', 'a\nb\n'),
    'http_status_lookup': ('404', '', 'Not Found'),
    'mime_lookup': ('file.wasm', '', 'application/wasm'),
  };
}

String _part(Map<String, Object?> value) =>
    base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
