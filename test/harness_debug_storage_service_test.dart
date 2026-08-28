import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/cleaner/domain/harness_debug_storage_service.dart';

void main() {
  test('汇总 Harness 调试目录并仅推荐超过保留期的文件', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'vibekits-harness-storage-',
    );
    addTearDown(() => root.delete(recursive: true));
    final Directory logs = await Directory(
      '${root.path}${Platform.pathSeparator}logs',
    ).create(recursive: true);
    final Directory screenshots = await Directory(
      '${root.path}${Platform.pathSeparator}screenshots',
    ).create(recursive: true);
    await Directory('${root.path}${Platform.pathSeparator}temp')
        .create(recursive: true);
    final File oldLog = File('${logs.path}${Platform.pathSeparator}old.log');
    await oldLog.writeAsBytes(List<int>.filled(100, 1));
    await oldLog.setLastModified(
      DateTime.now().subtract(const Duration(days: 2)),
    );
    await File('${screenshots.path}${Platform.pathSeparator}recent.png')
        .writeAsBytes(List<int>.filled(40, 2));

    final HarnessDebugStorageSummary summary =
        await HarnessDebugStorageService.inspect(root.path);

    expect(summary.totalBytes, 140);
    expect(summary.reclaimableBytes, 100);
    expect(summary.fileCount, 2);
    expect(summary.areas, hasLength(3));
    expect(
      summary.areas
          .singleWhere((HarnessDebugAreaUsage e) => e.name == 'logs')
          .reclaimableBytes,
      100,
    );
  });
}
