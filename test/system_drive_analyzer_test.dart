import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_task.dart';
import 'package:vibekits/features/cleaner/domain/system_drive_analysis_runner.dart';
import 'package:vibekits/features/cleaner/domain/system_drive_analysis_report.dart';
import 'package:vibekits/features/cleaner/domain/system_drive_analyzer.dart';
import 'package:vibekits/features/cleaner/domain/system_drive_insights.dart';

void main() {
  test('系统盘根目录按用途分类并统计真实字节', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'vk_drive_analysis_',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final Directory windows = Directory(
      '${root.path}${Platform.pathSeparator}Windows',
    )..createSync();
    final Directory programs = Directory(
      '${root.path}${Platform.pathSeparator}Program Files',
    )..createSync();
    final Directory users = Directory(
      '${root.path}${Platform.pathSeparator}Users',
    )..createSync();
    final Directory estlog = Directory(
      '${root.path}${Platform.pathSeparator}estlog',
    )..createSync();
    final Directory unknown = Directory(
      '${root.path}${Platform.pathSeparator}VendorScratch',
    )..createSync();
    File('${windows.path}${Platform.pathSeparator}system.bin')
        .writeAsBytesSync(List<int>.filled(11, 1));
    File('${programs.path}${Platform.pathSeparator}app.bin')
        .writeAsBytesSync(List<int>.filled(13, 2));
    File('${users.path}${Platform.pathSeparator}document.bin')
        .writeAsBytesSync(List<int>.filled(17, 3));
    File('${estlog.path}${Platform.pathSeparator}service.log')
        .writeAsBytesSync(List<int>.filled(19, 4));
    File('${unknown.path}${Platform.pathSeparator}mystery.tmp')
        .writeAsBytesSync(List<int>.filled(23, 5));
    File('${root.path}${Platform.pathSeparator}root.log')
        .writeAsBytesSync(List<int>.filled(29, 6));

    final SystemDriveAnalysis analysis = await SystemDriveAnalyzer.analyze(
      root.path,
    );

    expect(analysis.cancelled, isFalse);
    expect(analysis.measuredBytes, 112);
    expect(analysis.logicalMeasuredBytes, 112);
    expect(
      analysis.entries.singleWhere((entry) => entry.name == 'Windows').kind,
      SystemDriveEntryKind.windowsSystem,
    );
    expect(
      analysis.entries.singleWhere((entry) => entry.name == 'estlog').kind,
      SystemDriveEntryKind.logsAndCaches,
    );
    expect(
      analysis.entries
          .singleWhere((entry) => entry.name == 'VendorScratch')
          .needsReview,
      isTrue,
    );
    expect(
      analysis.entries.singleWhere((entry) => entry.name == 'root.log').kind,
      SystemDriveEntryKind.logsAndCaches,
    );
  });

  test('系统盘分析在独立 Isolate 中报告进度并可取消', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'vk_drive_analysis_cancel_',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final Directory users = Directory(
      '${root.path}${Platform.pathSeparator}Users',
    )..createSync();
    for (int index = 0; index < 1000; index++) {
      File('${users.path}${Platform.pathSeparator}$index.tmp')
          .writeAsStringSync('analysis-$index');
    }
    final CleanupCancellationToken token = CleanupCancellationToken();
    int progressEvents = 0;
    final SystemDriveAnalysis analysis =
        await SystemDriveAnalysisRunner.analyze(
          root.path,
          cancellationToken: token,
          onProgress: (SystemDriveAnalysisProgress progress) {
            progressEvents++;
            token.cancel();
          },
        );

    expect(progressEvents, greaterThan(0));
    expect(analysis.cancelled, isTrue);
    expect(analysis.visitedEntries, lessThan(1000));
  });

  test('一次扫描同时列出 Windows 组件、安装软件和用户软件数据', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'vk_drive_breakdown_',
    );
    addTearDown(() => root.deleteSync(recursive: true));
    final Directory acme = Directory(
      '${root.path}${Platform.pathSeparator}Program Files'
      '${Platform.pathSeparator}Acme IDE',
    )..createSync(recursive: true);
    final Directory winSxs = Directory(
      '${root.path}${Platform.pathSeparator}Windows'
      '${Platform.pathSeparator}WinSxS',
    )..createSync(recursive: true);
    final Directory code = Directory(
      '${root.path}${Platform.pathSeparator}Users'
      '${Platform.pathSeparator}tester${Platform.pathSeparator}AppData'
      '${Platform.pathSeparator}Local${Platform.pathSeparator}Code',
    )..createSync(recursive: true);
    File('${acme.path}${Platform.pathSeparator}app.bin')
        .writeAsBytesSync(List<int>.filled(101, 1));
    File('${winSxs.path}${Platform.pathSeparator}component.bin')
        .writeAsBytesSync(List<int>.filled(103, 2));
    File('${code.path}${Platform.pathSeparator}state.bin')
        .writeAsBytesSync(List<int>.filled(107, 3));

    final SystemDriveAnalysis analysis = await SystemDriveAnalyzer.analyze(
      root.path,
    );

    expect(
      analysis.breakdownEntries.any(
        (SystemDriveUsageEntry entry) =>
            entry.name == 'Acme IDE' && entry.sizeBytes == 101,
      ),
      isTrue,
    );
    expect(
      analysis.breakdownEntries.any(
        (SystemDriveUsageEntry entry) =>
            entry.name == 'WinSxS' && entry.sizeBytes == 103,
      ),
      isTrue,
    );
    expect(
      analysis.breakdownEntries.any(
        (SystemDriveUsageEntry entry) =>
            entry.name.contains('Code') &&
            entry.kind == SystemDriveEntryKind.softwareData &&
            entry.sizeBytes == 107,
      ),
      isTrue,
    );
  });

  test('完整空间报告保存容量、合理性和全部根项目', () async {
    final Directory output = Directory.systemTemp.createTempSync(
      'vk_drive_report_',
    );
    addTearDown(() => output.deleteSync(recursive: true));
    const SystemDriveAnalysis analysis = SystemDriveAnalysis(
      rootPath: r'C:\',
      entries: <SystemDriveUsageEntry>[
        SystemDriveUsageEntry(
          path: r'C:\Windows',
          name: 'Windows',
          sizeBytes: 600,
          kind: SystemDriveEntryKind.windowsSystem,
          reason: 'Windows 系统目录',
          isDirectory: true,
          complete: true,
        ),
        SystemDriveUsageEntry(
          path: r'C:\estlog',
          name: 'estlog',
          sizeBytes: 300,
          kind: SystemDriveEntryKind.logsAndCaches,
          reason: 'EST 日志',
          isDirectory: true,
          complete: true,
        ),
      ],
      cancelled: false,
      unreadablePaths: 2,
      visitedEntries: 20,
      measuredBytes: 900,
      totalBytes: 2000,
      freeBytes: 500,
      availableBytes: 450,
    );

    final File report = await SystemDriveAnalysisReportWriter.write(
      analysis,
      directory: output,
    );
    final Map<String, Object?> json =
        jsonDecode(await report.readAsString()) as Map<String, Object?>;
    final Map<String, Object?> disk = json['disk']! as Map<String, Object?>;
    final Map<String, Object?> insights =
        json['insights']! as Map<String, Object?>;
    final List<Object?> entries = json['entries']! as List<Object?>;

    expect(disk['usedBytes'], 1500);
    expect(disk['freeBytes'], 500);
    expect(disk['unaccountedBytes'], 600);
    expect(disk['logicalMeasuredBytes'], 900);
    expect(disk['logicalOvercountBytes'], 0);
    expect(entries, hasLength(2));
    expect((entries.last! as Map<String, Object?>)['assessment'], 'review');
    expect(json['version'], 3);
    expect(insights['systemBaseline'].toString(), contains('20–40 GiB'));
  });

  test('容量解释区分系统常见量、异常日志、未知目录和磁盘压力', () {
    const int gib = 1024 * 1024 * 1024;
    const SystemDriveAnalysis analysis = SystemDriveAnalysis(
      rootPath: r'C:\\',
      entries: <SystemDriveUsageEntry>[
        SystemDriveUsageEntry(
          path: r'C:\\Windows',
          name: 'Windows',
          sizeBytes: 30 * gib,
          kind: SystemDriveEntryKind.windowsSystem,
          reason: '系统目录',
          isDirectory: true,
          complete: true,
        ),
        SystemDriveUsageEntry(
          path: r'C:\\ESTLOG',
          name: 'ESTLOG',
          sizeBytes: 6 * gib,
          kind: SystemDriveEntryKind.logsAndCaches,
          reason: '软件日志',
          isDirectory: true,
          complete: true,
          deletePolicy: SystemDriveDeletePolicy.recycleAfterConfirmation,
        ),
        SystemDriveUsageEntry(
          path: r'C:\\VendorScratch',
          name: 'VendorScratch',
          sizeBytes: 2 * gib,
          kind: SystemDriveEntryKind.unknown,
          reason: '未知目录',
          isDirectory: true,
          complete: true,
          deletePolicy: SystemDriveDeletePolicy.recycleAfterConfirmation,
        ),
      ],
      breakdownEntries: <SystemDriveUsageEntry>[
        SystemDriveUsageEntry(
          path: r'C:\\Users\\tester\\AppData\\Local\\Acme',
          name: 'tester / AppData / Local / Acme',
          sizeBytes: 12 * gib,
          kind: SystemDriveEntryKind.softwareData,
          reason: 'Acme 软件数据',
          isDirectory: true,
          complete: true,
          ownerLabel: 'Acme',
          parentPath: r'C:\\Users',
        ),
      ],
      cancelled: false,
      unreadablePaths: 0,
      visitedEntries: 100,
      measuredBytes: 38 * gib,
      totalBytes: 100 * gib,
      freeBytes: 4 * gib,
      availableBytes: 4 * gib,
    );

    final SystemDriveInsights insights = SystemDriveInsights.from(analysis);
    final Map<String, SystemDriveEntryAssessment> byName =
        <String, SystemDriveEntryAssessment>{
          for (final SystemDriveEntryAssessment item in insights.assessments)
            item.entry.name: item,
        };

    expect(insights.storagePressure, SystemDriveAssessmentLevel.critical);
    expect(byName['Windows']?.level, SystemDriveAssessmentLevel.normal);
    expect(byName['ESTLOG']?.level, SystemDriveAssessmentLevel.critical);
    expect(byName['VendorScratch']?.level, SystemDriveAssessmentLevel.review);
    expect(
      byName['tester / AppData / Local / Acme']?.level,
      SystemDriveAssessmentLevel.review,
    );
    expect(insights.softwareOwners.single.entry.ownerLabel, 'Acme');
    expect(insights.priorities.first.entry.name, 'ESTLOG');
  });

  test('目录逻辑量超过物理已用量时显式报告硬链接重复计数', () {
    const SystemDriveAnalysis analysis = SystemDriveAnalysis(
      rootPath: r'C:\',
      entries: <SystemDriveUsageEntry>[],
      cancelled: false,
      unreadablePaths: 0,
      visitedEntries: 0,
      measuredBytes: 1800,
      totalBytes: 2000,
      freeBytes: 500,
      availableBytes: 500,
    );

    expect(analysis.usedBytes, 1500);
    expect(analysis.unaccountedBytes, 0);
    expect(analysis.logicalOvercountBytes, 300);
    expect(analysis.hasLogicalOvercount, isTrue);
  });
}
