import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_task.dart';
import 'package:vibekits/features/dev_tools/domain/duplicate_file_background_runner.dart';
import 'package:vibekits/features/dev_tools/domain/duplicate_file_scanner.dart';

void main() {
  test('重复文件枚举和哈希在独立 Isolate 中完成', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_duplicate_worker',
    );
    File('${sandbox.path}/a.bin').writeAsStringSync('same');
    File('${sandbox.path}/b.bin').writeAsStringSync('same');
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final List<DuplicateScanProgress> progress = <DuplicateScanProgress>[];

    final DuplicateScanResult result = await DuplicateFileBackgroundRunner.scan(
      sandbox.path,
      recursive: true,
      minimumSize: 0,
      cancellationToken: CleanupCancellationToken(),
      onProgress: progress.add,
    );

    expect(result.groups, hasLength(1));
    expect(result.groups.single.files, hasLength(2));
    expect(progress, isNotEmpty);
  });

  test('重复文件工作 Isolate 接收取消', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_duplicate_worker_cancel',
    );
    for (int index = 0; index < 20; index++) {
      File('${sandbox.path}/$index.bin').writeAsStringSync('same');
    }
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final CleanupCancellationToken cancellation = CleanupCancellationToken()
      ..cancel();

    final DuplicateScanResult result = await DuplicateFileBackgroundRunner.scan(
      sandbox.path,
      recursive: true,
      minimumSize: 0,
      cancellationToken: cancellation,
      onProgress: (_) {},
    );

    expect(result.cancelled, isTrue);
  });
}
