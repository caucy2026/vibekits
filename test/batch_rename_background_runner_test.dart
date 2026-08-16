import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/dev_tools/domain/batch_rename_background_runner.dart';
import 'package:vibekits/features/dev_tools/domain/file_tools.dart';

void main() {
  test('批量重命名规划和执行在独立 Isolate 完成', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_rename_worker',
    );
    final File source = File('${sandbox.path}/demo.txt')
      ..writeAsStringSync('content');
    addTearDown(() => sandbox.deleteSync(recursive: true));

    final BatchRenamePlan plan = await BatchRenameBackgroundRunner.buildPlan(
      sandbox.path,
      const BatchRenameOptions(prefix: 'done_'),
    );
    final BatchRenameReport report = await BatchRenameBackgroundRunner.execute(
      plan,
    );

    expect(report.isSuccess, isTrue);
    expect(source.existsSync(), isFalse);
    expect(File('${sandbox.path}/done_demo.txt').readAsStringSync(), 'content');
  });
}
