import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_task.dart';
import 'package:vibekits/features/cleaner/domain/system_drive_analysis_runner.dart';
import 'package:vibekits/features/cleaner/domain/system_drive_analysis_report.dart';
import 'package:vibekits/features/cleaner/domain/system_drive_analyzer.dart';

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
    final List<Object?> entries = json['entries']! as List<Object?>;

    expect(disk['usedBytes'], 1500);
    expect(disk['freeBytes'], 500);
    expect(disk['unaccountedBytes'], 600);
    expect(entries, hasLength(2));
    expect((entries.last! as Map<String, Object?>)['assessment'], 'review');
  });
}
