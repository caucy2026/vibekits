// ignore_for_file: avoid_print

import 'dart:io';

import 'package:vibekits/features/cleaner/domain/cleanup_deleter.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_file_identity.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_scanner.dart';

Future<void> main() async {
  final Directory sandbox = await Directory.systemTemp.createTemp(
    'vibekits_cleanup_verify_',
  );
  try {
    final File recycleFile = File(
      '${sandbox.path}${Platform.pathSeparator}recycle.cache',
    )..writeAsStringSync('generated test cache');
    final CleanupCandidate recycleCandidate = _candidate(recycleFile);
    final CleanupDeleteResult recycleResult =
        await CleanupDeleter.deleteCandidates(<CleanupCandidate>[
          recycleCandidate,
        ]);
    if (recycleResult.succeeded != 1 || recycleFile.existsSync()) {
      throw StateError(
        '回收站删除失败：${recycleResult.items.map((item) => item.reason).join(', ')}',
      );
    }

    final File fallbackFile = File(
      '${sandbox.path}${Platform.pathSeparator}fallback.cache',
    )..writeAsStringSync('generated fallback cache');
    final CleanupDeleteResult fallbackResult =
        await CleanupDeleter.deleteCandidates(
          <CleanupCandidate>[_candidate(fallbackFile)],
          recycle: (String _) => false,
          permanentFallback: true,
        );
    if (fallbackResult.succeeded != 1 || fallbackFile.existsSync()) {
      throw StateError(
        '强力清理失败：${fallbackResult.items.map((item) => item.reason).join(', ')}',
      );
    }
    print('真实回收站删除：通过');
    print('可再生成缓存强力清理：通过');
  } finally {
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  }
}

CleanupCandidate _candidate(File file) => CleanupCandidate(
  path: file.path,
  size: file.lengthSync(),
  modified: file.lastModifiedSync(),
  identity: CleanupFileIdentity.read(file.path),
  category: CleanupCategory.applicationCache,
  reason: '生成的测试缓存',
);
