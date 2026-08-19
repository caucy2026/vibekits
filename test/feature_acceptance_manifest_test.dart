import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('发布验收清单中的工作流、测试和证据均真实存在', () {
    final File manifest = File('tool/release_acceptance_manifest.json');
    expect(manifest.existsSync(), isTrue);
    final Map<String, Object?> json =
        jsonDecode(manifest.readAsStringSync()) as Map<String, Object?>;
    final List<Object?> workflows = json['workflows']! as List<Object?>;
    expect(workflows.length, greaterThanOrEqualTo(10));
    final Set<String> ids = <String>{};
    final Set<String> coveredTests = <String>{};
    for (final Object? raw in workflows) {
      final Map<String, Object?> workflow = (raw! as Map<Object?, Object?>)
          .cast<String, Object?>();
      final String id = workflow['id']!.toString();
      expect(id, matches(RegExp(r'^[a-z0-9-]+$')));
      expect(ids.add(id), isTrue, reason: '工作流 ID 重复：$id');
      expect(workflow['name'].toString().trim(), isNotEmpty);
      expect(workflow['risk'].toString().trim(), isNotEmpty);
      final List<Object?> tests = workflow['tests']! as List<Object?>;
      final List<Object?> evidence = workflow['evidence']! as List<Object?>;
      expect(tests, isNotEmpty, reason: '$id 缺少自动测试');
      expect(evidence, isNotEmpty, reason: '$id 缺少验收证据');
      for (final Object? pathValue in <Object?>[...tests, ...evidence]) {
        final String path = pathValue.toString();
        expect(File(path).existsSync(), isTrue, reason: '$id 引用了不存在的文件：$path');
      }
      coveredTests.addAll(tests.map((Object? value) => value.toString()));
    }
    expect(coveredTests, contains('test/harness_tool_bridge_test.dart'));
    expect(coveredTests, contains('test/system_drive_analyzer_test.dart'));
    expect(coveredTests, contains('test/cleaner_widget_test.dart'));
  });
}
