import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_deleter.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_report.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_scanner.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_task.dart';

void main() {
  test('逐项清理真实记录成功、跳过和失败', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_clean_delete',
    );
    addTearDown(() {
      if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
    });
    final File success = File('${sandbox.path}/success.tmp')
      ..writeAsStringSync('1234');
    final File failure = File('${sandbox.path}/failure.tmp')
      ..writeAsStringSync('12');
    final List<CleanupCandidate> candidates = <CleanupCandidate>[
      CleanupCandidate(
        path: success.path,
        size: success.lengthSync(),
        modified: success.lastModifiedSync(),
        category: CleanupCategory.userTemp,
        reason: '测试',
      ),
      CleanupCandidate(
        path: '${sandbox.path}/missing.tmp',
        size: 1,
        category: CleanupCategory.userTemp,
        reason: '测试',
      ),
      CleanupCandidate(
        path: failure.path,
        size: failure.lengthSync(),
        modified: failure.lastModifiedSync(),
        category: CleanupCategory.userTemp,
        reason: '测试',
      ),
    ];

    final CleanupDeleteResult result = await CleanupDeleter.deleteCandidates(
      candidates,
      recycle: (String path) {
        if (path == success.path) {
          File(path).deleteSync();
          return true;
        }
        return false;
      },
    );

    expect(result.succeeded, 1);
    expect(result.skipped, 1);
    expect(result.failed, 1);
    expect(result.releasedBytes, 0);
    expect(result.recycledBytes, 4);
  });

  test('清理日志持久化真实路径并支持读取和删除', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_clean_report',
    );
    addTearDown(() => sandbox.deleteSync(recursive: true));
    const String privatePath = r'C:\Users\private\secret.txt';
    const CleanupDeleteResult result = CleanupDeleteResult(
      items: <CleanupItemResult>[
        CleanupItemResult(
          candidate: CleanupCandidate(
            path: privatePath,
            size: 12,
            category: CleanupCategory.userTemp,
            reason: '临时文件',
          ),
          status: CleanupItemStatus.failed,
          reason: '访问被拒绝',
        ),
      ],
      cancelled: false,
      releasedBytes: 0,
    );

    final File report = await CleanupReportWriter.write(
      result,
      directory: sandbox,
    );
    final String contents = await report.readAsString();

    expect(contents, contains(privatePath.replaceAll(r'\', r'\\')));
    expect(contents, contains('访问被拒绝'));
    expect(contents, contains('"failed": 1'));
    expect(contents, contains('"version": 3'));

    final List<CleanupReportEntry> entries = await CleanupReportWriter.list(
      directory: sandbox,
    );
    expect(entries, hasLength(1));
    expect(entries.single.items.single['path'], privatePath);
    expect(entries.single.failed, 1);
    expect(
      await CleanupReportWriter.delete(entries.single.file, directory: sandbox),
      isTrue,
    );
    expect(await CleanupReportWriter.list(directory: sandbox), isEmpty);
  });

  test('清理取消与失败状态分离', () async {
    final CleanupCancellationToken token = CleanupCancellationToken()..cancel();
    final CleanupDeleteResult result = await CleanupDeleter.deleteCandidates(
      const <CleanupCandidate>[
        CleanupCandidate(
          path: r'C:\not-touched.tmp',
          size: 1,
          category: CleanupCategory.userTemp,
          reason: '测试',
        ),
      ],
      cancellationToken: token,
      recycle: (String _) => throw StateError('不应执行'),
    );

    expect(result.cancelled, isTrue);
    expect(result.failed, 0);
    expect(result.items, isEmpty);
  });

  test('回收站失败时只永久清理可再生成缓存', () async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_fallback',
    );
    addTearDown(() {
      if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
    });
    final File cache = File('${sandbox.path}/cache.bin')
      ..writeAsStringSync('cache');
    final File download = File('${sandbox.path}/download.zip')
      ..writeAsStringSync('download');

    final CleanupDeleteResult result = await CleanupDeleter.deleteCandidates(
      <CleanupCandidate>[
        CleanupCandidate(
          path: cache.path,
          size: cache.lengthSync(),
          modified: cache.lastModifiedSync(),
          category: CleanupCategory.devCache,
          reason: '包缓存',
        ),
        CleanupCandidate(
          path: download.path,
          size: download.lengthSync(),
          modified: download.lastModifiedSync(),
          category: CleanupCategory.downloads,
          reason: '旧安装包',
        ),
      ],
      recycle: (String _) => false,
      permanentFallback: true,
    );

    expect(cache.existsSync(), isFalse);
    expect(download.existsSync(), isTrue);
    expect(result.succeeded, 1);
    expect(result.failed, 1);
    expect(result.items.first.reason, contains('永久删除'));
  });
}
