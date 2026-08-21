import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_background_runner.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_rule_database.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_scanner.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_task.dart';
import 'package:vibekits/features/cleaner/domain/cleanup_targets.dart';

void main() {
  test('print current cleaner candidate gaps without deleting', () async {
    final List<CleanupScanTarget> targets = List<CleanupScanTarget>.of(
      CleanupTargetDiscovery.discover(),
    );
    final CleanupRuleDatabaseResult database = CleanupRuleDatabase.parse(
      File('assets/cleaner/windows_rules_v6.json').readAsStringSync(),
    );
    final Set<String> ids = targets.map((CleanupScanTarget item) => item.id).toSet();
    targets.addAll(database.targets.where((CleanupScanTarget item) => ids.add(item.id)));
    final List<CleanupScanTarget> enabled = targets
        .where((CleanupScanTarget item) =>
            item.defaultEnabled && item.id != 'system-drive-log-inventory')
        .toList(growable: false);
    final CleanupScanResult result = await CleanupBackgroundRunner.scanTargets(
      enabled,
      cancellationToken: CleanupCancellationToken(),
      onProgress: (_) {},
    );
    final Map<String, _Aggregate> groups = <String, _Aggregate>{};
    for (final CleanupCandidate item in result.candidates) {
      final String key = '${item.sourceLabel ?? '未知'} | '
          '${item.category.name} | ${item.riskLevel.name} | '
          '${item.defaultSelected ? 'default' : 'manual'}';
      (groups[key] ??= _Aggregate()).add(item);
    }
    final List<MapEntry<String, _Aggregate>> ordered = groups.entries.toList()
      ..sort((a, b) => b.value.bytes.compareTo(a.value.bytes));
    // ignore: avoid_print
    print('TOTAL\t${_gib(result.candidateBytes)} GiB\t${result.candidates.length} items');
    for (final MapEntry<String, _Aggregate> entry in ordered) {
      // ignore: avoid_print
      print('GROUP\t${_gib(entry.value.bytes)} GiB\t${entry.value.count}\t${entry.key}');
      for (final CleanupCandidate item in entry.value.largest.take(5)) {
        // ignore: avoid_print
        print('  TOP\t${_mib(item.size)} MiB\t${item.path}');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}

class _Aggregate {
  int bytes = 0;
  int count = 0;
  final List<CleanupCandidate> largest = <CleanupCandidate>[];

  void add(CleanupCandidate item) {
    bytes += item.size;
    count++;
    largest.add(item);
    largest.sort((a, b) => b.size.compareTo(a.size));
    if (largest.length > 5) largest.removeLast();
  }
}

String _gib(int value) => (value / 1024 / 1024 / 1024).toStringAsFixed(3);
String _mib(int value) => (value / 1024 / 1024).toStringAsFixed(1);
