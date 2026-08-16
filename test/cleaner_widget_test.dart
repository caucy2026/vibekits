import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_scanner.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_task.dart';
import 'package:vibekits/features/cleaner/presentation/cleaner_tab.dart';

void main() {
  testWidgets('扫描显示进度并可取消且保留部分结果', (WidgetTester tester) async {
    final Completer<CleanupScanResult> completer =
        Completer<CleanupScanResult>();
    CleanupCancellationToken? capturedToken;
    late void Function(CleanupScanProgress) progressCallback;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CleanerTab(
            scanRunner:
                ({
                  required CleanupCancellationToken cancellationToken,
                  required void Function(CleanupScanProgress progress)
                  onProgress,
                }) {
                  capturedToken = cancellationToken;
                  progressCallback = onProgress;
                  return completer.future;
                },
          ),
        ),
      ),
    );

    await tester.tap(find.text('开始扫描'));
    await tester.pump();
    progressCallback(
      const CleanupScanProgress(
        currentPath: r'C:\Temp\partial.tmp',
        visitedEntries: 8,
        candidateCount: 1,
        candidateBytes: 1024,
      ),
    );
    await tester.pump();

    expect(find.textContaining('已检查 8 项'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);

    await tester.tap(find.text('取消'));
    expect(capturedToken!.isCancelled, isTrue);
    completer.complete(
      const CleanupScanResult(
        candidates: <CleanupCandidate>[
          CleanupCandidate(
            path: r'C:\Temp\partial.tmp',
            size: 1024,
            category: CleanupCategory.userTemp,
            reason: '用户临时文件',
          ),
        ],
        cancelled: true,
        unreadablePaths: 0,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('扫描已取消'), findsOneWidget);
    expect(find.text(r'C:\Temp\partial.tmp'), findsOneWidget);
  });

  testWidgets('持久化白名单过滤真实子路径但不误伤相似前缀', (WidgetTester tester) async {
    const String root = r'C:\Temp\Keep';
    const String protected = r'C:\Temp\Keep\private.tmp';
    const String similar = r'C:\Temp\Keep2\visible.tmp';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CleanerTab(
            initialWhitelist: const <String>[root],
            scanRunner:
                ({
                  required CleanupCancellationToken cancellationToken,
                  required void Function(CleanupScanProgress progress)
                  onProgress,
                }) async => const CleanupScanResult(
                  candidates: <CleanupCandidate>[
                    CleanupCandidate(
                      path: protected,
                      size: 1,
                      category: CleanupCategory.userTemp,
                      reason: '测试',
                    ),
                    CleanupCandidate(
                      path: similar,
                      size: 1,
                      category: CleanupCategory.userTemp,
                      reason: '测试',
                    ),
                  ],
                  cancelled: false,
                  unreadablePaths: 0,
                ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('开始扫描'));
    await tester.pumpAndSettle();

    expect(find.text(protected), findsNothing);
    expect(find.text(similar), findsOneWidget);
    expect(find.text('白名单（1）'), findsOneWidget);
  });

  testWidgets('大量候选按分类折叠并分批显示', (WidgetTester tester) async {
    final List<CleanupCandidate> candidates = List<CleanupCandidate>.generate(
      150,
      (int index) => CleanupCandidate(
        path: 'C:\\Cache\\item_$index.bin',
        size: 150 - index,
        category: CleanupCategory.pluginCache,
        reason: '插件下载缓存',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CleanerTab(
            scanRunner:
                ({
                  required CleanupCancellationToken cancellationToken,
                  required void Function(CleanupScanProgress progress)
                  onProgress,
                }) async => CleanupScanResult(
                  candidates: candidates,
                  cancelled: false,
                  unreadablePaths: 0,
                ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('开始扫描'));
    await tester.pumpAndSettle();
    expect(find.text('插件下载缓存'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);

    await tester.tap(find.text('插件下载缓存'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNWidgets(100));
    expect(find.textContaining('剩余 50 项'), findsOneWidget);

    await tester.ensureVisible(find.textContaining('剩余 50 项'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('剩余 50 项'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNWidgets(150));
  });
}
