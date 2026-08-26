import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/archive/domain/disk_space.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_background_runner.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_decision_engine.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_rule_database.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_scanner.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_task.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_targets.dart';

void main() {
  test('live cleanup read-only audit', () async {
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
    final Stopwatch clock = Stopwatch()..start();
    final CleanupScanResult result = await CleanupBackgroundRunner.scanTargets(
      enabled,
      cancellationToken: CleanupCancellationToken(),
      onProgress: (_) {},
    );
    clock.stop();
    final DiskSpaceSnapshot disk = DiskSpace.snapshot(r'C:\')!;
    final CleanupDecisionPlan plan = CleanupDecisionEngine.buildPlan(
      result.candidates,
      freeSpaceRatio: disk.freeBytes / disk.totalBytes,
    );
    // ignore: avoid_print
    print(
      'READ_ONLY_AUDIT elapsed=${clock.elapsed.inSeconds}s '
      'candidates=${result.candidates.length} total=${_gib(result.candidateBytes)} GiB',
    );
    for (final CleanupDecisionTier tier in CleanupDecisionTier.values) {
      // ignore: avoid_print
      print(
        'DECISION\t${tier.name}\t'
        '${plan.candidatesFor(tier).length}\t${_gib(plan.bytesFor(tier))} GiB',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}

String _gib(int bytes) => (bytes / 1024 / 1024 / 1024).toStringAsFixed(3);
