import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/native_app_debug_service.dart';

void main() {
  test('macOS 进程工具可按其他 App 名筛选并返回真实字段', () async {
    if (!Platform.isMacOS) return;
    final result = await NativeAppDebugService.inspectProcesses(
      query: 'TargetApp',
      runner: (executable, arguments) async {
        expect(executable, '/bin/ps');
        expect(arguments, contains('pid=,ppid=,%cpu=,%mem=,etime=,command='));
        return ProcessResult(
          1,
          0,
          '  101 1 12.5 3.4 00:42 /Applications/TargetApp.app/Contents/MacOS/TargetApp\n'
              '  202 1  0.1 0.2 01:01 /Applications/Other.app/Contents/MacOS/Other\n',
          '',
        );
      },
    );
    final rows = result['processes']! as List<Object?>;
    expect(rows, hasLength(1));
    expect((rows.single as Map<String, Object?>)['pid'], 101);
    expect((rows.single as Map<String, Object?>)['cpuPercent'], 12.5);
  });

  test('macOS 日志工具固定调用 Unified Log 且参数不经过 shell', () async {
    if (!Platform.isMacOS) return;
    final result = await NativeAppDebugService.readLogs(
      processName: 'TargetApp',
      seconds: 60,
      maxLines: 2,
      runner: (executable, arguments) async {
        expect(executable, '/usr/bin/log');
        expect(arguments, containsAll(<String>['show', '--last', '60s']));
        expect(arguments.join(' '), contains('TargetApp'));
        return ProcessResult(1, 0, 'line1\nline2\nline3', '');
      },
    );
    expect(result['lines'], <String>['line2', 'line3']);
    expect(result['truncated'], isTrue);
    expect(result['source'], 'macOS Unified Log');
  });

  test('应用控制拒绝换行注入和未知动作', () async {
    expect(
      () => NativeAppDebugService.controlApplication(
        action: 'launch',
        target: 'App\nmalicious',
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => NativeAppDebugService.controlApplication(
        action: 'delete',
        target: 'TargetApp',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
