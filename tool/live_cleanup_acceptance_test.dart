import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/archive/domain/disk_space.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_background_runner.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_deleter.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_decision_engine.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_report.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_rule_database.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_scanner.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_task.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_targets.dart';

void main() {
  test('live 10 GiB cleanup acceptance plan', () async {
    final List<CleanupScanTarget> targets = List<CleanupScanTarget>.of(
      CleanupTargetDiscovery.discover(),
    );
    final CleanupRuleDatabaseResult database = CleanupRuleDatabase.parse(
      File('assets/cleaner/windows_rules_v6.json').readAsStringSync(),
    );
    final Set<String> ids = targets.map((item) => item.id).toSet();
    targets.addAll(database.targets.where((item) => ids.add(item.id)));
    final List<CleanupScanTarget> enabled = targets
        .where(
          (CleanupScanTarget item) =>
              item.defaultEnabled && item.id != 'system-drive-log-inventory',
        )
        .toList(growable: false);
    final CleanupScanResult result = await CleanupBackgroundRunner.scanTargets(
      enabled,
      cancellationToken: CleanupCancellationToken(),
      onProgress: (_) {},
    );
    final DiskSpaceSnapshot currentDisk = DiskSpace.snapshot(r'C:\')!;
    final CleanupDecisionPlan intelligentPlan = CleanupDecisionEngine.buildPlan(
      result.candidates,
      freeSpaceRatio: currentDisk.freeBytes / currentDisk.totalBytes,
    );
    for (final CleanupDecisionTier tier in CleanupDecisionTier.values) {
      final List<CleanupCandidate> tierItems = intelligentPlan.candidatesFor(
        tier,
      );
      // ignore: avoid_print
      print(
        'DECISION\t${tier.name}\t${tierItems.length}\t'
        '${_gib(intelligentPlan.bytesFor(tier))} GiB',
      );
    }
    final List<CleanupCandidate> plan = result.candidates
        .where((candidate) {
          if (candidate.category == CleanupCategory.recycleBin) return true;
          if (candidate.riskLevel == CleanupRiskLevel.safe &&
              (candidate.category == CleanupCategory.userTemp ||
                  candidate.category == CleanupCategory.discoveredTransient)) {
            return true;
          }
          final String path = candidate.path.toLowerCase();
          if (candidate.defaultSelected) return true;
          return <String>[
            r'c:\users\caucy\.gradle\caches\',
            r'c:\users\caucy\appdata\local\pub\cache\',
            r'c:\users\caucy\appdata\local\npm-cache\',
            r'c:\users\caucy\.cache\puppeteer\',
            r'c:\users\caucy\appdata\local\ccache\',
            r'c:\users\caucy\appdata\local\microsoft\vscode-cpptools\ipch\',
            r'c:\users\caucy\appdata\roaming\tencent\wxwork\upgrade\',
            r'c:\users\caucy\appdata\roaming\tencent\wxwork\patch\',
            r'c:\users\caucy\appdata\roaming\tencent\wxwork\log\',
            r'c:\users\caucy\appdata\roaming\tencent\logs\',
            r'c:\users\caucy\appdata\roaming\tencent\wxwork\applet\',
            r'c:\users\caucy\appdata\roaming\tencent\wxwork\wmpf_applet\',
            r'c:\users\caucy\appdata\roaming\tencent\wxwork\wwmapp\',
            r'c:\users\caucy\appdata\local\antigravity-updater\',
            r'c:\users\caucy\appdata\local\bilibili-updater\',
            r'c:\users\caucy\appdata\local\m-ai-updater\',
            r'c:\users\caucy\appdata\local\wsmysqltools-updater\',
            r'c:\users\caucy\.codex\.tmp\',
            r'c:\users\caucy\.codex\cache\',
          ].any(path.startsWith);
        })
        .toList(growable: false);
    final int bytes = plan.fold(0, (total, item) => total + item.size);
    final Map<String, int> roots = <String, int>{};
    for (final CleanupCandidate item in plan) {
      final String root = _planRoot(item.path);
      roots[root] = (roots[root] ?? 0) + item.size;
    }
    // ignore: avoid_print
    print(
      'ACCEPTANCE_PLAN candidates=${plan.length} bytes=${_gib(bytes)} GiB '
      'allCandidates=${_gib(result.candidateBytes)} GiB',
    );
    for (final MapEntry<String, int> entry
        in roots.entries.toList()..sort((a, b) => b.value.compareTo(a.value))) {
      // ignore: avoid_print
      print('PLAN_ROOT\t${_gib(entry.value)} GiB\t${entry.key}');
    }
    final Set<String> selectedPaths = plan
        .map((CleanupCandidate item) => item.path)
        .toSet();
    final Map<String, int> excluded = <String, int>{};
    for (final CleanupCandidate item in result.candidates.where(
      (CleanupCandidate item) => !selectedPaths.contains(item.path),
    )) {
      final String key =
          '${item.sourceLabel ?? '未知来源'} | ${item.category.name} | ${item.riskLevel.name}';
      excluded[key] = (excluded[key] ?? 0) + item.size;
    }
    for (final MapEntry<String, int> entry
        in excluded.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value))) {
      // ignore: avoid_print
      print('EXCLUDED\t${_gib(entry.value)} GiB\t${entry.key}');
    }
    if (Platform.environment['VIBEKITS_LIVE_DELETE'] != 'YES') return;
    expect(bytes, greaterThanOrEqualTo(10 * 1024 * 1024 * 1024));
    final DiskSpaceSnapshot before = DiskSpace.snapshot(r'C:\')!;
    final DateTime startedAt = DateTime.now();
    final CleanupDeleteResult deletion =
        await CleanupBackgroundRunner.deleteCandidates(
          plan,
          cancellationToken: CleanupCancellationToken(),
          permanentFallback: false,
          onProgress: (progress) {
            if (progress.completed % 10000 == 0) {
              // ignore: avoid_print
              print('DELETE_PROGRESS ${progress.completed}/${progress.total}');
            }
          },
        );
    final File report = await CleanupReportWriter.write(
      deletion,
      startedAt: startedAt,
      finishedAt: DateTime.now(),
    );
    final DiskSpaceSnapshot after = DiskSpace.snapshot(r'C:\')!;
    final int actualReleased = after.freeBytes - before.freeBytes;
    // ignore: avoid_print
    print(
      'APP_CLEANUP_RESULT actual=${_gib(actualReleased)} GiB '
      'reported=${_gib(deletion.releasedBytes)} GiB '
      'success=${deletion.succeeded} skipped=${deletion.skipped} '
      'failed=${deletion.failed} beforeFree=${_gib(before.freeBytes)} GiB '
      'afterFree=${_gib(after.freeBytes)} GiB report=${report.path}',
    );
    expect(actualReleased, greaterThanOrEqualTo(10 * 1024 * 1024 * 1024));
  }, timeout: const Timeout(Duration(minutes: 20)));
}

String _planRoot(String path) {
  final String normalized = path.replaceAll('/', r'\');
  final List<String> markers = <String>[
    r'\.gradle\caches',
    r'\Pub\Cache',
    r'\npm-cache',
    r'\.cache\puppeteer',
    r'\ccache',
    r'\vscode-cpptools\ipch',
    r'\Tencent\WXWork\upgrade',
    r'\Tencent\WXWork\patch',
    r'\Tencent\WXWork\Log',
    r'\Tencent\Logs',
    r'\Tencent\WXWork\Applet',
    r'\Tencent\WXWork\wmpf_Applet',
    r'\Tencent\WXWork\wwmapp',
    r'\antigravity-updater',
    r'\bilibili-updater',
    r'\m-ai-updater',
    r'\wsmysqltools-updater',
    r'\.codex\.tmp',
    r'\.codex\cache',
  ];
  for (final String marker in markers) {
    final int index = normalized.toLowerCase().indexOf(marker.toLowerCase());
    if (index >= 0) return normalized.substring(0, index + marker.length);
  }
  return '其他默认安全候选';
}

String _gib(int bytes) => (bytes / 1024 / 1024 / 1024).toStringAsFixed(3);
