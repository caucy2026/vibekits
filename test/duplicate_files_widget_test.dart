import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_deleter.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_scanner.dart';
import 'package:vibekits/features/dev_tools/domain/duplicate_file_scanner.dart';
import 'package:vibekits/features/dev_tools/presentation/duplicate_files_workspace.dart';

void main() {
  testWidgets('重复文件从扫描复核到安全删除完整闭环', (WidgetTester tester) async {
    final Directory sandbox = Directory.systemTemp.createTempSync(
      'vk_duplicate_widget',
    );
    final Directory reports = Directory('${sandbox.path}/reports')
      ..createSync();
    final File older = File('${sandbox.path}/older.bin')
      ..writeAsStringSync('duplicate-content');
    final File newer = File('${sandbox.path}/newer.bin')
      ..writeAsStringSync('duplicate-content');
    older.setLastModifiedSync(DateTime(2025, 1, 1));
    newer.setLastModifiedSync(DateTime(2025, 2, 1));
    final DuplicateScanResult prepared = (await tester.runAsync(
      () => DuplicateFileScanner.scan(sandbox.path, minimumSize: 0),
    ))!;
    addTearDown(() {
      if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DuplicateFilesWorkspace(
            directoryPicker: () async => sandbox.path,
            reportDirectory: reports,
            scanRunner: (
              String root, {
              required bool recursive,
              required int minimumSize,
              required cancellationToken,
              required onProgress,
            }) async => prepared,
            deleteRunner:
                (
                  List<CleanupCandidate> candidates, {
                  required onProgress,
                }) async {
                  final List<CleanupItemResult> items = <CleanupItemResult>[];
                  for (final CleanupCandidate candidate in candidates) {
                    File(candidate.path).deleteSync();
                    items.add(
                      CleanupItemResult(
                        candidate: candidate,
                        status: CleanupItemStatus.succeeded,
                        reason: '测试删除',
                      ),
                    );
                    onProgress(
                      CleanupDeleteProgress(
                        completed: items.length,
                        total: candidates.length,
                      ),
                    );
                  }
                  return CleanupDeleteResult(
                    items: items,
                    cancelled: false,
                    releasedBytes: candidates.fold<int>(
                      0,
                      (int total, CleanupCandidate item) => total + item.size,
                    ),
                  );
                },
            reportWriter: (CleanupDeleteResult result) async {
              return File('${reports.path}/duplicate-report.json')
                ..writeAsStringSync('{"succeeded":${result.succeeded}}');
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('duplicates-pick-directory')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('duplicates-scan')));
    for (
      int attempt = 0;
      attempt < 100 && find.textContaining('2 个相同文件').evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.textContaining('2 个相同文件'), findsOneWidget);
    expect(find.text('建议保留最新'), findsOneWidget);

    await tester.tap(find.text('选择每组建议项'));
    await tester.pump();
    expect(find.text('移入回收站 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('duplicates-delete')));
    await tester.pumpAndSettle();
    expect(find.text('将 1 个文件移入回收站？'), findsOneWidget);
    await tester.tap(find.byKey(const Key('duplicates-confirm-delete')));
    await tester.pumpAndSettle();

    expect(older.existsSync(), isFalse);
    expect(newer.readAsStringSync(), 'duplicate-content');
    expect(find.textContaining('成功 1'), findsOneWidget);
    expect(reports.listSync().whereType<File>(), hasLength(1));
  });
}
