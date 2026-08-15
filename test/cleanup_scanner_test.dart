import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_scanner.dart';

void main() {
  test('扫描沙箱并分类，不删除文件', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_clean_test',
    );
    final Directory sub = Directory('${sandbox.path}/sub');
    sub.createSync();
    File('${sandbox.path}/a.txt').writeAsStringSync('hello');
    File('${sub.path}/empty_dir_marker.txt').writeAsStringSync('x');

    try {
      final List<CleanupCandidate> candidates =
          await CleanupScanner.scanDirectory(
            sandbox.path,
            CleanupCategory.userTemp,
          );
      expect(candidates, isNotEmpty);
      // 扫描后文件仍在。
      expect(File('${sandbox.path}/a.txt').existsSync(), isTrue);
      // 分类正确。
      expect(
        candidates.every(
          (CleanupCandidate c) => c.category == CleanupCategory.userTemp,
        ),
        isTrue,
      );
    } finally {
      sandbox.deleteSync(recursive: true);
    }
  });

  test('扫描不存在的目录返回空', () async {
    final List<CleanupCandidate> candidates =
        await CleanupScanner.scanDirectory(
          'D:/no/such/dir/xyz',
          CleanupCategory.userTemp,
        );
    expect(candidates, isEmpty);
  });
}
