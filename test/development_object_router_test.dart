import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/development_object_router.dart';
import 'package:vibekits/features/dev_tools/domain/tool_result.dart';

void main() {
  test('开发对象自动识别并只返回有价值的联动动作', () {
    expect(
      DevelopmentObjectRouter.classify('adb://192.168.3.63:5555'),
      DevelopmentObjectKind.androidDevice,
    );
    expect(
      DevelopmentObjectRouter.classify(r'D:\work\demo\.git'),
      DevelopmentObjectKind.gitRepository,
    );
    expect(
      DevelopmentObjectRouter.classify('service.log'),
      DevelopmentObjectKind.logFile,
    );

    final ToolSuccess result = DevelopmentObjectRouter.recommend(
      'adb://192.168.3.63:5555',
      '',
    ) as ToolSuccess;
    final Map<String, Object?> decoded =
        jsonDecode(result.output) as Map<String, Object?>;
    final List<Object?> actions = decoded['actions']! as List<Object?>;
    expect(decoded['kind'], 'androidDevice');
    expect(actions, hasLength(3));
    expect(actions.first.toString(), contains('vibekits.adb.command'));
  });
}
