import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_scanner.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_task.dart';

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

  test('扫描可在中途取消且不删除文件', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_clean_cancel',
    );
    for (int index = 0; index < 1000; index++) {
      File('${sandbox.path}/$index.tmp').writeAsStringSync('data');
    }
    final CleanupCancellationToken token = CleanupCancellationToken();
    final Future<CleanupScanResult> pending =
        CleanupScanner.scanDirectoryWithProgress(
          sandbox.path,
          CleanupCategory.userTemp,
          cancellationToken: token,
        );
    Future<void>.delayed(const Duration(milliseconds: 1), token.cancel);

    try {
      final CleanupScanResult result = await pending;
      expect(result.cancelled, isTrue);
      expect(result.candidates.length, lessThan(1000));
      expect(File('${sandbox.path}/999.tmp').existsSync(), isTrue);
    } finally {
      sandbox.deleteSync(recursive: true);
    }
  });

  test('精确缓存规则优先于泛化发现，系统保护始终优先', () {
    const CleanupCandidate discovered = CleanupCandidate(
      path: r'C:\App\Cache\a.bin',
      size: 10,
      category: CleanupCategory.discoveredTransient,
      reason: '名称发现',
      riskLevel: CleanupRiskLevel.cautious,
    );
    const CleanupCandidate exact = CleanupCandidate(
      path: r'C:\App\Cache\a.bin',
      size: 10,
      category: CleanupCategory.applicationCache,
      reason: '官方缓存规则',
      sourceLabel: '应用缓存',
      riskLevel: CleanupRiskLevel.safe,
    );
    const CleanupCandidate protected = CleanupCandidate(
      path: r'C:\App\Cache\a.bin',
      size: 10,
      category: CleanupCategory.systemCache,
      reason: '系统管理',
      riskLevel: CleanupRiskLevel.systemManaged,
    );

    expect(
      CleanupScanner.preferredCandidate(discovered, exact).reason,
      '官方缓存规则',
    );
    expect(
      CleanupScanner.preferredCandidate(exact, protected).riskLevel,
      CleanupRiskLevel.systemManaged,
    );
  });
}
