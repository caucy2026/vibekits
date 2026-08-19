import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/code_structure_search_service.dart';
import 'package:vibekits/features/dev_tools/domain/tool_result.dart';

void main() {
  test('后台定位真实类和函数声明并忽略注释与依赖目录', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'vibekits_structure_search_',
    );
    addTearDown(() => root.delete(recursive: true));
    await File(
      '${root.path}${Platform.pathSeparator}service.dart',
    ).writeAsString(
      '// class FakeService {}\nclass UserService {\n  void loadUser() {}\n}\n',
    );
    final Directory ignored = Directory(
      '${root.path}${Platform.pathSeparator}build',
    )..createSync();
    await File('${ignored.path}${Platform.pathSeparator}generated.dart')
        .writeAsString('class UserServiceGenerated {}\n');

    final ToolResult result = await CodeStructureSearchService.search(
      root.path,
      'class|UserService',
    );
    final Map<String, Object?> report =
        jsonDecode((result as ToolSuccess).output) as Map<String, Object?>;

    expect(report['matches'], hasLength(1));
    expect(report['matches'].toString(), contains('UserService'));
    expect(report['matches'].toString(), contains('service.dart'));
  });
}
