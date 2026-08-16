import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/archive/domain/archive_service.dart';
import 'package:vibekits/features/archive/domain/seven_zip.dart';

void main() {
  test('内置 7-Zip 是支持 RAR/ISO/ZSTD 的完整 26.02 后端', () async {
    final String? exe = SevenZip.findExecutable();
    expect(exe, isNotNull);
    final ProcessResult info = await Process.run(exe!, <String>['i']);
    expect(info.exitCode, 0);
    final String output = info.stdout as String;
    expect(output, contains('7-Zip 26.02'));
    expect(output, contains(' Rar5 '));
    expect(output, contains(' Iso '));
    expect(output, contains(' zstd '));
  });

  test('7z 创建、列表、解压闭环', () async {
    final String? exe = SevenZip.findExecutable();
    if (exe == null) {
      return; // 无 7za 时跳过
    }
    final Directory tmp = Directory.systemTemp.createTempSync('vk_7z');
    File('${tmp.path}/a.txt').writeAsStringSync('hello 7z');
    try {
      final ProcessResult create = await Process.run(exe, <String>[
        'a',
        't.7z',
        'a.txt',
        '-y',
      ], workingDirectory: tmp.path);
      expect(create.exitCode, 0, reason: '${create.stderr}');

      final List<SevenZipEntry> entries = await SevenZip.list(
        '${tmp.path}/t.7z',
      );
      expect(
        entries.any((SevenZipEntry e) => e.name.endsWith('a.txt')),
        isTrue,
      );

      final String out = '${tmp.path}/out';
      await SevenZip.extract('${tmp.path}/t.7z', out);
      expect(File('$out/a.txt').readAsStringSync(), 'hello 7z');

      final ArchiveCancellationToken token = ArchiveCancellationToken()
        ..cancel();
      final String cancelledOut = '${tmp.path}/cancelled';
      final ExtractResult cancelled = await SevenZip.extractCancellable(
        '${tmp.path}/t.7z',
        cancelledOut,
        cancellationToken: token,
      );
      expect(cancelled.cancelled, isTrue);
      expect(Directory(cancelledOut).existsSync(), isFalse);
    } finally {
      tmp.deleteSync(recursive: true);
    }
  });

  test('官方 RAR5 真实文件可列表并选择性解压', () async {
    final String separator = Platform.pathSeparator;
    final String archivePath = <String>[
      Directory.current.path,
      'test_data',
      'archives',
      'rarlng.rar',
    ].join(separator);
    final List<SevenZipEntry> entries = await SevenZip.list(archivePath);
    final SevenZipEntry firstFile = entries.firstWhere(
      (SevenZipEntry entry) => !entry.isDirectory && entry.size > 0,
    );
    expect(entries.length, greaterThan(10));
    expect(firstFile.name, startsWith('Resources'));

    final Directory output = Directory.systemTemp.createTempSync(
      'vk_rar_extract',
    );
    try {
      final ExtractResult result = await SevenZip.extractCancellable(
        archivePath,
        output.path,
        selectedEntries: <String>[firstFile.name],
      );
      expect(result.failed, 0);
      expect(result.succeeded, 1);
      expect(
        File('${output.path}$separator${firstFile.name}').existsSync(),
        isTrue,
      );
    } finally {
      output.deleteSync(recursive: true);
    }
  });
}
