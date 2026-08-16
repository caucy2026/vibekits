import 'dart:io';

import 'package:vibekits/features/cleaner/domain/cleanup_deleter.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_scanner.dart';
import 'package:vibekits/features/dev_tools/domain/duplicate_file_scanner.dart';

Future<void> main() async {
  if (!Platform.isWindows) {
    stderr.writeln('此验证需要 Windows 回收站。');
    exitCode = 2;
    return;
  }
  final Directory sandbox = Directory.systemTemp.createTempSync(
    'vibekits_duplicate_verify_',
  );
  final File keep = File('${sandbox.path}${Platform.pathSeparator}keep.bin')
    ..writeAsStringSync(
      'generated-duplicate-${DateTime.now().microsecondsSinceEpoch}',
    );
  final File recycle = File(
    '${sandbox.path}${Platform.pathSeparator}recycle.bin',
  )..writeAsBytesSync(keep.readAsBytesSync());
  try {
    final DuplicateScanResult scan = await DuplicateFileScanner.scan(
      sandbox.path,
      minimumSize: 0,
    );
    if (scan.groups.length != 1 || scan.groups.single.files.length != 2) {
      throw StateError('扫描未得到唯一的双文件重复组');
    }
    final DuplicateFileEntry target = scan.groups.single.files.firstWhere(
      (DuplicateFileEntry file) => file.path == recycle.path,
    );
    final CleanupDeleteResult deleted = await CleanupDeleter.deleteCandidates(
      <CleanupCandidate>[
        CleanupCandidate(
          path: target.path,
          size: target.size,
          modified: target.modified,
          identity: target.identity,
          category: CleanupCategory.duplicateFiles,
          reason: '生成的重复文件验证',
        ),
      ],
    );
    final bool passed =
        deleted.succeeded == 1 &&
        keep.existsSync() &&
        !recycle.existsSync() &&
        keep.readAsBytesSync().isNotEmpty;
    stdout.writeln('大小预筛 + SHA-256 分组：通过');
    stdout.writeln('保留文件完整：${keep.existsSync() ? '通过' : '失败'}');
    stdout.writeln('重复副本移入 Windows 回收站：${passed ? '通过' : '失败'}');
    if (!passed) exitCode = 1;
  } finally {
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  }
}
