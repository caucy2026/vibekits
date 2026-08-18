import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/archive/domain/disk_space.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_deleter.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_scanner.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_task.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_targets.dart';
import 'package:vibekits/features/cleaner/domain/system_drive_analyzer.dart';
import 'package:vibekits/features/cleaner/presentation/cleaner_tab.dart';

void main() {
  const List<CleanupScanTarget> testTargets = <CleanupScanTarget>[
    CleanupScanTarget(
      id: 'test-temp',
      label: '测试临时目录',
      path: r'C:\Temp',
      category: CleanupCategory.userTemp,
      defaultEnabled: true,
    ),
  ];

  testWidgets('扫描显示进度并可取消且保留部分结果', (WidgetTester tester) async {
    final Completer<CleanupScanResult> completer =
        Completer<CleanupScanResult>();
    CleanupCancellationToken? capturedToken;
    late void Function(CleanupScanProgress) progressCallback;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CleanerTab(
            availableTargets: testTargets,
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
            availableTargets: testTargets,
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
    expect(find.byTooltip('白名单（1）'), findsOneWidget);
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
            availableTargets: testTargets,
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

  testWidgets('清理完成展示本次累计与系统盘容量总结', (WidgetTester tester) async {
    const CleanupCandidate candidate = CleanupCandidate(
      path: r'C:\Cache\package.tmp',
      size: 2048,
      category: CleanupCategory.pluginCache,
      reason: '插件下载缓存',
    );
    int diskReads = 0;
    int? persistedTotal;
    int? persistedRuns;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CleanerTab(
            availableTargets: testTargets,
            initialTotalReleasedBytes: 1024,
            initialCompletedRuns: 2,
            scanRunner:
                ({
                  required CleanupCancellationToken cancellationToken,
                  required void Function(CleanupScanProgress progress)
                  onProgress,
                }) async => const CleanupScanResult(
                  candidates: <CleanupCandidate>[candidate],
                  cancelled: false,
                  unreadablePaths: 0,
                ),
            deleteRunner:
                ({
                  required List<CleanupCandidate> candidates,
                  required CleanupCancellationToken cancellationToken,
                  required bool permanentFallback,
                  required void Function(CleanupDeleteProgress progress)
                  onProgress,
                }) async {
                  onProgress(
                    const CleanupDeleteProgress(completed: 1, total: 1),
                  );
                  return const CleanupDeleteResult(
                    items: <CleanupItemResult>[
                      CleanupItemResult(
                        candidate: candidate,
                        status: CleanupItemStatus.succeeded,
                        reason: '测试清理完成',
                      ),
                    ],
                    cancelled: false,
                    releasedBytes: 2048,
                  );
                },
            diskSnapshotReader: (String path) {
              diskReads++;
              return DiskSpaceSnapshot(
                path: path,
                availableBytes: diskReads == 1 ? 5000 : 7000,
                totalBytes: 10000,
                freeBytes: diskReads == 1 ? 5000 : 7000,
              );
            },
            onCleanupStatsChanged: (int total, int runs) async {
              persistedTotal = total;
              persistedRuns = runs;
            },
            analyzeAfterCleanup: false,
          ),
        ),
      ),
    );

    await tester.tap(find.text('开始扫描'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清理 1 项'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, '清理'));
    await tester.pumpAndSettle();

    expect(find.text('本次清理'), findsOneWidget);
    expect(find.text('累计清理'), findsOneWidget);
    expect(find.text('系统盘总容量'), findsOneWidget);
    expect(find.text('当前可用'), findsOneWidget);
    expect(find.text('当前已用'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);
    expect(find.text('3.0 KB'), findsOneWidget);
    expect(persistedTotal, 3072);
    expect(persistedRuns, 3);
  });

  testWidgets('空间分析展示总量剩余、占用来源和合理性', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CleanerTab(
            availableTargets: testTargets,
            driveAnalysisRunner:
                ({
                  required CleanupCancellationToken cancellationToken,
                  required void Function(SystemDriveAnalysisProgress progress)
                  onProgress,
                }) async {
                  onProgress(
                    const SystemDriveAnalysisProgress(
                      currentPath: r'C:\estlog',
                      visitedEntries: 12,
                      measuredBytes: 4000,
                      completedRootEntries: 2,
                      totalRootEntries: 3,
                    ),
                  );
                  return const SystemDriveAnalysis(
                    rootPath: r'C:\',
                    entries: <SystemDriveUsageEntry>[
                      SystemDriveUsageEntry(
                        path: r'C:\Windows',
                        name: 'Windows',
                        sizeBytes: 6000,
                        kind: SystemDriveEntryKind.windowsSystem,
                        reason: 'Windows 系统文件',
                        isDirectory: true,
                        complete: true,
                      ),
                      SystemDriveUsageEntry(
                        path: r'C:\estlog',
                        name: 'estlog',
                        sizeBytes: 2000,
                        kind: SystemDriveEntryKind.logsAndCaches,
                        reason: 'EST 加密软件日志',
                        isDirectory: true,
                        complete: true,
                      ),
                    ],
                    cancelled: false,
                    unreadablePaths: 0,
                    visitedEntries: 12,
                    measuredBytes: 8000,
                    totalBytes: 10000,
                    freeBytes: 2000,
                    availableBytes: 2000,
                  );
                },
            persistDriveAnalysisReport: false,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('系统盘空间分析'));
    await tester.pumpAndSettle();

    expect(find.text('系统盘空间分析'), findsOneWidget);
    expect(find.textContaining('总量 9.8 KB'), findsOneWidget);
    expect(find.text('Windows'), findsOneWidget);
    expect(find.text('estlog'), findsOneWidget);
    expect(find.textContaining('需复核'), findsOneWidget);
    expect(find.textContaining('剩余 2.0 KB'), findsOneWidget);
  });
}
