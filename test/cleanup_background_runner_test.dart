import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_background_runner.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_scanner.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_targets.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_task.dart';

void main() {
  test('后台扫描可跨 Isolate 接收进度并取消', () async {
    final Directory directory = Directory.systemTemp.createTempSync(
      'vibekits_background_scan_',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    for (int index = 0; index < 800; index++) {
      File('${directory.path}${Platform.pathSeparator}$index.tmp')
          .writeAsStringSync('cache-$index');
    }
    final CleanupCancellationToken token = CleanupCancellationToken();
    int progressEvents = 0;

    final CleanupScanResult result = await CleanupBackgroundRunner.scanTargets(
      <CleanupScanTarget>[
        CleanupScanTarget(
          id: 'test-background',
          label: '后台测试',
          path: directory.path,
          category: CleanupCategory.userTemp,
          defaultEnabled: true,
        ),
      ],
      cancellationToken: token,
      onProgress: (CleanupScanProgress progress) {
        progressEvents++;
        token.cancel();
      },
    );

    expect(result.cancelled, isTrue);
    expect(progressEvents, greaterThan(0));
    expect(result.candidates.length, lessThan(800));
  });
}
