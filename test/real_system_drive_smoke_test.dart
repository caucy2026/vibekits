import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_task.dart';
import 'package:vibekits/features/cleaner/domain/system_drive_analysis_report.dart';
import 'package:vibekits/features/cleaner/domain/system_drive_analysis_runner.dart';
import 'package:vibekits/features/cleaner/domain/system_drive_analyzer.dart';
import 'package:vibekits/features/cleaner/domain/system_drive_insights.dart';

void main() {
  final String? realDrive = Platform.environment['VIBEKITS_REAL_SYSTEM_DRIVE'];
  test(
    '真实系统盘只读扫描生成可解释报告',
    () async {
      final Directory output = Directory('build/acceptance');
      final SystemDriveAnalysis analysis =
          await SystemDriveAnalysisRunner.analyze(
            realDrive!,
            cancellationToken: CleanupCancellationToken(),
            onProgress: (SystemDriveAnalysisProgress progress) {
              if (progress.completedEntry != null) {
                // ignore: avoid_print
                print(
                  '${progress.completedRootEntries}/'
                  '${progress.totalRootEntries} '
                  '${progress.completedEntry!.path} '
                  '${progress.completedEntry!.sizeBytes}',
                );
              }
            },
          );
      final SystemDriveInsights insights = SystemDriveInsights.from(analysis);
      final File report = await SystemDriveAnalysisReportWriter.write(
        analysis,
        directory: output,
      );
      expect(analysis.cancelled, isFalse);
      expect(analysis.totalBytes, greaterThan(0));
      expect(analysis.usedBytes, greaterThan(0));
      expect(analysis.entries, isNotEmpty);
      expect(analysis.visitedEntries, greaterThan(0));
      expect(insights.systemBaseline, contains('20–40 GiB'));
      expect(report.existsSync(), isTrue);
      // ignore: avoid_print
      print('REAL_SYSTEM_DRIVE_REPORT=${report.absolute.path}');
    },
    skip: realDrive == null || realDrive.trim().isEmpty
        ? '设置 VIBEKITS_REAL_SYSTEM_DRIVE 后才执行真实磁盘只读扫描'
        : false,
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
