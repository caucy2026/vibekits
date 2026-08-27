import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/project_iteration_service.dart';

void main() {
  test('Harness 自迭代门禁按注册、分析、测试、Release 顺序执行', () async {
    final Directory root = Directory.systemTemp.createTempSync('vk_iteration_');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}${Platform.pathSeparator}pubspec.yaml')
        .writeAsStringSync('name: fixture\n');
    final Directory domain = Directory(
      '${root.path}${Platform.pathSeparator}lib${Platform.pathSeparator}features'
      '${Platform.pathSeparator}dev_tools${Platform.pathSeparator}domain',
    )..createSync(recursive: true);
    File('${domain.path}${Platform.pathSeparator}tool_registry.dart')
        .writeAsStringSync('// registry');
    File('${domain.path}${Platform.pathSeparator}harness_tool_bridge.dart')
        .writeAsStringSync('// bridge');
    final File flutter = File(
      '${root.path}${Platform.pathSeparator}${Platform.isWindows ? 'flutter.bat' : 'flutter'}',
    )..writeAsStringSync('fixture');
    final List<List<String>> commands = <List<String>>[];
    final ProjectIterationService service = ProjectIterationService(
      runner:
          (
            String executable,
            List<String> arguments, {
            required String workingDirectory,
            required Duration timeout,
          }) async {
            commands.add(<String>[executable, ...arguments]);
            return ProcessResult(1, 0, 'ok', '');
          },
    );

    expect((await service.inspect(root.path))['ready'], isTrue);
    final Map<String, Object?> built = await service.build(
      workspace: root.path,
      target: Platform.isWindows ? 'windows' : 'macos',
      flutterExecutable: flutter.path,
    );
    expect(built['success'], isTrue);
    expect(commands.map((List<String> item) => item[1]), <String>[
      'analyze',
      'test',
      'build',
    ]);
    expect('${built['installPolicy']}', contains('用户'));
  });
}
