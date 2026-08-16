import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_task.dart';
import 'package:vibekits/features/dev_tools/domain/duplicate_file_scanner.dart';

void main() {
  test('重复文件先按大小预筛再用完整 SHA-256 分组', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_duplicate_scan',
    );
    final Directory nested = Directory('${sandbox.path}/nested')..createSync();
    final File first = File('${sandbox.path}/first.bin')
      ..writeAsStringSync('same-content');
    final File second = File('${nested.path}/second.bin')
      ..writeAsStringSync('same-content');
    File('${sandbox.path}/same-size-different.bin')
        .writeAsStringSync('other-content');
    File('${sandbox.path}/unique.bin').writeAsStringSync('unique');
    first.setLastModifiedSync(DateTime(2025, 1, 1));
    second.setLastModifiedSync(DateTime(2025, 2, 1));
    addTearDown(() => sandbox.deleteSync(recursive: true));

    final List<DuplicateScanPhase> phases = <DuplicateScanPhase>[];
    final DuplicateScanResult result = await DuplicateFileScanner.scan(
      sandbox.path,
      minimumSize: 0,
      onProgress: (DuplicateScanProgress progress) {
        phases.add(progress.phase);
      },
    );

    expect(result.cancelled, isFalse);
    expect(result.groups, hasLength(1));
    expect(result.groups.single.files, hasLength(2));
    expect(
      FileSystemEntity.identicalSync(
        result.groups.single.suggestedKeep.path,
        second.path,
      ),
      isTrue,
    );
    expect(result.groups.single.reclaimableBytes, first.lengthSync());
    expect(result.groups.single.sha256, hasLength(64));
    expect(phases, contains(DuplicateScanPhase.enumerating));
    expect(phases, contains(DuplicateScanPhase.hashing));
  });

  test('关闭递归时不进入子文件夹', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_duplicate_depth',
    );
    final Directory nested = Directory('${sandbox.path}/nested')..createSync();
    File('${sandbox.path}/first.bin').writeAsStringSync('same');
    File('${nested.path}/second.bin').writeAsStringSync('same');
    addTearDown(() => sandbox.deleteSync(recursive: true));

    final DuplicateScanResult result = await DuplicateFileScanner.scan(
      sandbox.path,
      recursive: false,
      minimumSize: 0,
    );

    expect(result.visitedFiles, 1);
    expect(result.groups, isEmpty);
  });

  test('重复文件扫描可以协作取消且不修改文件', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_duplicate_cancel',
    );
    for (int index = 0; index < 20; index++) {
      File('${sandbox.path}/$index.bin').writeAsStringSync('same-content');
    }
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final CleanupCancellationToken token = CleanupCancellationToken();

    final DuplicateScanResult result = await DuplicateFileScanner.scan(
      sandbox.path,
      minimumSize: 0,
      cancellationToken: token,
      onProgress: (DuplicateScanProgress progress) {
        if (progress.visitedFiles >= 2) token.cancel();
      },
    );

    expect(result.cancelled, isTrue);
    expect(sandbox.listSync().whereType<File>(), hasLength(20));
  });
}
