import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/archive/domain/disk_space.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_deleter.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_scanner.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_task.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_targets.dart';
import 'package:vibekits/features/cleaner/domain/disk_volume_discovery.dart';
import 'package:vibekits/features/cleaner/domain/installed_application_service.dart';
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

  testWidgets('目录版本升级会自动合入新的 ESTLOG 默认范围', (WidgetTester tester) async {
    List<String>? savedIds;
    int? savedVersion;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CleanerTab(
            availableTargets: const <CleanupScanTarget>[
              ...testTargets,
              CleanupScanTarget(
                id: 'est-encryption-old-logs',
                label: r'C:\ESTLOG 加密软件日志',
                path: r'C:\ESTLOG',
                category: CleanupCategory.logs,
                defaultEnabled: true,
                minimumAgeHours: 24,
                includePatterns: <String>['*.log'],
              ),
            ],
            initialTargetIds: const <String>['test-temp'],
            initialTargetCatalogVersion: 8,
            onTargetIdsChanged: (List<String> ids, int version) async {
              savedIds = ids;
              savedVersion = version;
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      savedIds,
      containsAll(<String>['test-temp', 'est-encryption-old-logs']),
    );
    expect(savedVersion, CleanupTargetDiscovery.catalogVersion);
  });

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

    await tester.tap(find.text('扫描可清理项'));
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

    await tester.tap(find.text('扫描可清理项'));
    await tester.pumpAndSettle();

    expect(find.text(protected), findsNothing);
    expect(find.text(similar), findsOneWidget);
    expect(find.byTooltip('白名单（1）'), findsOneWidget);
  });

  testWidgets('智能选择只选安全项并保留应用运行包和回收站', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
                }) async => const CleanupScanResult(
                  candidates: <CleanupCandidate>[
                    CleanupCandidate(
                      path: r'C:\Cache\gradle.bin',
                      size: 8 * 1024 * 1024 * 1024,
                      category: CleanupCategory.systemCache,
                      reason: '已验证的系统缓存',
                    ),
                    CleanupCandidate(
                      path: r'C:\',
                      size: 2 * 1024 * 1024 * 1024,
                      category: CleanupCategory.recycleBin,
                      reason: '回收站',
                      riskLevel: CleanupRiskLevel.systemManaged,
                    ),
                    CleanupCandidate(
                      path: r'C:\Users\caucy\Downloads\keep.zip',
                      size: 3 * 1024 * 1024 * 1024,
                      category: CleanupCategory.downloads,
                      reason: '用户下载',
                    ),
                    CleanupCandidate(
                      path:
                          r'C:\Users\caucy\AppData\Roaming\Tencent\runtime.dll',
                      size: 1024 * 1024 * 1024,
                      category: CleanupCategory.applicationCache,
                      reason: '应用运行包',
                      riskLevel: CleanupRiskLevel.cautious,
                    ),
                    CleanupCandidate(
                      path: r'C:\Users\caucy\.gradle\caches\active.bin',
                      size: 1024 * 1024 * 1024,
                      category: CleanupCategory.devCache,
                      reason: '当前可能使用的开发依赖',
                    ),
                    CleanupCandidate(
                      path: r'C:\Users\caucy\AppData\Local\KnownApp\Cache\old.tmp',
                      size: 512 * 1024 * 1024,
                      category: CleanupCategory.applicationCache,
                      reason: '已验证的可重建应用缓存',
                    ),
                  ],
                  cancelled: false,
                  unreadablePaths: 0,
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('扫描可清理项'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('智能选择'));
    await tester.pumpAndSettle();

    expect(find.text('智能选择清理计划'), findsOneWidget);
    expect(find.textContaining('不会被智能选择'), findsOneWidget);
    expect(find.textContaining('预计 8.50 GB'), findsOneWidget);
    await tester.tap(find.text('确认选择'));
    await tester.pumpAndSettle();
    expect(find.text('清理 2 项'), findsOneWidget);
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

    await tester.tap(find.text('扫描可清理项'));
    await tester.pumpAndSettle();
    for (final String view in <String>[
      'recommended',
      'softwareCache',
      'largeDownloads',
    ]) {
      expect(
        find.byKey(ValueKey<String>('cleanup-view-$view')),
        findsOneWidget,
      );
    }
    await tester.drag(
      find.byKey(const ValueKey<String>('cleanup-task-navigation')),
      const Offset(-600, 0),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('cleanup-view-unusedSoftware')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('cleanup-view-deepCleanup')),
      findsOneWidget,
    );
    await tester.drag(
      find.byKey(const ValueKey<String>('cleanup-task-navigation')),
      const Offset(600, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('cleanup-view-softwareCache')),
    );
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

    await tester.tap(find.text('扫描可清理项'));
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
    String? harnessPrompt;
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
            onAskHarness: (String prompt) async {
              harnessPrompt = prompt;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('分析全部磁盘占用（只读）'));
    await tester.pumpAndSettle();

    expect(find.textContaining('磁盘空间分析'), findsOneWidget);
    expect(find.textContaining('总量 9.8 KB'), findsOneWidget);
    expect(find.text('Windows'), findsOneWidget);
    expect(find.text('estlog'), findsOneWidget);
    expect(find.textContaining('需复核'), findsOneWidget);
    expect(find.textContaining('剩余 2.0 KB'), findsOneWidget);
    await tester.tap(find.text('让 Harness 解释'));
    await tester.pump();
    expect(harnessPrompt, contains('vibekits.cleaner.analyze_drive'));
    expect(harnessPrompt, contains(r'C:\'));
  });

  testWidgets('空间分析未完成时逐项显示已完成的软件占用', (WidgetTester tester) async {
    final Completer<SystemDriveAnalysis> result =
        Completer<SystemDriveAnalysis>();
    late void Function(SystemDriveAnalysisProgress) report;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CleanerTab(
            availableTargets: testTargets,
            persistDriveAnalysisReport: false,
            driveAnalysisRunner:
                ({
                  required CleanupCancellationToken cancellationToken,
                  required void Function(SystemDriveAnalysisProgress progress)
                  onProgress,
                }) {
                  report = onProgress;
                  return result.future;
                },
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('分析全部磁盘占用（只读）'));
    await tester.pump();
    report(
      const SystemDriveAnalysisProgress(
        currentPath: r'C:\Program Files\Acme IDE',
        visitedEntries: 20,
        measuredBytes: 4096,
        completedRootEntries: 1,
        totalRootEntries: 8,
        completedEntry: SystemDriveUsageEntry(
          path: r'C:\Program Files',
          name: 'Program Files',
          sizeBytes: 4096,
          kind: SystemDriveEntryKind.installedPrograms,
          reason: '应用安装目录',
          isDirectory: true,
          complete: true,
        ),
        completedBreakdownEntries: <SystemDriveUsageEntry>[
          SystemDriveUsageEntry(
            path: r'C:\Program Files\Acme IDE',
            name: 'Acme IDE',
            sizeBytes: 4096,
            kind: SystemDriveEntryKind.installedPrograms,
            reason: 'Acme IDE 的程序安装文件',
            isDirectory: true,
            complete: true,
            ownerLabel: 'Acme IDE',
            parentPath: r'C:\Program Files',
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.textContaining('占用结果实时加载'), findsOneWidget);
    expect(find.text('Acme IDE'), findsOneWidget);
    expect(find.textContaining('1/8'), findsOneWidget);

    result.complete(
      const SystemDriveAnalysis(
        rootPath: r'C:\',
        entries: <SystemDriveUsageEntry>[],
        cancelled: true,
        unreadablePaths: 0,
        visitedEntries: 20,
        measuredBytes: 4096,
        totalBytes: 10000,
        freeBytes: 2000,
        availableBytes: 2000,
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('空间占用列表可确认后把日志目录移到回收站', (WidgetTester tester) async {
    String? recycledPath;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CleanerTab(
            availableTargets: testTargets,
            persistDriveAnalysisReport: false,
            installedApplicationLoader: () async =>
                const <InstalledApplication>[],
            driveEntryRecycler: (String path) async {
              recycledPath = path;
              return true;
            },
            driveAnalysisRunner:
                ({
                  required CleanupCancellationToken cancellationToken,
                  required void Function(SystemDriveAnalysisProgress progress)
                  onProgress,
                }) async => const SystemDriveAnalysis(
                  rootPath: r'C:\',
                  entries: <SystemDriveUsageEntry>[
                    SystemDriveUsageEntry(
                      path: r'C:\ESTLOG',
                      name: 'ESTLOG',
                      sizeBytes: 8192,
                      kind: SystemDriveEntryKind.logsAndCaches,
                      reason: 'EST 加密软件日志',
                      isDirectory: true,
                      complete: true,
                      deletePolicy:
                          SystemDriveDeletePolicy.recycleAfterConfirmation,
                    ),
                  ],
                  cancelled: false,
                  unreadablePaths: 0,
                  visitedEntries: 10,
                  measuredBytes: 8192,
                  totalBytes: 10000,
                  freeBytes: 1000,
                  availableBytes: 1000,
                ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('分析全部磁盘占用（只读）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('磁盘占用与可清理'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('移到回收站'));
    await tester.pumpAndSettle();
    expect(find.text('从空间列表清理？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '移到回收站'));
    await tester.pumpAndSettle();

    expect(recycledPath, r'C:\ESTLOG');
  });

  testWidgets('软件占用列表可直接清理缓存并启动正式卸载器', (WidgetTester tester) async {
    String? recycledPath;
    String? uninstalledName;
    const SystemDriveAnalysis analysis = SystemDriveAnalysis(
      rootPath: r'C:\',
      entries: <SystemDriveUsageEntry>[
        SystemDriveUsageEntry(
          path: r'C:\Program Files',
          name: 'Program Files',
          sizeBytes: 5000,
          kind: SystemDriveEntryKind.installedPrograms,
          reason: '程序安装目录',
          isDirectory: true,
          complete: true,
        ),
      ],
      breakdownEntries: <SystemDriveUsageEntry>[
        SystemDriveUsageEntry(
          path: r'C:\Program Files\Acme',
          name: 'Acme',
          sizeBytes: 3000,
          kind: SystemDriveEntryKind.installedPrograms,
          reason: 'Acme 安装目录',
          isDirectory: true,
          complete: true,
          ownerLabel: 'Acme',
          parentPath: r'C:\Program Files',
        ),
        SystemDriveUsageEntry(
          path: r'C:\Users\me\AppData\Local\Acme',
          name: 'me / AppData / Local / Acme',
          sizeBytes: 2000,
          kind: SystemDriveEntryKind.softwareData,
          reason: 'Acme 数据',
          isDirectory: true,
          complete: true,
          ownerLabel: 'Acme',
          parentPath: r'C:\Users',
        ),
        SystemDriveUsageEntry(
          path: r'C:\Users\me\AppData\Local\Acme\Cache',
          name: 'me / AppData / Local / Acme / Cache',
          sizeBytes: 1000,
          kind: SystemDriveEntryKind.logsAndCaches,
          reason: 'Acme 缓存',
          isDirectory: true,
          complete: true,
          ownerLabel: 'Acme',
          parentPath: r'C:\Users',
          deletePolicy: SystemDriveDeletePolicy.recycleAfterConfirmation,
        ),
      ],
      cancelled: false,
      unreadablePaths: 0,
      visitedEntries: 10,
      measuredBytes: 5000,
      totalBytes: 10000,
      freeBytes: 3000,
      availableBytes: 3000,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CleanerTab(
            availableTargets: testTargets,
            persistDriveAnalysisReport: false,
            installedApplicationLoader: () async =>
                const <InstalledApplication>[
                  InstalledApplication(
                    id: 'acme',
                    name: 'Acme IDE',
                    uninstallCommand: r'"C:\Program Files\Acme\uninstall.exe"',
                  ),
                ],
            applicationUninstallLauncher: (InstalledApplication app) async {
              uninstalledName = app.name;
              return true;
            },
            driveEntryRecycler: (String path) async {
              recycledPath = path;
              return true;
            },
            driveAnalysisRunner: ({
              required CleanupCancellationToken cancellationToken,
              required void Function(SystemDriveAnalysisProgress progress)
              onProgress,
            }) async => analysis,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('分析全部磁盘占用（只读）'));
    await tester.pumpAndSettle();
    expect(find.text('软件占用与操作'), findsOneWidget);
    expect(find.text('Acme IDE'), findsOneWidget);
    expect(find.textContaining('安装 2.9 KB'), findsOneWidget);
    expect(find.textContaining('可清缓存 1000 B'), findsOneWidget);
    expect(find.textContaining(r'安装路径：C:\Program Files\Acme'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, '清理缓存'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-software-cache-clean')));
    await tester.pumpAndSettle();
    expect(recycledPath, r'C:\Users\me\AppData\Local\Acme\Cache');

    await tester.tap(find.widgetWithText(TextButton, '卸载'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-software-uninstall')));
    await tester.pumpAndSettle();
    expect(uninstalledName, 'Acme IDE');
  });

  testWidgets('可勾选多个磁盘并切换查看逐盘占用和可清理容量', (WidgetTester tester) async {
    final List<String> analyzedRoots = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CleanerTab(
            availableTargets: testTargets,
            persistDriveAnalysisReport: false,
            volumeLoader: () async => const <DiskVolumeInfo>[
              DiskVolumeInfo(
                rootPath: 'C:\\',
                name: 'C:（系统盘）',
                type: DiskVolumeType.fixed,
                totalBytes: 10000,
                freeBytes: 2000,
                availableBytes: 2000,
                isSystemVolume: true,
              ),
              DiskVolumeInfo(
                rootPath: 'D:\\',
                name: 'D:',
                type: DiskVolumeType.fixed,
                totalBytes: 20000,
                freeBytes: 7000,
                availableBytes: 7000,
                isSystemVolume: false,
              ),
            ],
            installedApplicationLoader: () async =>
                const <InstalledApplication>[],
            volumeDriveAnalysisRunner:
                (
                  String rootPath, {
                  required CleanupCancellationToken cancellationToken,
                  required void Function(SystemDriveAnalysisProgress progress)
                  onProgress,
                }) async {
                  analyzedRoots.add(rootPath);
                  final bool dataDrive = rootPath.startsWith('D:');
                  return SystemDriveAnalysis(
                    rootPath: rootPath,
                    entries: <SystemDriveUsageEntry>[
                      SystemDriveUsageEntry(
                        path: '${rootPath}Logs',
                        name: 'Logs',
                        sizeBytes: dataDrive ? 3000 : 1000,
                        kind: SystemDriveEntryKind.logsAndCaches,
                        reason: '日志目录',
                        isDirectory: true,
                        complete: true,
                        deletePolicy:
                            SystemDriveDeletePolicy.recycleAfterConfirmation,
                      ),
                    ],
                    cancelled: false,
                    unreadablePaths: 0,
                    visitedEntries: 2,
                    measuredBytes: dataDrive ? 13000 : 8000,
                    totalBytes: dataDrive ? 20000 : 10000,
                    freeBytes: dataDrive ? 7000 : 2000,
                    availableBytes: dataDrive ? 7000 : 2000,
                  );
                },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('C:（系统盘）'), findsOneWidget);
    expect(find.textContaining('D: · 本地磁盘'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('cleaner-volume-D:\\')));
    await tester.tap(find.byTooltip('分析全部磁盘占用（只读）'));
    await tester.pumpAndSettle();

    expect(analyzedRoots, containsAll(<String>['C:\\', 'D:\\']));
    expect(
      find.byKey(const ValueKey<String>('cleaner-volume-result-C:\\')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('cleaner-volume-result-D:\\')),
      findsOneWidget,
    );
    expect(find.textContaining('可清 2.9 KB'), findsOneWidget);
  });
}
