import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_deleter.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_file_identity.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_scanner.dart';

void main() {
  test('Windows 文件身份稳定且不同文件身份不同', () {
    if (!Platform.isWindows) return;
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_identity',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final File first = File('${sandbox.path}/first.tmp')
      ..writeAsStringSync('x');
    final File second = File('${sandbox.path}/second.tmp')
      ..writeAsStringSync('x');

    final CleanupFileIdentity? firstIdentity = CleanupFileIdentity.read(
      first.path,
    );
    expect(firstIdentity, isNotNull);
    expect(CleanupFileIdentity.read(first.path), firstIdentity);
    expect(CleanupFileIdentity.read(second.path), isNot(firstIdentity));
  });

  test('同路径文件被替换后清理计划跳过新文件', () async {
    if (!Platform.isWindows) return;
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_identity_replace',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final File target = File('${sandbox.path}/target.tmp')
      ..writeAsStringSync('same');
    final CleanupFileIdentity identity = CleanupFileIdentity.read(target.path)!;
    final DateTime modified = target.lastModifiedSync();
    final File replacement = File('${sandbox.path}/replacement.tmp')
      ..writeAsStringSync('same');
    replacement.setLastModifiedSync(modified);
    target.deleteSync();
    replacement.renameSync(target.path);

    final CleanupDeleteResult result = await CleanupDeleter.deleteCandidates(
      <CleanupCandidate>[
        CleanupCandidate(
          path: target.path,
          size: 4,
          modified: modified,
          identity: identity,
          category: CleanupCategory.userTemp,
          reason: '测试',
        ),
      ],
      recycle: (String path) {
        File(path).deleteSync();
        return true;
      },
    );

    expect(result.skipped, 1);
    expect(result.items.single.reason, '扫描后文件已变化');
    expect(target.existsSync(), isTrue);
  });
}
