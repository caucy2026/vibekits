import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/code_statistics_service.dart';
import 'package:vibekits/features/dev_tools/domain/tool_result.dart';

void main() {
  test('后台统计代码、注释、空白并跳过依赖目录', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'vibekits_code_stats_',
    );
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}${Platform.pathSeparator}main.dart')
        .writeAsString('// comment\n\nvoid main() {\n  print("ok");\n}\n');
    final Directory dependency = Directory(
      '${root.path}${Platform.pathSeparator}node_modules',
    )..createSync();
    await File('${dependency.path}${Platform.pathSeparator}ignored.js')
        .writeAsString('const ignored = true;\n');

    final ToolResult result = await CodeStatisticsService.analyze(root.path);

    expect(result, isA<ToolSuccess>());
    final Map<String, Object?> report =
        jsonDecode((result as ToolSuccess).output) as Map<String, Object?>;
    expect(report['files'], 1);
    expect(report['codeLines'], 3);
    expect(report['commentLines'], 1);
    expect(report['blankLines'], 1);
    expect(report['languages'].toString(), contains('Dart'));
  });
}
